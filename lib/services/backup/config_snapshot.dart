import '../../models/auth_config.dart';

/// The full set of user-owned app configuration that a backup captures and a
/// restore rewrites (Issue #109, ADR-0001). This is the *plaintext* payload —
/// [BackupCodec] handles turning it into a passphrase-encrypted envelope.
///
/// Every field is nullable/defaulted so the model tolerates partial or
/// forward-versioned files: [fromJson] ignores unknown keys and accepts missing
/// ones. Scope is deliberately limited to config; device *state* (the
/// `last_state_cache`) and server-side data (schedules, eco temps) are not
/// included. Temperature scale is server-driven (DESIGN §8.1) and not captured.
class ConfigSnapshot {
  final String? serverUrl;
  final AuthConfig auth;
  final String? activeSerial;
  final Map<String, String> deviceNameOverrides;

  /// Appearance prefs, stored as the enum `.name` string exactly as their
  /// notifiers persist them (`NumeralFont.name` / `TimeFieldPalette.name`). Kept
  /// as opaque strings here so this model doesn't depend on the settings enums;
  /// the notifiers own validation on restore.
  final String? numeralFont;
  final String? timeFieldPalette;

  const ConfigSnapshot({
    required this.serverUrl,
    required this.auth,
    required this.activeSerial,
    required this.deviceNameOverrides,
    required this.numeralFont,
    required this.timeFieldPalette,
  });

  Map<String, dynamic> toJson() => {
    if (serverUrl != null) 'server_url': serverUrl,
    'auth': _authToJson(auth),
    if (activeSerial != null) 'active_serial': activeSerial,
    if (deviceNameOverrides.isNotEmpty)
      'device_name_overrides': deviceNameOverrides,
    if (numeralFont != null) 'numeral_font': numeralFont,
    if (timeFieldPalette != null) 'time_field_palette': timeFieldPalette,
  };

  /// Rebuilds a snapshot from a decrypted payload. Unknown keys are ignored and
  /// missing keys fall back to null/empty, so a file written by a future build
  /// with extra keys still restores everything this build understands.
  factory ConfigSnapshot.fromJson(Map<String, dynamic> json) {
    final overridesRaw = json['device_name_overrides'];
    final overrides = <String, String>{};
    if (overridesRaw is Map) {
      overridesRaw.forEach((k, v) {
        if (k is String && v is String) overrides[k] = v;
      });
    }
    return ConfigSnapshot(
      serverUrl: json['server_url'] as String?,
      auth: _authFromJson(json['auth']),
      activeSerial: json['active_serial'] as String?,
      deviceNameOverrides: overrides,
      numeralFont: json['numeral_font'] as String?,
      timeFieldPalette: json['time_field_palette'] as String?,
    );
  }

  /// Auth serialized as `{type, ...creds}` keyed on [AuthConfig.tag], the same
  /// discriminator used for on-disk storage. Only the active scheme's secrets
  /// are written, matching the store's "clear then write active set" posture.
  static Map<String, dynamic> _authToJson(AuthConfig auth) => switch (auth) {
    AuthNone() => {'type': auth.tag},
    AuthBasic(:final username, :final password) => {
      'type': auth.tag,
      'username': username,
      'password': password,
    },
    AuthBearer(:final token) => {'type': auth.tag, 'token': token},
    AuthCfServiceToken(:final clientId, :final clientSecret) => {
      'type': auth.tag,
      'client_id': clientId,
      'client_secret': clientSecret,
    },
  };

  static AuthConfig _authFromJson(dynamic raw) {
    if (raw is! Map) return const AuthNone();
    final type = raw['type'];
    return switch (type) {
      'basic' => AuthBasic(
        username: (raw['username'] as String?) ?? '',
        password: (raw['password'] as String?) ?? '',
      ),
      'bearer' => AuthBearer(token: (raw['token'] as String?) ?? ''),
      'cf_service_token' => AuthCfServiceToken(
        clientId: (raw['client_id'] as String?) ?? '',
        clientSecret: (raw['client_secret'] as String?) ?? '',
      ),
      _ => const AuthNone(),
    };
  }
}
