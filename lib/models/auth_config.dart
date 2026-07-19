import 'dart:convert';

/// Per DESIGN §7.2 and §7.3: persisted auth choice for the NLE reverse proxy.
sealed class AuthConfig {
  const AuthConfig();

  /// Headers this config contributes to every request. Empty when no auth is
  /// configured. This is the canonical surface the HTTP client consumes — it
  /// covers both `Authorization`-style schemes (Basic/Bearer) and custom
  /// header pairs like Cloudflare Access service tokens.
  Map<String, String> get headers;

  /// Convenience accessor for the `Authorization` header value, or null when
  /// this config sets none. Header-based schemes that don't use
  /// `Authorization` (e.g. Cloudflare Access) return null here.
  String? get authorizationHeader => headers['Authorization'];

  /// Persistence tag — used as the `auth_type` value in storage.
  String get tag;
}

class AuthNone extends AuthConfig {
  const AuthNone();
  @override
  Map<String, String> get headers => const {};
  @override
  String get tag => 'none';
}

class AuthBasic extends AuthConfig {
  final String username;
  final String password;
  const AuthBasic({required this.username, required this.password});

  @override
  Map<String, String> get headers {
    final encoded = base64Encode(utf8.encode('$username:$password'));
    return {'Authorization': 'Basic $encoded'};
  }

  @override
  String get tag => 'basic';
}

class AuthBearer extends AuthConfig {
  final String token;
  const AuthBearer({required this.token});

  @override
  Map<String, String> get headers => {'Authorization': 'Bearer $token'};

  @override
  String get tag => 'bearer';
}

/// Cloudflare Access service token (DESIGN §7.2). Authenticates the client to
/// the Cloudflare Access edge sitting in front of the NLE reverse proxy via a
/// header pair, rather than an `Authorization` header. Cloudflare strips these
/// headers before the request reaches the origin, so the origin sees no auth —
/// which is why this is modeled as a mutually-exclusive auth choice rather
/// than layered on top of Basic/Bearer.
class AuthCfServiceToken extends AuthConfig {
  final String clientId;
  final String clientSecret;
  const AuthCfServiceToken({
    required this.clientId,
    required this.clientSecret,
  });

  @override
  Map<String, String> get headers => {
    'CF-Access-Client-Id': clientId,
    'CF-Access-Client-Secret': clientSecret,
  };

  @override
  String get tag => 'cf_service_token';
}
