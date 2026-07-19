import 'package:dio/dio.dart';

import 'app_logger.dart';

/// Key used to stash the request start time inside [RequestOptions.extra]
/// so the response/error handlers can compute the round-trip duration.
const String _startKey = '_nle_log_start';

/// Dio interceptor that records HTTP request/response metadata to
/// [AppLogger] per DESIGN §15.2.
///
/// **Logged:** method, path, status code, duration in ms. On error, the dio
/// error type (timeout / connection / bad-response / …) and status if present.
///
/// **NEVER logged:** request or response bodies (the `/api/devices` response
/// includes per-device `api_key` values), request headers (would leak
/// `Authorization`), or query strings (defense in depth — current endpoints
/// don't put secrets in query strings, but the rule keeps it that way).
///
/// Tests must verify the formatted message never contains a credential. See
/// `test/services/nle_api_logging_interceptor_test.dart`.
class NleApiLoggingInterceptor extends Interceptor {
  final AppLogger logger;
  final DateTime Function() clock;

  NleApiLoggingInterceptor({required this.logger, DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = clock();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final method = response.requestOptions.method.toUpperCase();
    final path = response.requestOptions.path;
    final status = response.statusCode ?? 0;
    final ms = _elapsedMs(response.requestOptions);
    logger.info('$method $path → $status (${ms}ms)');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final method = err.requestOptions.method.toUpperCase();
    final path = err.requestOptions.path;
    final status = err.response?.statusCode;
    final ms = _elapsedMs(err.requestOptions);
    final klass = _errorClass(err);
    final statusFragment = status != null ? '$status' : 'no-response';
    // Include the target host:port and the low-level reason so a connection
    // failure shows what it actually tried to reach (e.g. a wrong port). The
    // URI host/port carry no credentials, and the reason is the OS/socket
    // message — never a header or body. Query strings remain omitted (see the
    // class doc); RequestOptions.path is just the path.
    final target = _target(err.requestOptions);
    final reason = _reasonFragment(err);
    logger.error(
      '$method $target$path → $statusFragment $klass$reason (${ms}ms)',
    );
    handler.next(err);
  }

  String _target(RequestOptions options) {
    final uri = options.uri;
    return uri.host.isEmpty ? '' : '${uri.host}:${uri.port}';
  }

  /// The nested socket/handshake reason for connection-level failures, e.g.
  /// `[Connection refused]`. Empty for `badResponse` (the status already
  /// explains it) and when dio carries no underlying error.
  String _reasonFragment(DioException err) {
    if (err.type == DioExceptionType.badResponse) return '';
    final underlying = err.error?.toString() ?? err.message;
    if (underlying == null || underlying.isEmpty) return '';
    return ' [$underlying]';
  }

  int _elapsedMs(RequestOptions options) {
    final start = options.extra[_startKey];
    if (start is! DateTime) return 0;
    return clock().difference(start).inMilliseconds;
  }

  String _errorClass(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
        return 'connection-timeout';
      case DioExceptionType.sendTimeout:
        return 'send-timeout';
      case DioExceptionType.receiveTimeout:
        return 'receive-timeout';
      case DioExceptionType.transformTimeout:
        return 'transform-timeout';
      case DioExceptionType.badCertificate:
        return 'bad-certificate';
      case DioExceptionType.badResponse:
        return 'bad-response';
      case DioExceptionType.cancel:
        return 'cancelled';
      case DioExceptionType.connectionError:
        return 'connection-error';
      case DioExceptionType.unknown:
        return 'unknown';
    }
  }
}
