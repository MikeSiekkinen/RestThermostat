import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rest_thermostat/state/devices_snapshot.dart';
import 'package:rest_thermostat/state/polling_device_state_source.dart';
import 'package:rest_thermostat/state/state_cache.dart';

import 'fake_state_cache.dart';

class _FakeFetch {
  int callCount = 0;
  bool failNext = false;
  Map<String, dynamic> response;

  _FakeFetch({required this.response});

  Future<Map<String, dynamic>> call() async {
    callCount++;
    if (failNext) {
      throw Exception('boom');
    }
    return response;
  }
}

Map<String, dynamic> _fixture() {
  return jsonDecode(File('test/fixtures/devices_one.json').readAsStringSync())
      as Map<String, dynamic>;
}

PollingDeviceStateSource _source({
  required _FakeFetch fetch,
  required StateCache cache,
  required FakeAsync async,
  Duration interval = const Duration(seconds: 20),
}) {
  return PollingDeviceStateSource(
    fetchJson: fetch.call,
    cache: cache,
    interval: interval,
    clock: () => DateTime.utc(2026, 1, 1).add(async.elapsed),
  );
}

void main() {
  test('initial poll fires once on start and writes cache', () {
    fakeAsync((async) {
      final fetch = _FakeFetch(response: _fixture());
      final cache = FakeStateCache();
      final source = _source(fetch: fetch, cache: cache, async: async);
      final emissions = <DevicesSnapshot>[];
      source.watch().listen(emissions.add);

      source.start();
      async.flushMicrotasks();

      expect(fetch.callCount, 1);
      expect(emissions, hasLength(1));
      expect(emissions.first.fromCache, isFalse);
      expect(cache.entry, isNotNull);
      expect(cache.entry!.response, _fixture());

      source.dispose();
      async.flushMicrotasks();
    });
  });

  test('cached snapshot is emitted before the first live poll', () {
    fakeAsync((async) {
      final fetch = _FakeFetch(response: _fixture());
      final cache = FakeStateCache()
        ..entry = CachedDevicesResponse(
          fetchedAt: DateTime.utc(2026, 1, 1),
          response: _fixture(),
        );
      final source = _source(fetch: fetch, cache: cache, async: async);
      final emissions = <DevicesSnapshot>[];
      source.watch().listen(emissions.add);

      source.start();
      async.flushMicrotasks();

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions[0].fromCache, isTrue);
      expect(emissions[1].fromCache, isFalse);

      source.dispose();
      async.flushMicrotasks();
    });
  });

  test('20s cadence triggers subsequent polls', () {
    fakeAsync((async) {
      final fetch = _FakeFetch(response: _fixture());
      final source = _source(
        fetch: fetch,
        cache: FakeStateCache(),
        async: async,
      );
      source.watch().listen((_) {});

      source.start();
      async.flushMicrotasks();
      expect(fetch.callCount, 1);

      async.elapse(const Duration(seconds: 20));
      expect(fetch.callCount, 2);

      async.elapse(const Duration(seconds: 20));
      expect(fetch.callCount, 3);

      source.dispose();
      async.flushMicrotasks();
    });
  });

  test('refresh fires immediately and schedules +1s, +3s, +7s polls', () {
    fakeAsync((async) {
      final fetch = _FakeFetch(response: _fixture());
      final source = _source(
        fetch: fetch,
        cache: FakeStateCache(),
        async: async,
      );
      source.watch().listen((_) {});

      source.start();
      async.flushMicrotasks();
      expect(fetch.callCount, 1);

      source.refresh();
      async.flushMicrotasks();
      expect(fetch.callCount, 2, reason: 'immediate refresh poll');

      async.elapse(const Duration(seconds: 1));
      expect(fetch.callCount, 3, reason: '+1s reconciliation');

      async.elapse(const Duration(seconds: 2));
      expect(fetch.callCount, 4, reason: '+3s reconciliation');

      async.elapse(const Duration(seconds: 4));
      expect(fetch.callCount, 5, reason: '+7s reconciliation');

      source.dispose();
      async.flushMicrotasks();
    });
  });

  test('refresh resets the 20s cadence (next regular tick is 20s later)', () {
    fakeAsync((async) {
      final fetch = _FakeFetch(response: _fixture());
      final source = _source(
        fetch: fetch,
        cache: FakeStateCache(),
        async: async,
      );
      source.watch().listen((_) {});

      source.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      expect(fetch.callCount, 1);

      source.refresh();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 7));
      expect(fetch.callCount, 5, reason: 'refresh + +1 + +3 + +7');

      // From refresh (t=10) the next regular cadence tick is at t=30,
      // i.e. 13s after the +7 reconciliation completes.
      async.elapse(const Duration(seconds: 12));
      expect(fetch.callCount, 5, reason: 'no cadence tick yet');
      async.elapse(const Duration(seconds: 1));
      expect(fetch.callCount, 6, reason: 'cadence tick at refresh+20s');

      source.dispose();
      async.flushMicrotasks();
    });
  });

  test('pause cancels cadence; resume kicks immediate poll', () {
    fakeAsync((async) {
      final fetch = _FakeFetch(response: _fixture());
      final source = _source(
        fetch: fetch,
        cache: FakeStateCache(),
        async: async,
      );
      source.watch().listen((_) {});

      source.start();
      async.flushMicrotasks();
      expect(fetch.callCount, 1);

      source.pause();
      async.elapse(const Duration(seconds: 60));
      expect(fetch.callCount, 1, reason: 'no polls while paused');

      source.resume();
      async.flushMicrotasks();
      expect(fetch.callCount, 2, reason: 'immediate poll on resume');

      async.elapse(const Duration(seconds: 20));
      expect(fetch.callCount, 3, reason: 'cadence resumed');

      source.dispose();
      async.flushMicrotasks();
    });
  });

  test('isStale tracks 60s freshness window after a successful poll', () {
    fakeAsync((async) {
      final fetch = _FakeFetch(response: _fixture());
      final source = _source(
        fetch: fetch,
        cache: FakeStateCache(),
        async: async,
      );
      source.watch().listen((_) {});

      source.start();
      async.flushMicrotasks();
      expect(source.isStale, isFalse);

      source.pause();
      async.elapse(const Duration(seconds: 59));
      expect(source.isStale, isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(source.isStale, isTrue);

      source.dispose();
      async.flushMicrotasks();
    });
  });

  test('isStale becomes true when a poll fails', () {
    fakeAsync((async) {
      final fetch = _FakeFetch(response: _fixture())..failNext = true;
      final cache = FakeStateCache();
      final source = _source(fetch: fetch, cache: cache, async: async);
      source.watch().listen((_) {});

      source.start();
      async.flushMicrotasks();
      expect(source.isStale, isTrue);
      expect(cache.entry, isNull);

      source.dispose();
      async.flushMicrotasks();
    });
  });
}
