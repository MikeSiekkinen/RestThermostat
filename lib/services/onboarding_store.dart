import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_config.dart';

class OnboardingConfig {
  final String? serverUrl;
  final AuthConfig auth;
  final String? activeSerial;
  final bool isComplete;
  final Map<String, String> deviceNameOverrides;

  const OnboardingConfig({
    required this.serverUrl,
    required this.auth,
    required this.activeSerial,
    required this.isComplete,
    this.deviceNameOverrides = const {},
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

  /// Persists [name] as the local display override for [serial]. A null or
  /// empty name removes the override (display falls back to NLE name or
  /// `Thermostat (XXXX)` per DESIGN §4.4).
  Future<void> setDeviceNameOverride(String serial, String? name);

  /// Wipes secure storage + prefs (DESIGN §12.7 Disconnect). Caller is
  /// responsible for clearing the state cache and the in-memory Riverpod
  /// providers separately — this method only handles the on-disk state owned
  /// by the store.
  Future<void> clear();
}

class FlutterOnboardingStore implements OnboardingStore {
  static const _kServerUrl = 'server_url';
  static const _kActiveSerial = 'active_device_serial';
  static const _kComplete = 'onboarding_complete';
  static const _kAuthType = 'auth_type';
  static const _kBasicUser = 'auth_basic_username';
  static const _kBasicPass = 'auth_basic_password';
  static const _kBearer = 'auth_bearer_token';
  static const _kDeviceNameOverrides = 'device_name_overrides';

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
      deviceNameOverrides: _readOverrides(prefs),
    );
  }

  Map<String, String> _readOverrides(SharedPreferences prefs) {
    final raw = prefs.getString(_kDeviceNameOverrides);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      // Corrupt entry — drop it silently. Treat as no overrides.
      return const {};
    }
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

  @override
  Future<void> setDeviceNameOverride(String serial, String? name) async {
    final prefs = await _prefs();
    final current = Map<String, String>.from(_readOverrides(prefs));
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      current.remove(serial);
    } else {
      current[serial] = trimmed;
    }
    if (current.isEmpty) {
      await prefs.remove(_kDeviceNameOverrides);
    } else {
      await prefs.setString(_kDeviceNameOverrides, jsonEncode(current));
    }
  }

  @override
  Future<void> clear() async {
    // Per DESIGN §12.7: wipe everything the store owns. Secure storage clears
    // every key under the app's Keychain/EncryptedSharedPreferences scope; we
    // then remove our prefs keys individually so we don't trample cache or
    // unrelated prefs that other features may store later.
    await _secure.deleteAll();
    final prefs = await _prefs();
    await prefs.remove(_kServerUrl);
    await prefs.remove(_kActiveSerial);
    await prefs.remove(_kComplete);
    await prefs.remove(_kDeviceNameOverrides);
  }
}
