import 'package:rest_thermostat/state/state_cache.dart';

class FakeStateCache implements StateCache {
  CachedDevicesResponse? entry;

  @override
  Future<CachedDevicesResponse?> read() async => entry;

  @override
  Future<void> write(CachedDevicesResponse cached) async => entry = cached;

  @override
  Future<void> clear() async => entry = null;
}
