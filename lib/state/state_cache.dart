import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CachedDevicesResponse {
  final DateTime fetchedAt;
  final Map<String, dynamic> response;

  const CachedDevicesResponse({
    required this.fetchedAt,
    required this.response,
  });
}

/// Persistence boundary for the most recent successful `/api/devices`
/// payload. DESIGN §12.1 places this in `shared_preferences` as a
/// JSON-encoded string under the `last_state_cache` key.
abstract class StateCache {
  Future<CachedDevicesResponse?> read();
  Future<void> write(CachedDevicesResponse cached);
  Future<void> clear();
}

class SharedPrefsStateCache implements StateCache {
  static const _key = 'last_state_cache';
  final Future<SharedPreferences> Function() _prefs;

  SharedPrefsStateCache({Future<SharedPreferences> Function()? prefsLoader})
    : _prefs = prefsLoader ?? SharedPreferences.getInstance;

  @override
  Future<CachedDevicesResponse?> read() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final fetchedAt = DateTime.parse(decoded['fetched_at'] as String);
      final response = decoded['response'] as Map<String, dynamic>;
      return CachedDevicesResponse(fetchedAt: fetchedAt, response: response);
    } catch (_) {
      // Corrupt cache entry — drop it. Better to render skeleton than crash.
      return null;
    }
  }

  @override
  Future<void> write(CachedDevicesResponse cached) async {
    final prefs = await _prefs();
    final payload = {
      'fetched_at': cached.fetchedAt.toUtc().toIso8601String(),
      'response': cached.response,
    };
    await prefs.setString(_key, jsonEncode(payload));
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(_key);
  }
}
