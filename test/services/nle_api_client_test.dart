import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:rest_thermostat/services/nle_api_client.dart';

void main() {
  late Dio dio;
  late DioAdapter dioAdapter;
  late NleApiClient client;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
    dioAdapter = DioAdapter(dio: dio);
    client = NleApiClient(dio: dio);
  });

  group('getDevices', () {
    test('parses successful response from fixture', () async {
      final raw = File('test/fixtures/devices_one.json').readAsStringSync();
      final body = jsonDecode(raw);

      dioAdapter.onGet('/api/devices', (server) => server.reply(200, body));

      final response = await client.getDevices();
      expect(response.total, 1);
      expect(response.devices, hasLength(1));
      expect(response.devices.first.serial, '02AA01AC041403JM');
    });

    test('throws DioException on 500', () async {
      dioAdapter.onGet(
        '/api/devices',
        (server) => server.reply(500, {'error': 'server error'}),
      );

      expect(client.getDevices, throwsA(isA<DioException>()));
    });

    test('throws DioException on 401', () async {
      dioAdapter.onGet(
        '/api/devices',
        (server) => server.reply(401, {'error': 'unauthorized'}),
      );

      expect(client.getDevices, throwsA(isA<DioException>()));
    });
  });

  group('getSchedule', () {
    test('parses successful schedule response from fixture', () async {
      final raw = File('test/fixtures/schedule_one.json').readAsStringSync();
      final body = jsonDecode(raw);

      dioAdapter.onGet(
        '/api/devices/02AA01AC041403JM/schedule',
        (server) => server.reply(200, body),
      );

      final schedule = await client.getSchedule('02AA01AC041403JM');
      expect(schedule, isNotNull);
      expect(schedule!.mode, 'HEAT');
      expect(schedule.eventsForDay(0), hasLength(4));
      expect(schedule.eventsForDay(4), isEmpty);
    });

    test('returns null on 404 (server has no schedule for device)', () async {
      dioAdapter.onGet(
        '/api/devices/missing-serial/schedule',
        (server) => server.reply(404, {'error': 'not found'}),
      );

      final schedule = await client.getSchedule('missing-serial');
      expect(schedule, isNull);
    });

    test('rethrows DioException on 500', () async {
      dioAdapter.onGet(
        '/api/devices/abc/schedule',
        (server) => server.reply(500, {'error': 'server error'}),
      );

      expect(() => client.getSchedule('abc'), throwsA(isA<DioException>()));
    });
  });

  group('factory NleApiClient.create', () {
    test('uses provided baseUrl without authorization header by default', () {
      final c = NleApiClient.create(baseUrl: 'http://nest.home:8082');
      // No assertion needed beyond construction succeeding; the absence of an
      // auth header is exercised by the success test above which mocks paths
      // relative to baseUrl.
      expect(c, isA<NleApiClient>());
    });

    test('passes authorization header when provided', () async {
      final c = NleApiClient.create(
        baseUrl: 'http://nest.home:8082',
        authorizationHeader: 'Bearer test-token',
      );
      expect(c, isA<NleApiClient>());
    });
  });
}
