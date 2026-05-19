import 'package:dio/dio.dart';

import '../models/devices_response.dart';

class NleApiClient {
  final Dio dio;

  const NleApiClient({required this.dio});

  factory NleApiClient.create({
    required String baseUrl,
    String? authorizationHeader,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Authorization': ?authorizationHeader},
      ),
    );
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
}
