import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/state/state_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns null when key is absent', () async {
    final cache = SharedPrefsStateCache();
    expect(await cache.read(), isNull);
  });

  test('roundtrip preserves fetchedAt and response payload', () async {
    final cache = SharedPrefsStateCache();
    final fetchedAt = DateTime.utc(2026, 5, 19, 1, 30);
    final payload = {
      'devices': [
        {'serial': 'X', 'mode': 'heat'},
      ],
      'total': 1,
    };

    await cache.write(
      CachedDevicesResponse(fetchedAt: fetchedAt, response: payload),
    );
    final got = await cache.read();

    expect(got, isNotNull);
    expect(got!.fetchedAt.toUtc(), fetchedAt);
    expect(got.response, payload);
  });

  test('clear removes the cached entry', () async {
    final cache = SharedPrefsStateCache();
    await cache.write(
      CachedDevicesResponse(
        fetchedAt: DateTime.utc(2026, 5, 19),
        response: const {'devices': [], 'total': 0},
      ),
    );
    await cache.clear();
    expect(await cache.read(), isNull);
  });

  test('returns null on corrupt JSON instead of throwing', () async {
    SharedPreferences.setMockInitialValues({'last_state_cache': 'not-json {'});
    final cache = SharedPrefsStateCache();
    expect(await cache.read(), isNull);
  });
}
