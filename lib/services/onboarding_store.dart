import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_config.dart';

class OnboardingConfig {
  final String? serverUrl;
  final AuthConfig auth;
  final String? activeSerial;
  final bool isComplete;

  const OnboardingConfig({
    required this.serverUrl,
    required this.auth,
    required this.activeSerial,
    required this.isComplete,
  });
}

/// Persistence boundary for the onboarding flow. Implementations split storage
/// per DESIGN §7.3/§12.1: credentials in secure storage, non-secrets in
/// SharedPreferences. The interface lets widget tests substitute an in-memory
/// fake without touching platform channels.
abstract class OnboardingStore {
  Future<OnboardingConfig> read();
  Future<void> saveServerUrl(String url);
  Future<void> saveAuth(AuthConfig auth);
  Future<void> saveActiveSerial(String serial);
  Future<void> markComplete();
}

class FlutterOnboardingStore implements OnboardingStore {
  static const _kServerUrl = 'server_url';
  static const _kActiveSerial = 'active_device_serial';
  static const _kComplete = 'onboarding_complete';
  static const _kAuthType = 'auth_type';
  static const _kBasicUser = 'auth_basic_username';
  static const _kBasicPass = 'auth_basic_password';
  static const _kBearer = 'auth_bearer_token';

  final FlutterSecureStorage _secure;
  final Future<SharedPreferences> Function() _prefs;

  FlutterOnboardingStore({
    FlutterSecureStorage? secureStorage,
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _secure = secureStorage ?? const FlutterSecureStorage(),
       _prefs = prefsLoader ?? SharedPreferences.getInstance;

  @override
  Future<OnboardingConfig> read() async {
    final prefs = await _prefs();
    final type = await _secure.read(key: _kAuthType) ?? 'none';
    final auth = switch (type) {
      'basic' => AuthBasic(
        username: await _secure.read(key: _kBasicUser) ?? '',
        password: await _secure.read(key: _kBasicPass) ?? '',
      ),
      'bearer' => AuthBearer(token: await _secure.read(key: _kBearer) ?? ''),
      _ => const AuthNone(),
    };
    return OnboardingConfig(
      serverUrl: prefs.getString(_kServerUrl),
      auth: auth,
      activeSerial: prefs.getString(_kActiveSerial),
      isComplete: prefs.getBool(_kComplete) ?? false,
    );
  }

  @override
  Future<void> saveServerUrl(String url) async {
    final prefs = await _prefs();
    await prefs.setString(_kServerUrl, url);
  }

  @override
  Future<void> saveAuth(AuthConfig auth) async {
    await _secure.write(key: _kAuthType, value: auth.tag);
    switch (auth) {
      case AuthNone():
        await _secure.delete(key: _kBasicUser);
        await _secure.delete(key: _kBasicPass);
        await _secure.delete(key: _kBearer);
      case AuthBasic(:final username, :final password):
        await _secure.write(key: _kBasicUser, value: username);
        await _secure.write(key: _kBasicPass, value: password);
        await _secure.delete(key: _kBearer);
      case AuthBearer(:final token):
        await _secure.write(key: _kBearer, value: token);
        await _secure.delete(key: _kBasicUser);
        await _secure.delete(key: _kBasicPass);
    }
  }

  @override
  Future<void> saveActiveSerial(String serial) async {
    final prefs = await _prefs();
    await prefs.setString(_kActiveSerial, serial);
  }

  @override
  Future<void> markComplete() async {
    final prefs = await _prefs();
    await prefs.setBool(_kComplete, true);
  }
}
