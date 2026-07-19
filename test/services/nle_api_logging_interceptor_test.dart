import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:rest_thermostat/services/app_logger.dart';
import 'package:rest_thermostat/services/nle_api_logging_interceptor.dart';

/// Synthetic credentials & sensitive payload values that MUST NOT appear in
/// any log entry produced by the interceptor. Each test asserts that the
/// captured log messages do not contain these substrings, even substring-of.
const _bearerToken = 'SYNTHETIC_BEARER_TOKEN_DO_NOT_LOG';
const _basicCreds = 'SYNTHETIC_BASIC_CREDS_DO_NOT_LOG';
const _sensitiveApiKey = 'a.SYNTHETIC_API_KEY_DO_NOT_LOG';
const _sensitiveBodyMarker = 'SYNTHETIC_RESPONSE_BODY_DO_NOT_LOG';
const _cfClientId = 'SYNTHETIC_CF_CLIENT_ID_DO_NOT_LOG.access';
const _cfClientSecret = 'SYNTHETIC_CF_CLIENT_SECRET_DO_NOT_LOG';

void main() {
  late AppLogger logger;
  late Dio dio;
  late DioAdapter adapter;

  setUp(() {
    logger = AppLogger(capacity: 100);
    dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
    adapter = DioAdapter(dio: dio);
    dio.interceptors.add(NleApiLoggingInterceptor(logger: logger));
  });

  void expectNoLeaks(List<LogEntry> entries) {
    for (final entry in entries) {
      expect(
        entry.message,
        isNot(contains(_bearerToken)),
        reason: 'bearer token leaked into "${entry.message}"',
      );
      expect(
        entry.message,
        isNot(contains(_basicCreds)),
        reason: 'basic creds leaked into "${entry.message}"',
      );
      expect(
        entry.message,
        isNot(contains(_sensitiveApiKey)),
        reason: 'api_key leaked into "${entry.message}"',
      );
      expect(
        entry.message,
        isNot(contains(_sensitiveBodyMarker)),
        reason: 'response body leaked into "${entry.message}"',
      );
      expect(
        entry.message.toLowerCase(),
        isNot(contains('authorization')),
        reason: 'Authorization header name leaked into log message',
      );
      expect(
        entry.message,
        isNot(contains(_cfClientId)),
        reason: 'CF client id leaked into "${entry.message}"',
      );
      expect(
        entry.message,
        isNot(contains(_cfClientSecret)),
        reason: 'CF client secret leaked into "${entry.message}"',
      );
      expect(
        entry.message.toLowerCase(),
        isNot(contains('cf-access-client-secret')),
        reason: 'CF secret header name leaked into log message',
      );
    }
  }

  test('successful request logs method, path, status, and duration', () async {
    adapter.onGet(
      '/api/devices',
      (server) => server.reply(200, {
        'devices': [
          {'serial': 'X', 'api_key': _sensitiveApiKey},
        ],
        'marker': _sensitiveBodyMarker,
      }),
    );

    await dio.get(
      '/api/devices',
      options: Options(headers: {'Authorization': 'Bearer $_bearerToken'}),
    );

    expect(logger.entries, hasLength(1));
    final entry = logger.entries.first;
    expect(entry.level, LogLevel.info);
    expect(
      entry.message,
      matches(RegExp(r'^GET /api/devices → 200 \(\d+ms\)$')),
    );
    expectNoLeaks(logger.entries);
  });

  test('5xx response logs as error with status + bad-response class', () async {
    adapter.onGet(
      '/api/devices',
      (server) => server.reply(500, {'msg': _sensitiveBodyMarker}),
    );

    try {
      await dio.get(
        '/api/devices',
        options: Options(headers: {'Authorization': 'Bearer $_bearerToken'}),
      );
      fail('expected DioException');
    } on DioException catch (_) {
      // expected
    }

    expect(logger.entries, hasLength(1));
    final entry = logger.entries.first;
    expect(entry.level, LogLevel.error);
    expect(entry.message, startsWith('GET '));
    expect(entry.message, contains('/api/devices'));
    expect(entry.message, contains('500'));
    expect(entry.message, contains('bad-response'));
    expectNoLeaks(logger.entries);
  });

  test(
    'connection error logs an error entry with no-response status',
    () async {
      adapter.onGet(
        '/api/devices',
        (server) => server.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/devices'),
            reason: 'boom',
          ),
        ),
      );

      try {
        await dio.get(
          '/api/devices',
          options: Options(headers: {'Authorization': 'Basic $_basicCreds'}),
        );
        fail('expected DioException');
      } on DioException catch (_) {
        // expected
      }

      expect(logger.entries, hasLength(1));
      final entry = logger.entries.first;
      expect(entry.level, LogLevel.error);
      expect(entry.message, contains('no-response'));
      expectNoLeaks(logger.entries);
    },
  );

  test(
    'duration is measured from onRequest to onResponse via injected clock',
    () async {
      final times = <DateTime>[
        DateTime.utc(2026, 1, 1, 12, 0, 0),
        DateTime.utc(2026, 1, 1, 12, 0, 0, 250),
      ];
      var idx = 0;
      DateTime fakeClock() =>
          times[idx < times.length ? idx++ : times.length - 1];

      logger = AppLogger(capacity: 10);
      final dio2 = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
      final adapter2 = DioAdapter(dio: dio2);
      dio2.interceptors.add(
        NleApiLoggingInterceptor(logger: logger, clock: fakeClock),
      );
      adapter2.onGet('/api/devices', (s) => s.reply(200, {'ok': true}));

      await dio2.get('/api/devices');
      expect(logger.entries.first.message, contains('(250ms)'));
    },
  );

  test(
    'connection error logs target host:port and the underlying reason',
    () async {
      adapter.onGet(
        '/api/devices',
        (server) => server.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(
              path: '/api/devices',
              baseUrl: 'http://test.local:8082',
            ),
            reason: 'connection refused',
            error: const SocketException('Connection refused'),
          ),
        ),
      );

      try {
        await dio.get(
          '/api/devices',
          options: Options(headers: {'Authorization': 'Basic $_basicCreds'}),
        );
        fail('expected DioException');
      } on DioException catch (_) {
        // expected
      }

      final message = logger.entries.first.message;
      expect(message, contains('test.local:8082'));
      expect(message, contains('Connection refused'));
      expect(message, contains('connection-error'));
      expectNoLeaks(logger.entries);
    },
  );

  test('POST requests log the method correctly', () async {
    adapter.onPost(
      '/command',
      (server) => server.reply(200, {}),
      data: {'serial': 'X', 'command': 'set_mode', 'value': 'heat'},
    );

    await dio.post(
      '/command',
      data: {'serial': 'X', 'command': 'set_mode', 'value': 'heat'},
      options: Options(headers: {'Authorization': 'Bearer $_bearerToken'}),
    );

    expect(logger.entries.first.message, startsWith('POST /command → 200'));
    expectNoLeaks(logger.entries);
  });

  test('Cloudflare service-token headers never leak into logs — success, '
      'error response, and network failure', () async {
    final cfHeaders = {
      'CF-Access-Client-Id': _cfClientId,
      'CF-Access-Client-Secret': _cfClientSecret,
    };

    adapter.onGet('/api/devices', (server) => server.reply(200, {}));
    await dio.get('/api/devices', options: Options(headers: cfHeaders));

    adapter.onGet(
      '/api/schedule',
      (server) => server.reply(403, {'error': 'denied'}),
    );
    try {
      await dio.get('/api/schedule', options: Options(headers: cfHeaders));
      fail('expected DioException');
    } on DioException catch (_) {}

    adapter.onGet(
      '/status',
      (server) => server.throws(
        0,
        DioException(
          requestOptions: RequestOptions(path: '/status'),
          type: DioExceptionType.connectionError,
          error: const SocketException('Connection refused'),
        ),
      ),
    );
    try {
      await dio.get('/status', options: Options(headers: cfHeaders));
      fail('expected DioException');
    } on DioException catch (_) {}

    expect(logger.entries, isNotEmpty);
    expectNoLeaks(logger.entries);
  });
}
