import 'dart:io' show HttpDate;

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
    if (code == 401 || code == 403) {
      return NleAuthError(statusCode: code, serverMessage: extracted);
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
    if (code >= 400 && code < 500) {
      return NleClientError(statusCode: code, serverMessage: extracted);
    }
    return NleNetworkError(cause: e);
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

/// Indirect network failure: connect/read/send timeout, connection-refused,
/// DNS, TLS bad-cert, cancellation, or anything else dio surfaces as a
/// non-`badResponse` exception type. Transient by default — retry the
/// command once, then surface to the user.
class NleNetworkError extends NleError {
  final DioException cause;
  const NleNetworkError({required this.cause, super.serverMessage});

  @override
  String toString() => 'NleNetworkError(${cause.type}: ${cause.message})';
}

/// 401 or 403. Surfaces via the deep-link snackbar that routes the user to
/// Settings → Connection with the auth section pre-expanded.
class NleAuthError extends NleError {
  final int statusCode;
  const NleAuthError({required this.statusCode, super.serverMessage});

  @override
  String toString() =>
      'NleAuthError($statusCode${serverMessage == null ? "" : ": $serverMessage"})';
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
