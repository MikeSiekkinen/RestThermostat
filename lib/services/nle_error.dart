import 'dart:io' show HandshakeException, HttpDate, SocketException;

import 'package:dio/dio.dart';

/// Typed errors thrown by [NleApiClient] per `docs/DESIGN.md` §15.1.
///
/// Replaces raw [DioException] at the public API boundary so UI catches can
/// dispatch on intent (transient network blip vs. auth failure vs. rate limit)
/// without re-deriving the classifier at every call site.
///
/// Construct via [NleError.fromDio] (HTTP-level errors) or directly (parse
/// errors, which originate outside dio).
sealed class NleError implements Exception {
  /// Optional user-facing copy candidate extracted from the server response
  /// body (typically `error` or `message` keys). Callers may surface this
  /// verbatim or fall back to their own generic copy.
  final String? serverMessage;

  const NleError({this.serverMessage});

  /// Classify a [DioException] into the appropriate [NleError] subclass.
  /// `Retry-After` is parsed from the response headers when present (429).
  static NleError fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return NleNetworkError(cause: e);
      case DioExceptionType.badResponse:
        break;
    }
    final response = e.response;
    final code = response?.statusCode ?? 0;
    final body = response?.data;
    final extracted = _extractServerMessage(body);
    final cfAccess = _looksLikeCloudflareAccess(response);
    if (code == 401 || code == 403) {
      return NleAuthError(
        statusCode: code,
        isCloudflareAccess: cfAccess,
        serverMessage: extracted,
      );
    }
    if (code == 429) {
      return NleRateLimitError(
        retryAfter: parseRetryAfter(response?.headers.value('retry-after')),
        serverMessage: extracted,
      );
    }
    if (code >= 500 && code < 600) {
      return NleServerError(statusCode: code, serverMessage: extracted);
    }
    // A JSON control API never legitimately redirects. A 3xx means an identity
    // / access gate (Cloudflare Access, an SSO reverse proxy) intercepted the
    // request — treat it as an auth failure so the user is routed to fix
    // credentials rather than told the network is down. Redirect-following is
    // disabled on the client (see NleApiClient.create) so these arrive here as
    // `badResponse` 3xx with their `Location` / `WWW-Authenticate` headers.
    if (code >= 300 && code < 400) {
      return NleAuthError(
        statusCode: code,
        isCloudflareAccess: cfAccess,
        serverMessage: extracted,
      );
    }
    if (code >= 400 && code < 500) {
      return NleClientError(statusCode: code, serverMessage: extracted);
    }
    return NleNetworkError(cause: e);
  }

  /// Heuristic: does this response look like a Cloudflare Access challenge?
  /// Access returns a 302 to `*.cloudflareaccess.com` and tags responses with
  /// `WWW-Authenticate: Cloudflare-Access`. Lets the UI point the user at the
  /// service-token fields instead of generic credentials.
  static bool _looksLikeCloudflareAccess(Response<dynamic>? response) {
    if (response == null) return false;
    final headers = response.headers;
    final wwwAuth = headers.value('www-authenticate')?.toLowerCase() ?? '';
    if (wwwAuth.contains('cloudflare-access')) return true;
    final location = headers.value('location');
    if (location == null || location.isEmpty) return false;
    final host = Uri.tryParse(location)?.host.toLowerCase() ?? '';
    return host == 'cloudflareaccess.com' ||
        host.endsWith('.cloudflareaccess.com');
  }

  static String? _extractServerMessage(Object? body) {
    if (body is Map) {
      final candidate = body['error'] ?? body['message'];
      if (candidate is String && candidate.isNotEmpty) return candidate;
    } else if (body is String && body.isNotEmpty) {
      return body;
    }
    return null;
  }

  /// Parse `Retry-After` per RFC 9110 §10.2.3: integer seconds OR an HTTP-date.
  /// Returns `null` for missing/malformed values; callers fall back to a
  /// fixed backoff (DESIGN §15.1 says 30s). Public for testing.
  static Duration? parseRetryAfter(String? raw, {DateTime Function()? now}) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final asInt = int.tryParse(trimmed);
    if (asInt != null) return Duration(seconds: asInt.clamp(0, 86400));
    try {
      final when = HttpDate.parse(trimmed);
      final delta = when.difference((now ?? DateTime.now)());
      return delta.isNegative ? Duration.zero : delta;
    } catch (_) {
      return null;
    }
  }
}

/// The specific shape of a network failure, derived from the underlying
/// [DioException]. Lets the UI show a cause-specific message ("connection
/// refused" vs. "name not found" vs. "timed out") instead of one catch-all.
enum NleNetworkErrorKind {
  /// Couldn't establish a TCP connection in time.
  connectionTimeout,

  /// Connected, but the server didn't send a response in time.
  receiveTimeout,

  /// Couldn't finish sending the request in time.
  sendTimeout,

  /// The host actively refused the connection (nothing listening on that
  /// host:port, or a closed port). The most common "wrong port" symptom.
  connectionRefused,

  /// DNS lookup failed — the hostname doesn't resolve.
  dnsFailure,

  /// TLS handshake / certificate failure (e.g. https to a plain-http port,
  /// or an untrusted/expired certificate).
  tlsFailure,

  /// Anything else dio couldn't connect for (unreachable network, reset, …).
  unknown,
}

