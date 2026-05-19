import 'package:dio/dio.dart';

import '../models/devices_response.dart';
import '../models/schedule.dart';
import 'app_logger.dart';
import 'nle_api_logging_interceptor.dart';

class NleApiClient {
  final Dio dio;

  const NleApiClient({required this.dio});

  /// Production factory. Installs the diagnostic-logging interceptor so every
  /// HTTP call appears in [AppLogger]; logs the configured auth presence once
  /// at construction time (never the credential value).
  ///
  /// The raw [NleApiClient] constructor intentionally does NOT install the
  /// interceptor — that keeps mock-adapter-based unit tests of unrelated code
  /// from leaking entries into the global logger.
  factory NleApiClient.create({
    required String baseUrl,
    String? authorizationHeader,
    AppLogger? logger,
  }) {
    final effectiveLogger = logger ?? AppLogger.instance;
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Authorization': ?authorizationHeader},
      ),
    );
    dio.interceptors.add(NleApiLoggingInterceptor(logger: effectiveLogger));
    effectiveLogger.info('auth: ${_authPresence(authorizationHeader)}');
    return NleApiClient(dio: dio);
  }

  Future<DevicesResponse> getDevices() async {
    return DevicesResponse.fromJson(await fetchDevicesJson());
  }

  /// Same call as [getDevices] but returns the raw JSON body so callers (e.g.
  /// [PollingDeviceStateSource]) can cache it verbatim without re-serializing
  /// the parsed object graph.
  Future<Map<String, dynamic>> fetchDevicesJson() async {
    final response = await dio.get<Map<String, dynamic>>('/api/devices');
    return response.data!;
  }

  /// Fetch the active schedule for [serial], or `null` if the server has none
  /// stored for that device (404). Other status codes still throw — the caller
  /// surfaces them through the standard error UI.
  Future<Schedule?> getSchedule(String serial) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/api/devices/$serial/schedule',
      );
      return Schedule.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Issue a write command per DESIGN §16.4. Body shape is
  /// `{serial, command, value}` posted to `/command`.
  ///
  /// On success, an `AppLogger.commandIssued` entry is appended via the
  /// underlying logger so the diagnostic log shows the command name + value
  /// (never any credential). HTTP-level metadata is also captured by the dio
  /// interceptor automatically.
  ///
  /// Errors propagate as [DioException] for the caller to surface in UI.
  Future<void> sendCommand({
    required String serial,
    required String command,
    required Object? value,
  }) async {
    AppLogger.instance.commandIssued(command, value);
    await dio.post<dynamic>(
      '/command',
      data: {'serial': serial, 'command': command, 'value': value},
    );
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

  /// Maps a raw `Authorization` header value to a presence label
  /// (`"bearer"`/`"basic"`/`"none"`) without leaking the credential itself.
  static String _authPresence(String? header) {
    if (header == null || header.isEmpty) return 'none';
    final lower = header.toLowerCase();
    if (lower.startsWith('bearer')) return 'bearer';
    if (lower.startsWith('basic')) return 'basic';
    return 'other';
  }
}
