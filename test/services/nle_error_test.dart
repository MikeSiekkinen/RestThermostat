import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/services/nle_error.dart';

DioException _badResponse({
  required int code,
  Object? body,
  Map<String, List<String>>? headers,
}) {
  final req = RequestOptions(path: '/x');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: req,
      statusCode: code,
      data: body,
      headers: Headers.fromMap(headers ?? const {}),
    ),
  );
}

DioException _typed(DioExceptionType type) {
  return DioException(
    requestOptions: RequestOptions(path: '/x'),
    type: type,
  );
}

void main() {
  group('NleError.fromDio classification', () {
    test('connection-error → NleNetworkError', () {
      final e = NleError.fromDio(_typed(DioExceptionType.connectionError));
      expect(e, isA<NleNetworkError>());
    });

    test('receive-timeout → NleNetworkError', () {
      final e = NleError.fromDio(_typed(DioExceptionType.receiveTimeout));
      expect(e, isA<NleNetworkError>());
    });

    test('bad-cert → NleNetworkError', () {
      final e = NleError.fromDio(_typed(DioExceptionType.badCertificate));
      expect(e, isA<NleNetworkError>());
    });

    test('401 → NleAuthError(401)', () {
      final e = NleError.fromDio(_badResponse(code: 401)) as NleAuthError;
      expect(e.statusCode, 401);
    });

    test('403 → NleAuthError(403)', () {
      final e = NleError.fromDio(_badResponse(code: 403)) as NleAuthError;
      expect(e.statusCode, 403);
    });

    test('404 → NleClientError(404)', () {
      final e = NleError.fromDio(_badResponse(code: 404)) as NleClientError;
      expect(e.statusCode, 404);
    });

    test('500 → NleServerError(500)', () {
      final e = NleError.fromDio(_badResponse(code: 500)) as NleServerError;
      expect(e.statusCode, 500);
    });

    test('302 to Cloudflare Access login → NleAuthError(isCloudflareAccess)', () {
      final e =
          NleError.fromDio(
                _badResponse(
                  code: 302,
                  headers: {
                    'location': [
                      'https://team.cloudflareaccess.com/cdn-cgi/access/login/x',
                    ],
                    'www-authenticate': ['Cloudflare-Access'],
                  },
                ),
              )
              as NleAuthError;
      expect(e.statusCode, 302);
      expect(e.isCloudflareAccess, isTrue);
    });

    test('generic 302 (no Access markers) → NleAuthError, not CF', () {
      final e =
          NleError.fromDio(
                _badResponse(
                  code: 302,
                  headers: {
                    'location': ['https://example.com/login'],
                  },
                ),
              )
              as NleAuthError;
      expect(e.statusCode, 302);
      expect(e.isCloudflareAccess, isFalse);
    });

    test('403 carrying Cloudflare-Access challenge sets the flag', () {
      final e =
          NleError.fromDio(
                _badResponse(
                  code: 403,
                  headers: {
                    'www-authenticate': ['Cloudflare-Access'],
                  },
                ),
              )
              as NleAuthError;
      expect(e.isCloudflareAccess, isTrue);
    });

    test('429 with integer Retry-After parses to Duration', () {
      final e =
          NleError.fromDio(
                _badResponse(
                  code: 429,
                  headers: {
                    'retry-after': ['30'],
                  },
                ),
              )
              as NleRateLimitError;
      expect(e.retryAfter, const Duration(seconds: 30));
    });

    test('429 without Retry-After surfaces null retryAfter', () {
      final e = NleError.fromDio(_badResponse(code: 429)) as NleRateLimitError;
      expect(e.retryAfter, isNull);
    });

    test('extracts serverMessage from {error: "..."} body', () {
      final e =
          NleError.fromDio(
                _badResponse(code: 400, body: {'error': 'bad serial'}),
              )
              as NleClientError;
      expect(e.serverMessage, 'bad serial');
    });

    test('extracts serverMessage from {message: "..."} body', () {
      final e =
          NleError.fromDio(
                _badResponse(code: 400, body: {'message': 'bad serial'}),
              )
              as NleClientError;
      expect(e.serverMessage, 'bad serial');
    });

    test('extracts serverMessage from raw string body', () {
      final e =
          NleError.fromDio(_badResponse(code: 400, body: 'plain text reason'))
              as NleClientError;
      expect(e.serverMessage, 'plain text reason');
    });

    test('serverMessage is null when body is empty', () {
      final e = NleError.fromDio(_badResponse(code: 400)) as NleClientError;
      expect(e.serverMessage, isNull);
    });
  });

  group('NleNetworkError.kind classification', () {
    NleNetworkError net(
      DioExceptionType type, {
      Object? error,
      String baseUrl = 'http://nest.home:8082',
    }) {
      return NleError.fromDio(
            DioException(
              requestOptions: RequestOptions(path: '/api/devices', baseUrl: baseUrl),
              type: type,
              error: error,
            ),
          )
          as NleNetworkError;
    }

    test('connectionTimeout type → connectionTimeout kind', () {
      expect(
        net(DioExceptionType.connectionTimeout).kind,
        NleNetworkErrorKind.connectionTimeout,
      );
    });

    test('receiveTimeout type → receiveTimeout kind', () {
      expect(
        net(DioExceptionType.receiveTimeout).kind,
        NleNetworkErrorKind.receiveTimeout,
      );
    });

    test('badCertificate type → tlsFailure kind', () {
      expect(
        net(DioExceptionType.badCertificate).kind,
        NleNetworkErrorKind.tlsFailure,
      );
    });

    test('connectionError wrapping HandshakeException → tlsFailure', () {
      expect(
        net(
          DioExceptionType.connectionError,
          error: const HandshakeException('handshake failed'),
        ).kind,
        NleNetworkErrorKind.tlsFailure,
      );
    });

    test('SocketException "Connection refused" → connectionRefused', () {
      expect(
        net(
          DioExceptionType.connectionError,
          error: const SocketException(
            'Connection refused',
            osError: OSError('Connection refused', 61),
          ),
        ).kind,
        NleNetworkErrorKind.connectionRefused,
      );
    });

    test('SocketException "Failed host lookup" → dnsFailure', () {
      expect(
        net(
          DioExceptionType.connectionError,
          error: const SocketException(
            "Failed host lookup: 'nest.home'",
            osError: OSError('nodename nor servname provided', 8),
          ),
        ).kind,
        NleNetworkErrorKind.dnsFailure,
      );
    });

    test('connectionError with no underlying error → unknown', () {
      expect(
        net(DioExceptionType.connectionError).kind,
        NleNetworkErrorKind.unknown,
      );
    });

    test('target exposes host:port from the request', () {
      expect(
        net(DioExceptionType.connectionError).target,
        'nest.home:8082',
      );
    });
  });

  group('NleError.parseRetryAfter', () {
    test('integer seconds → Duration', () {
      expect(NleError.parseRetryAfter('30'), const Duration(seconds: 30));
    });

    test('clamps to 24h max', () {
      expect(NleError.parseRetryAfter('999999')?.inSeconds, 86400);
    });

    test('HTTP-date in the future → positive duration', () {
      final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
      final later = now.add(const Duration(seconds: 90));
      final asHttpDate = _toHttpDate(later);
      final got = NleError.parseRetryAfter(asHttpDate, now: () => now);
      expect(got, isNotNull);
      // Allow ±1s tolerance — HTTP-date second precision can round.
      expect((got!.inSeconds - 90).abs(), lessThanOrEqualTo(1));
    });

    test('HTTP-date in the past → Duration.zero (not negative)', () {
      final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
      final earlier = now.subtract(const Duration(seconds: 60));
      final got = NleError.parseRetryAfter(
        _toHttpDate(earlier),
        now: () => now,
      );
      expect(got, Duration.zero);
    });

    test('malformed string → null', () {
      expect(NleError.parseRetryAfter('not-a-date'), isNull);
    });

    test('null/empty → null', () {
      expect(NleError.parseRetryAfter(null), isNull);
      expect(NleError.parseRetryAfter(''), isNull);
      expect(NleError.parseRetryAfter('   '), isNull);
    });
  });
}

/// Format a UTC DateTime as an RFC 7231 IMF-fixdate string ("Sun, 06 Nov 1994
/// 08:49:37 GMT"). Inlined here so the tests don't pull in another package.
String _toHttpDate(DateTime utc) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = utc.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${days[d.weekday - 1]}, ${two(d.day)} ${months[d.month - 1]} ${d.year} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)} GMT';
}
