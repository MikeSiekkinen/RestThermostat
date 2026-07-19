import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/auth_config.dart';
import 'package:rest_thermostat/services/backup/config_snapshot.dart';

ConfigSnapshot _snap({
  String? serverUrl,
  AuthConfig auth = const AuthNone(),
  String? activeSerial,
  Map<String, String> overrides = const {},
  String? numeralFont,
  String? timeFieldPalette,
}) => ConfigSnapshot(
  serverUrl: serverUrl,
  auth: auth,
  activeSerial: activeSerial,
  deviceNameOverrides: overrides,
  numeralFont: numeralFont,
  timeFieldPalette: timeFieldPalette,
);

void main() {
  group('ConfigSnapshot round-trip', () {
    test('carries every config field through toJson/fromJson', () {
      final original = _snap(
        serverUrl: 'https://nest.example.com',
        auth: const AuthBasic(username: 'user', password: 'pass'),
        activeSerial: '02AA01AC12345678',
        overrides: {'02AA01AC12345678': 'Living Room'},
        numeralFont: 'anton',
        timeFieldPalette: 'neutral',
      );

      final restored = ConfigSnapshot.fromJson(original.toJson());

      expect(restored.serverUrl, original.serverUrl);
      expect(restored.activeSerial, original.activeSerial);
      expect(restored.deviceNameOverrides, original.deviceNameOverrides);
      expect(restored.numeralFont, 'anton');
      expect(restored.timeFieldPalette, 'neutral');
      expect(restored.auth, isA<AuthBasic>());
      final auth = restored.auth as AuthBasic;
      expect(auth.username, 'user');
      expect(auth.password, 'pass');
    });

    test('each auth subtype survives the round-trip', () {
      for (final auth in <AuthConfig>[
        const AuthNone(),
        const AuthBasic(username: 'u', password: 'p'),
        const AuthBearer(token: 'tok'),
        const AuthCfServiceToken(clientId: 'cid', clientSecret: 'csecret'),
      ]) {
        final restored = ConfigSnapshot.fromJson(
          _snap(auth: auth).toJson(),
        ).auth;
        expect(restored.runtimeType, auth.runtimeType);
        expect(restored.headers, auth.headers);
        expect(restored.tag, auth.tag);
      }
    });

    test('omits absent optional keys from JSON', () {
      final json = _snap(auth: const AuthNone()).toJson();
      expect(json.containsKey('server_url'), isFalse);
      expect(json.containsKey('active_serial'), isFalse);
      expect(json.containsKey('device_name_overrides'), isFalse);
      expect(json.containsKey('numeral_font'), isFalse);
      // Auth is always present (even AuthNone) so the type is explicit.
      expect(json['auth'], {'type': 'none'});
    });
  });

  group('ConfigSnapshot forward/backward compatibility', () {
    test('ignores unknown keys from a future schema', () {
      final json = {
        'server_url': 'https://x',
        'auth': {'type': 'none'},
        'future_feature_flag': true,
        'some_new_setting': {'nested': 42},
      };
      final restored = ConfigSnapshot.fromJson(json);
      expect(restored.serverUrl, 'https://x');
      expect(restored.auth, isA<AuthNone>());
    });

    test('tolerates a completely empty object', () {
      final restored = ConfigSnapshot.fromJson({});
      expect(restored.serverUrl, isNull);
      expect(restored.activeSerial, isNull);
      expect(restored.numeralFont, isNull);
      expect(restored.timeFieldPalette, isNull);
      expect(restored.deviceNameOverrides, isEmpty);
      expect(restored.auth, isA<AuthNone>());
    });

    test('unknown auth type falls back to AuthNone', () {
      final restored = ConfigSnapshot.fromJson({
        'auth': {'type': 'quantum-oauth', 'token': 'x'},
      });
      expect(restored.auth, isA<AuthNone>());
    });
  });
}
