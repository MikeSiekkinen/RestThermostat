import 'package:dio/dio.dart';

import '../models/devices_response.dart';
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