/// Indirect network failure: connect/read/send timeout, connection-refused,
/// DNS, TLS bad-cert, cancellation, or anything else dio surfaces as a
/// non-`badResponse` exception type. Transient by default — retry the
/// command once, then surface to the user.
class NleNetworkError extends NleError {
  final DioException cause;
  const NleNetworkError({required this.cause, super.serverMessage});

  /// Classify [cause] into a [NleNetworkErrorKind]. For connection-level
  /// failures dio nests the real reason in [DioException.error] (a
  /// [SocketException] or [HandshakeException]), so we inspect that to tell
  /// "name not found" apart from "connection refused".
  NleNetworkErrorKind get kind {
    switch (cause.type) {
      case DioExceptionType.connectionTimeout:
        return NleNetworkErrorKind.connectionTimeout;
      case DioExceptionType.receiveTimeout:
        return NleNetworkErrorKind.receiveTimeout;
      case DioExceptionType.sendTimeout:
        return NleNetworkErrorKind.sendTimeout;
      case DioExceptionType.badCertificate:
        return NleNetworkErrorKind.tlsFailure;
      case DioExceptionType.connectionError:
      case DioExceptionType.cancel:
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return _classifyUnderlying(cause.error);
    }
  }

  static NleNetworkErrorKind _classifyUnderlying(Object? error) {
    if (error is HandshakeException) return NleNetworkErrorKind.tlsFailure;
    if (error is SocketException) {
      final osError = error.osError;
      final message =
          '${error.message} ${osError?.message ?? ''}'.toLowerCase();
      if (message.contains('failed host lookup') ||
          message.contains('nodename nor servname') ||
          message.contains('name or service not known') ||
          message.contains('no address associated')) {
        return NleNetworkErrorKind.dnsFailure;
      }
      // ECONNREFUSED is 61 on macOS/BSD, 111 on Linux.
      if (message.contains('connection refused') ||
          osError?.errorCode == 61 ||
          osError?.errorCode == 111) {
        return NleNetworkErrorKind.connectionRefused;
      }
    }
    return NleNetworkErrorKind.unknown;
  }

  /// `host:port` the failed request was aimed at, or empty when unknown.
  /// Safe to surface to the user / logs — never contains credentials.
  String get target {
    final uri = cause.requestOptions.uri;
    return uri.host.isEmpty ? '' : '${uri.host}:${uri.port}';
  }

  @override
  String toString() => 'NleNetworkError($kind, ${cause.type}: ${cause.message})';
}

/// An authentication / access-gate failure: a 401 or 403 from the origin, or a
/// 3xx redirect to an identity provider (Cloudflare Access, SSO). Surfaces via
/// the deep-link snackbar that routes the user to Settings → Connection with
/// the auth section pre-expanded.
class NleAuthError extends NleError {
  final int statusCode;

  /// True when the failure is a Cloudflare Access gate (a redirect to the
  /// Access login, or a 401/403 carrying `WWW-Authenticate: Cloudflare-Access`)
  /// rather than the origin rejecting Basic/Bearer credentials. Lets the UI
  /// point the user specifically at the service-token fields.
  final bool isCloudflareAccess;

  const NleAuthError({
    required this.statusCode,
    this.isCloudflareAccess = false,
    super.serverMessage,
  });

  @override
  String toString() =>
      'NleAuthError($statusCode${isCloudflareAccess ? ", cloudflare-access" : ""}'
      '${serverMessage == null ? "" : ": $serverMessage"})';
}

/// 429. [retryAfter] is the parsed value of the response's `Retry-After` header
/// when present; `null` means the server didn't include one and callers should
/// fall back to a fixed backoff.
class NleRateLimitError extends NleError {
  final Duration? retryAfter;
  const NleRateLimitError({this.retryAfter, super.serverMessage});

  @override
  String toString() => 'NleRateLimitError(retryAfter: $retryAfter)';
}

/// 5xx. Already retried once by [NleApiClient.sendCommand] for the write path;
/// this is the post-retry failure. The poll path doesn't retry — the next 20s
/// cadence cycle is the retry per DESIGN §3.3.
class NleServerError extends NleError {
  final int statusCode;
  const NleServerError({required this.statusCode, super.serverMessage});

  @override
  String toString() =>
      'NleServerError($statusCode${serverMessage == null ? "" : ": $serverMessage"})';
}

/// 4xx other than 401/403/429. The server validated the request and rejected
/// it; retries won't help and the UI should reflect the rejection to the user.
class NleClientError extends NleError {
  final int statusCode;
  const NleClientError({required this.statusCode, super.serverMessage});

  @override
  String toString() =>
      'NleClientError($statusCode${serverMessage == null ? "" : ": $serverMessage"})';
}

/// 200 OK but the body wasn't shaped the way the client expected — a JSON
/// parse failure, a missing required field, an unexpected type, etc. Carries
/// a short [responseExcerpt] (≤200 chars, credentials never present in NLE
/// response bodies per the server schema) that callers log via [AppLogger]
/// for postmortem.
class NleParseError extends NleError {
  final String responseExcerpt;
  final Object? cause;
  const NleParseError({
    required this.responseExcerpt,
    this.cause,
    super.serverMessage,
  });

  @override
  String toString() => 'NleParseError(excerpt: $responseExcerpt)';
}
