import 'dart:convert';

/// Per DESIGN §7.2 and §7.3: persisted auth choice for the NLE reverse proxy.
sealed class AuthConfig {
  const AuthConfig();

  /// Encoded `Authorization` header value, or null when no auth is configured.
  String? get authorizationHeader;

  /// Persistence tag — used as the `auth_type` value in storage.
  String get tag;
}

class AuthNone extends AuthConfig {
  const AuthNone();
  @override
  String? get authorizationHeader => null;
  @override
  String get tag => 'none';
}

class AuthBasic extends AuthConfig {
  final String username;
  final String password;
  const AuthBasic({required this.username, required this.password});

  @override
  String? get authorizationHeader {
    final encoded = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $encoded';
  }

  @override
  String get tag => 'basic';
}

class AuthBearer extends AuthConfig {
  final String token;
  const AuthBearer({required this.token});

  @override
  String? get authorizationHeader => 'Bearer $token';

  @override
  String get tag => 'bearer';
}
