import 'dart:async';

import '../services/app_logger.dart';
import 'device_state_source.dart';
import 'devices_snapshot.dart';
import 'state_cache.dart';

typedef FetchDevicesJson = Future<Map<String, dynamic>> Function();

/// HTTP-polling implementation of [DeviceStateSource] per DESIGN §3.3.
///
/// Cadence:
/// - Foreground idle: `/api/devices` every 20s.
/// - [refresh] fires immediately, resets the 20s clock, and schedules
///   reconciliation polls at +1s, +3s, +7s for post-command catch-up.
/// - [pause] cancels everything; [resume] kicks an immediate poll and
///   restarts the 20s cadence.
///
/// On [start], the cache is read first so the UI has something to render
/// while the first live poll is in flight.
class PollingDeviceStateSource implements DeviceStateSource {
  final FetchDevicesJson fetchJson;
  final StateCache cache;
  final Duration interval;
  final Duration freshness;
  final DateTime Function() clock;
  final AppLogger? logger;

  final _controller = StreamController<DevicesSnapshot>.broadcast();
  DevicesSnapshot? _latest;
  DateTime? _lastSuccessAt;
  bool _lastAttemptFailed = false;
  Timer? _periodic;
  final List<Timer> _reconciliations = [];
  bool _started = false;
  bool _disposed = false;

  PollingDeviceStateSource({
    required this.fetchJson,
    required this.cache,
    this.interval = const Duration(seconds: 20),
    this.freshness = const Duration(seconds: 60),
    DateTime Function()? clock,
    this.logger,
  }) : clock = clock ?? DateTime.now;

  /// Reads cache (emits it if present), then begins the live polling loop.
  /// Safe to call once; subsequent calls are a no-op.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    final cached = await cache.read();
    if (_disposed) return;
    if (cached != null) {
      _emit(
        DevicesSnapshot.fromResponseJson(
          json: cached.response,
          fetchedAt: cached.fetchedAt,
          fromCache: true,
        ),
      );
    }

    _scheduleCadence();
    unawaited(_poll());
  }

  @override
  Stream<DevicesSnapshot> watch() {
    // Replays the latest snapshot to new subscribers, then forwards every
    // future emission. The explicit controller (vs. `async* { yield _latest;
    // yield* _controller.stream; }`) avoids a race where the broadcast
    // controller emits before the generator reaches `yield*`, dropping the
    // event for that subscriber.
    late StreamController<DevicesSnapshot> out;
    StreamSubscription<DevicesSnapshot>? sub;
    out = StreamController<DevicesSnapshot>(
      onListen: () {
        sub = _controller.stream.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
        if (_latest != null) out.add(_latest!);
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  void refresh() {
    if (_disposed) return;
    _cancelReconciliations();
    _scheduleCadence();
    unawaited(_poll());
    _reconciliations.addAll([
      Timer(const Duration(seconds: 1), () => unawaited(_poll())),
      Timer(const Duration(seconds: 3), () => unawaited(_poll())),
      Timer(const Duration(seconds: 7), () => unawaited(_poll())),
    ]);
  }

  void pause() {
    final wasActive = _periodic != null;
    _periodic?.cancel();
    _periodic = null;
    _cancelReconciliations();
    if (wasActive) logger?.info('polling paused');
  }

  void resume() {
    if (_disposed) return;
    final wasIdle = _periodic == null;
    _scheduleCadence();
    unawaited(_poll());
    if (wasIdle) logger?.info('polling resumed');
  }

  @override
  bool get isStale {
    if (_lastAttemptFailed) return true;
    if (_lastSuccessAt != null) {
      return clock().difference(_lastSuccessAt!) > freshness;
    }
    if (_latest != null && _latest!.fromCache) {
      return clock().difference(_latest!.fetchedAt) > freshness;
    }
    return true;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    pause();
    await _controller.close();
  }

  void _scheduleCadence() {
    _periodic?.cancel();
    _periodic = Timer.periodic(interval, (_) => unawaited(_poll()));
  }

  void _cancelReconciliations() {
    for (final t in _reconciliations) {
      t.cancel();
    }
    _reconciliations.clear();
  }

  Future<void> _poll() async {
    if (_disposed) return;
    try {
      final raw = await fetchJson();
      if (_disposed) return;
      final now = clock();
      await cache.write(CachedDevicesResponse(fetchedAt: now, response: raw));
      _lastSuccessAt = now;
      _lastAttemptFailed = false;
      _emit(
        DevicesSnapshot.fromResponseJson(
          json: raw,
          fetchedAt: now,
          fromCache: false,
        ),
      );
    } catch (_) {
      _lastAttemptFailed = true;
    }
  }

  void _emit(DevicesSnapshot snapshot) {
    _latest = snapshot;
    if (!_controller.isClosed) {
      _controller.add(snapshot);
    }
  }
}
