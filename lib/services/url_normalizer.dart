/// Normalizes a user-typed server URL per DESIGN §7.5.
///
/// Rules:
/// - Missing scheme → default `http://`.
/// - Missing port → default `:8082`.
/// - Strip trailing slash.
/// - Reject malformed input (empty host, bad scheme, parse failure).
class UrlNormalizationException implements Exception {
  final String message;
  const UrlNormalizationException(this.message);
  @override
  String toString() => 'UrlNormalizationException: $message';
}

String normalizeServerUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const UrlNormalizationException('Server address is required.');
  }

  final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';

  final Uri uri;
  try {
    uri = Uri.parse(withScheme);
  } on FormatException catch (e) {
    throw UrlNormalizationException('Invalid URL: ${e.message}');
  }

  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw UrlNormalizationException(
      'Scheme must be http or https (got "${uri.scheme}").',
    );
  }
  if (uri.host.isEmpty) {
    throw const UrlNormalizationException('Missing hostname.');
  }
  if (uri.path.isNotEmpty && uri.path != '/') {
    throw const UrlNormalizationException(
      'Path component is not supported; enter only host[:port].',
    );
  }

  final port = uri.hasPort ? uri.port : 8082;
  return '${uri.scheme}://${uri.host}:$port';
}
