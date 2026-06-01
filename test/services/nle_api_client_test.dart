import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:rest_thermostat/models/schedule.dart';
import 'package:rest_thermostat/services/nle_api_client.dart';
import 'package:rest_thermostat/services/nle_error.dart';

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

    test('throws NleServerError on 500', () async {
      dioAdapter.onGet(
        '/api/devices',
        (server) => server.reply(500, {'error': 'server error'}),
      );

      expect(client.getDevices, throwsA(isA<NleServerError>()));
    });

    test('throws NleAuthError on 401', () async {
      dioAdapter.onGet(
        '/api/devices',
        (server) => server.reply(401, {'error': 'unauthorized'}),
      );

      expect(client.getDevices, throwsA(isA<NleAuthError>()));
    });

    test('throws NleAuthError on 403', () async {
      dioAdapter.onGet(
        '/api/devices',
        (server) => server.reply(403, {'error': 'forbidden'}),
      );

      expect(client.getDevices, throwsA(isA<NleAuthError>()));
    });

    test('throws NleRateLimitError on 429 with parsed Retry-After', () async {
      dioAdapter.onGet(
        '/api/devices',
        (server) => server.reply(
          429,
          {'error': 'too many requests'},
          headers: const {
            Headers.contentTypeHeader: [Headers.jsonContentType],
            'retry-after': ['45'],
          },
        ),
      );

      try {
        await client.getDevices();
        fail('expected throw');
      } on NleRateLimitError catch (e) {
        expect(e.retryAfter, const Duration(seconds: 45));
      }
    });

    test('throws NleParseError on malformed JSON shape', () async {
      // /api/devices is expected to return a Map; sending an array instead
      // forces the parse path to throw.
      dioAdapter.onGet(
        '/api/devices',
        (server) => server.reply(200, {'devices': 'not-a-list'}),
      );

      expect(client.getDevices, throwsA(isA<NleParseError>()));
    });
  });

  group('getSchedule', () {
    test('parses envelope and inner schedule from fixture', () async {
      final raw = File('test/fixtures/schedule_one.json').readAsStringSync();
      final body = jsonDecode(raw);

      dioAdapter.onGet(
        '/api/schedule',
        (server) => server.reply(200, body),
        queryParameters: {'serial': '02AA01AC041403JM'},
      );

      final schedule = await client.getSchedule('02AA01AC041403JM');
      expect(schedule, isNotNull);
      expect(schedule!.mode, 'HEAT');
      expect(schedule.eventsForDay(0), hasLength(4));
      expect(schedule.eventsForDay(4), isEmpty);
    });

    test('returns null when envelope.schedule is null', () async {
      dioAdapter.onGet(
        '/api/schedule',
        (server) => server.reply(200, {
          'serial': 'no-sched',
          'schedule': null,
          'object_revision': 0,
          'object_timestamp': 0,
        }),
        queryParameters: {'serial': 'no-sched'},
      );

      final schedule = await client.getSchedule('no-sched');
      expect(schedule, isNull);
    });

    test('throws NleServerError on 500', () async {
      dioAdapter.onGet(
        '/api/schedule',
        (server) => server.reply(500, {'error': 'server error'}),
        queryParameters: {'serial': 'abc'},
      );

      expect(() => client.getSchedule('abc'), throwsA(isA<NleServerError>()));
    });
  });

  group('sendCommand', () {
    test('POSTs /command with {serial, command, value}', () async {
      Map<String, dynamic>? capturedBody;
      dioAdapter.onPost(
        '/command',
        (server) => server.reply(200, {'ok': true}),
        data: Matchers.any,
      );
      // Use a fresh dio adapter that captures the request payload via
      // interceptor — http_mock_adapter ignores data when no matcher is set,
      // so we approximate by asserting on the inflight interceptor instead.
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedBody = options.data as Map<String, dynamic>?;
            handler.next(options);
          },
        ),
      );

      await client.sendCommand(
        serial: 'abc',
        command: 'set_mode',
        value: 'heat',
      );

      expect(capturedBody, isNotNull);
      expect(capturedBody!['serial'], 'abc');
      expect(capturedBody!['command'], 'set_mode');
      expect(capturedBody!['value'], 'heat');
    });

    test('throws NleServerError on persistent 500 (after one retry)', () async {
      // Reply 500 to every POST; the retry should also see 500 and the call
      // should ultimately throw. retryDelay overridden to zero so the test
      // doesn't spend 2 real seconds waiting.
      var calls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            handler.next(options);
          },
        ),
      );
      dioAdapter.onPost(
        '/command',
        (server) => server.reply(500, {'error': 'server error'}),
        data: Matchers.any,
      );
      await expectLater(
        () => client.sendCommand(
          serial: 'abc',
          command: 'set_mode',
          value: 'heat',
          retryDelay: Duration.zero,
        ),
        throwsA(isA<NleServerError>()),
      );
      // Initial attempt + 1 retry = 2 calls.
      expect(calls, 2);
    });

    test('does NOT retry on 4xx (auth/validation)', () async {
      var calls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            handler.next(options);
          },
        ),
      );
      dioAdapter.onPost(
        '/command',
        (server) => server.reply(401, {'error': 'unauthorized'}),
        data: Matchers.any,
      );
      await expectLater(
        () => client.sendCommand(
          serial: 'abc',
          command: 'set_mode',
          value: 'heat',
          retryDelay: Duration.zero,
        ),
        throwsA(isA<NleAuthError>()),
      );
      expect(calls, 1);
    });

    test('retry succeeds on second attempt (transient 503)', () async {
      // First call → 503 (via an interceptor that throws), second call → real
      // 200 from the mock adapter. http_mock_adapter doesn't queue responses,
      // so we use an interceptor to inject the first-call failure.
      var calls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            if (calls == 1) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: options,
                    statusCode: 503,
                    data: {'error': 'unavailable'},
                  ),
                ),
              );
              return;
            }
            handler.next(options);
          },
        ),
      );
      dioAdapter.onPost(
        '/command',
        (server) => server.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      await client.sendCommand(
        serial: 'abc',
        command: 'set_mode',
        value: 'heat',
        retryDelay: Duration.zero,
      );
      expect(calls, 2);
    });
  });

  group('setSchedule', () {
    test('POSTs /command with set_schedule + full schedule body', () async {
      Object? capturedValue;
      String? capturedCommand;
      dioAdapter.onPost(
        '/command',
        (server) => server.reply(200, {'ok': true}),
        data: Matchers.any,
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final body = options.data as Map<String, dynamic>;
            capturedCommand = body['command'] as String?;
            capturedValue = body['value'];
            handler.next(options);
          },
        ),
      );
      final schedule = Schedule.fromJson(
        jsonDecode(File('test/fixtures/schedule_one.json').readAsStringSync())
            as Map<String, dynamic>,
      );

      await client.setSchedule('abc', schedule);

      expect(capturedCommand, 'set_schedule');
      expect(capturedValue, isA<Map<String, dynamic>>());
      final value = capturedValue as Map<String, dynamic>;
      expect(value['days'], isA<Map<String, dynamic>>());
      expect((value['days'] as Map).keys, hasLength(7));
    });
  });

  group('factory NleApiClient.create', () {
    test('uses provided baseUrl without auth headers by default', () {
      final c = NleApiClient.create(baseUrl: 'http://nest.home:8082');
      expect(c.dio.options.headers.containsKey('Authorization'), isFalse);
      expect(
        c.dio.options.headers.containsKey('CF-Access-Client-Id'),
        isFalse,
      );
    });

    test('merges Authorization auth header when provided', () async {
      final c = NleApiClient.create(
        baseUrl: 'http://nest.home:8082',
        authHeaders: const {'Authorization': 'Bearer test-token'},
      );
      expect(c.dio.options.headers['Authorization'], 'Bearer test-token');
    });

    test('merges Cloudflare Access service-token headers when provided', () {
      final c = NleApiClient.create(
        baseUrl: 'http://nest.home:8082',
        authHeaders: const {
          'CF-Access-Client-Id': 'abc.access',
          'CF-Access-Client-Secret': 's3cr3t',
        },
      );
      expect(c.dio.options.headers['CF-Access-Client-Id'], 'abc.access');
      expect(c.dio.options.headers['CF-Access-Client-Secret'], 's3cr3t');
      expect(c.dio.options.headers.containsKey('Authorization'), isFalse);
    });

    test('disables redirect following (3xx must surface, not be chased)', () {
      final c = NleApiClient.create(baseUrl: 'http://nest.home:8082');
      expect(c.dio.options.followRedirects, isFalse);
    });

    test(
      'sends CF Access headers on EVERY request (GET devices + POST command)',
      () async {
        // Build via the production factory so we exercise the real header
        // plumbing (BaseOptions.headers), not a hand-rolled Dio.
        final c = NleApiClient.create(
          baseUrl: 'http://nest.home:8082',
          authHeaders: const {
            'CF-Access-Client-Id': 'abc.access',
            'CF-Access-Client-Secret': 's3cr3t',
          },
        );
        final captured = <String, Map<String, dynamic>>{};
        c.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              captured[options.path] = Map<String, dynamic>.from(
                options.headers,
              );
              handler.next(options);
            },
          ),
        );
        final adapter = DioAdapter(dio: c.dio);
        adapter.onGet(
          '/api/devices',
          (s) => s.reply(200, {'total': 0, 'devices': <dynamic>[]}),
        );
        adapter.onPost(
          '/command',
          (s) => s.reply(200, {'ok': true}),
          data: Matchers.any,
        );

        await c.fetchDevicesJson();
        await c.sendCommand(serial: 'X', command: 'set_mode', value: 'heat');

        for (final path in ['/api/devices', '/command']) {
          expect(
            captured[path]?['CF-Access-Client-Id'],
            'abc.access',
            reason: 'CF client id missing on $path',
          );
          expect(
            captured[path]?['CF-Access-Client-Secret'],
            's3cr3t',
            reason: 'CF client secret missing on $path',
          );
        }
      },
    );
  });
}
