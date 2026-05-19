import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dio/dio.dart';
import 'package:rest_thermostat/services/nle_error.dart';
import 'package:rest_thermostat/state/connection_status.dart';
import 'package:rest_thermostat/state/devices_snapshot.dart';
import 'package:rest_thermostat/state/polling_device_state_source.dart';
import 'package:rest_thermostat/state/state_cache.dart';

import 'fake_state_cache.dart';

class _FakeFetch {
  int callCount = 0;
  bool failNext = false;
  Object? throwOnNext;
  Map<String, dynamic> response;

  _FakeFetch({required this.response});

  Future<Map<String, dynamic>> call() async {
    callCount++;
    if (throwOnNext != null) {
      final e = throwOnNext;
      throwOnNext = null;
      throw e!;
    }
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

  NleRateLimitError rateLimit(Duration? retryAfter) {
    return NleRateLimitError(retryAfter: retryAfter);
  }

  group('rate limit (429)', () {
    test('pauseFor(Retry-After) stops polling and auto-resumes', () {
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

        source.pauseFor(const Duration(seconds: 45));
        async.elapse(const Duration(seconds: 20));
        expect(fetch.callCount, 1, reason: 'no polls during rate-limit window');
        async.elapse(const Duration(seconds: 20));
        expect(fetch.callCount, 1, reason: 'still inside the window');

        // Past 45s the source should auto-resume and fire an immediate poll.
        async.elapse(const Duration(seconds: 10));
        expect(fetch.callCount, 2, reason: 'auto-resume kicks immediate poll');

        source.dispose();
        async.flushMicrotasks();
      });
    });

    test('NleRateLimitError from a poll triggers pauseFor', () {
      fakeAsync((async) {
        final fetch = _FakeFetch(response: _fixture());
        final source = _source(
          fetch: fetch,
          cache: FakeStateCache(),
          async: async,
        );
        source.watch().listen((_) {});

        // First poll succeeds.
        source.start();
        async.flushMicrotasks();
        expect(fetch.callCount, 1);

        // Next poll gets a 429 with Retry-After: 60.
        fetch.throwOnNext = rateLimit(const Duration(seconds: 60));
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        expect(fetch.callCount, 2);
        expect(source.isStale, isTrue);

        // 50s in, still no poll (we're in the 60s backoff window from t=20s).
        async.elapse(const Duration(seconds: 50));
        expect(fetch.callCount, 2);

        // After the 60s window elapses, auto-resume fires a poll.
        async.elapse(const Duration(seconds: 15));
        expect(
          fetch.callCount,
          greaterThanOrEqualTo(3),
          reason: 'resumed after rate-limit window',
        );

        source.dispose();
        async.flushMicrotasks();
      });
    });

    test('NleRateLimitError with no Retry-After falls back to 30s', () {
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
        fetch.throwOnNext = rateLimit(null);
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        expect(fetch.callCount, 2);

        async.elapse(const Duration(seconds: 25));
        expect(fetch.callCount, 2, reason: 'still inside 30s fallback');
        async.elapse(const Duration(seconds: 10));
        expect(fetch.callCount, greaterThanOrEqualTo(3));

        source.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('watchStatus()', () {
    test('emits fresh after a successful poll', () {
      fakeAsync((async) {
        final fetch = _FakeFetch(response: _fixture());
        final source = _source(
          fetch: fetch,
          cache: FakeStateCache(),
          async: async,
        );
        source.watch().listen((_) {});
        final statuses = <ConnectionStatus>[];
        source.watchStatus().listen(statuses.add);

        source.start();
        async.flushMicrotasks();

        // Final emission should be fresh.
        expect(statuses.last.isFresh, isTrue);
        expect(statuses.last.isReconnecting, isFalse);
        expect(statuses.last.isRateLimited, isFalse);

        source.dispose();
        async.flushMicrotasks();
      });
    });

    test('emits reconnecting=true during retry after a prior failure', () {
      fakeAsync((async) {
        final fetch = _FakeFetch(response: _fixture());
        final source = _source(
          fetch: fetch,
          cache: FakeStateCache(),
          async: async,
        );
        source.watch().listen((_) {});

        // Fail the FIRST poll synchronously by throwing a non-Nle exception.
        // The fetch helper accepts a typed throw via [throwOnNext].
        final ioError = DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        );
        fetch.throwOnNext = NleError.fromDio(ioError);

        final statuses = <ConnectionStatus>[];
        source.watchStatus().listen(statuses.add);
        source.start();
        async.flushMicrotasks();

        // After the failed first poll, status should be non-fresh.
        expect(statuses.last.isFresh, isFalse);
        expect(statuses.last.lastSuccessAt, isNull);

        // The next cadence tick: we observe at least one "reconnecting=true"
        // status. Track the maximum reconnecting value across the cycle —
        // the in-flight transition can be very fast, so we just assert the
        // status went through the reconnecting state at least once.
        var sawReconnecting = false;
        late StreamSubscription<ConnectionStatus> probe;
        probe = source.watchStatus().listen((s) {
          if (s.isReconnecting) sawReconnecting = true;
        });
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        probe.cancel();

        expect(sawReconnecting, isTrue);

        source.dispose();
        async.flushMicrotasks();
      });
    });

    test('emits rateLimited=true while paused, fresh after recovery', () {
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

        final statuses = <ConnectionStatus>[];
        source.watchStatus().listen(statuses.add);

        fetch.throwOnNext = rateLimit(const Duration(seconds: 30));
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        expect(statuses.any((s) => s.isRateLimited), isTrue);

        // After backoff + a successful poll, status returns to fresh.
        async.elapse(const Duration(seconds: 35));
        async.flushMicrotasks();
        expect(statuses.last.isRateLimited, isFalse);
        expect(statuses.last.isFresh, isTrue);

        source.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
