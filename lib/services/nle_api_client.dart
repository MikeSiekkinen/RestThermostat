import 'package:dio/dio.dart';

import '../models/devices_response.dart';
import '../models/schedule.dart';
import 'app_logger.dart';
import 'nle_api_logging_interceptor.dart';
import 'nle_error.dart';

class NleApiClient {
  final Dio dio;
  final AppLogger? _logger;

  // Initializing-formal would require the constructor param to be named
  // `_logger` (matching the field), which is awkward for a public API. The
  // `:` form keeps the named arg `logger`.
  // ignore: prefer_initializing_formals
  const NleApiClient({required this.dio, AppLogger? logger}) : _logger = logger;

  /// Production factory. Installs the diagnostic-logging interceptor so every
  /// HTTP call appears in [AppLogger]; logs the configured auth presence once
  /// at construction time (never the credential value).
  ///
  /// [authHeaders] are merged verbatim into every request — this covers both
  /// `Authorization`-style schemes and custom header pairs (e.g. Cloudflare
  /// Access service tokens). See [AuthConfig.headers].
  ///
  /// The raw [NleApiClient] constructor intentionally does NOT install the
  /// interceptor — that keeps mock-adapter-based unit tests of unrelated code
  /// from leaking entries into the global logger.
  factory NleApiClient.create({
    required String baseUrl,
    Map<String, String>? authHeaders,
    AppLogger? logger,
  }) {
    final effectiveLogger = logger ?? AppLogger.instance;
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        headers: {...?authHeaders},
        // The NLE control API returns JSON and never legitimately redirects.
        // A 3xx means an access gate (Cloudflare Access, an SSO proxy)
        // intercepted the request — don't chase it into an HTML login page;
        // surface the 3xx so NleError.fromDio can classify it as an auth gate.
        followRedirects: false,
      ),
    );
    dio.interceptors.add(NleApiLoggingInterceptor(logger: effectiveLogger));
    effectiveLogger.info('auth: ${_authPresence(authHeaders)}');
    return NleApiClient(dio: dio, logger: effectiveLogger);
  }

  AppLogger get _log => _logger ?? AppLogger.instance;

  Future<DevicesResponse> getDevices() async {
    final raw = await fetchDevicesJson();
    return _parse(raw, () => DevicesResponse.fromJson(raw));
  }

  /// Same call as [getDevices] but returns the raw JSON body so callers (e.g.
  /// [PollingDeviceStateSource]) can cache it verbatim without re-serializing
  /// the parsed object graph. Throws [NleError] subclasses on HTTP failure;
  /// the body's shape isn't validated here (callers do that).
  Future<Map<String, dynamic>> fetchDevicesJson() async {
    try {
      final response = await dio.get<Map<String, dynamic>>('/api/devices');
      return response.data!;
    } on DioException catch (e) {
      throw NleError.fromDio(e);
    }
  }

  /// Fetch the active schedule for [serial], or `null` if the server has none
  /// stored for that device. Per the Control API spec the endpoint always
  /// returns 200 with the response wrapped as
  /// `{serial, schedule, object_revision, object_timestamp}`; `schedule` is
  /// `null` when no schedule is stored.
  Future<Schedule?> getSchedule(String serial) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await dio.get<Map<String, dynamic>>(
        '/api/schedule',
        queryParameters: {'serial': serial},
      );
    } on DioException catch (e) {
      throw NleError.fromDio(e);
    }
    final body = response.data;
    return _parse(body, () {
      final inner = body?['schedule'];
      if (inner is! Map<String, dynamic>) return null;
      return Schedule.fromJson(inner);
    });
  }

  /// Issue a write command per DESIGN §16.4. Body shape is
  /// `{serial, command, value}` posted to `/command`.
  ///
  /// On success, an `AppLogger.commandIssued` entry is appended via the
  /// underlying logger so the diagnostic log shows the command name + value
  /// (never any credential). HTTP-level metadata is also captured by the dio
  /// interceptor automatically.
  ///
  /// Retries once with a 2s backoff on transient failures (network errors and
  /// 5xx responses) per DESIGN §2.3. 4xx responses (validation/auth) are
  /// returned to the caller immediately — retrying won't help and the user
  /// needs the snackbar surface. Errors propagate as [NleError] subclasses.
  ///
  /// [retryDelay] is provided as an override for tests so they can run
  /// without waiting on real wall-clock time.
  Future<void> sendCommand({
    required String serial,
    required String command,
    required Object? value,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    _log.commandIssued(command, value);
    final data = {'serial': serial, 'command': command, 'value': value};
    try {
      await dio.post<dynamic>('/command', data: data);
      return;
    } on DioException catch (e) {
      if (!_isTransient(e)) throw NleError.fromDio(e);
      await Future<void>.delayed(retryDelay);
      try {
        await dio.post<dynamic>('/command', data: data);
      } on DioException catch (e2) {
        throw NleError.fromDio(e2);
      }
    }
  }

  static bool _isTransient(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.transformTimeout:
        return true;
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        return code >= 500 && code < 600;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return false;
    }
  }

  /// Thin wrapper over [sendCommand] that posts a full schedule object as the
  /// `set_schedule` value. Schedule writes are full-replace per DESIGN §6.1.
  Future<void> setSchedule(String serial, Schedule schedule) {
    return sendCommand(
      serial: serial,
      command: 'set_schedule',
      value: schedule.toJson(),
    );
  }

  /// Wrap a synchronous JSON-shaping callback so any thrown
  /// `FormatException`/`TypeError`/`NoSuchMethodError` becomes an
  /// [NleParseError] with a short excerpt logged for postmortem.
  T _parse<T>(Object? body, T Function() builder) {
    try {
      return builder();
    } catch (e) {
      final excerpt = _excerpt(body);
      _log.error('parse failed', data: {'excerpt': excerpt});
      throw NleParseError(responseExcerpt: excerpt, cause: e);
    }
  }

  static String _excerpt(Object? body) {
    final s = body?.toString() ?? '';
    return s.length <= 200 ? s : '${s.substring(0, 200)}…';
  }

  /// Maps the configured auth headers to a presence label
  /// (`"bearer"`/`"basic"`/`"cf-service-token"`/`"none"`/`"other"`) without
  /// leaking any credential value.
  static String _authPresence(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return 'none';
    if (headers.containsKey('CF-Access-Client-Id')) return 'cf-service-token';
    final auth = headers['Authorization']?.toLowerCase() ?? '';
    if (auth.startsWith('bearer')) return 'bearer';
    if (auth.startsWith('basic')) return 'basic';
    return 'other';
  }
}
