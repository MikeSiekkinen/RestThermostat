import 'dart:async';

import '../services/app_logger.dart';
import '../services/nle_error.dart';
import 'connection_status.dart';
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
/// - [pauseFor] is the 429 path: stop polling for the indicated duration,
///   then auto-resume. Used by the rate-limit handler in [_poll].
///
/// On [start], the cache is read first so the UI has something to render
/// while the first live poll is in flight.
///
/// [ConnectionStatus] is broadcast via [watchStatus] whenever the source
/// transitions between fresh / reconnecting / rate-limited / stale. The
/// home-screen stale-state pill consumes that stream.
class PollingDeviceStateSource implements DeviceStateSource {
  final FetchDevicesJson fetchJson;
  final StateCache cache;
  final Duration interval;
  final Duration freshness;
  final Duration rateLimitFallback;
  final DateTime Function() clock;
  final AppLogger? logger;

  final _controller = StreamController<DevicesSnapshot>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  DevicesSnapshot? _latest;
  DateTime? _lastSuccessAt;
  bool _lastAttemptFailed = false;
  bool _pollInFlight = false;
  DateTime? _rateLimitedUntil;
  Timer? _periodic;
  Timer? _rateLimitTimer;
  final List<Timer> _reconciliations = [];
  bool _started = false;
  bool _disposed = false;
  ConnectionStatus _currentStatus = ConnectionStatus.initial;

  /// Optional callback invoked when a poll fails with an [NleAuthError].
  /// The host wires this to [AuthFailureCoordinator.fire] so the home shell
  /// can surface the deep-link snackbar.
  final void Function()? _onAuthFailure;

  // The `:` form keeps the named arg `onAuthFailure` (an initializing formal
  // would force renaming it to `_onAuthFailure` and exposing the private
  // name in the public constructor).
  PollingDeviceStateSource({
    required this.fetchJson,
    required this.cache,
    this.interval = const Duration(seconds: 20),
    this.freshness = const Duration(seconds: 60),
    this.rateLimitFallback = const Duration(seconds: 30),
    DateTime Function()? clock,
    this.logger,
    void Function()? onAuthFailure,
  }) : clock = clock ?? DateTime.now,
       // ignore: prefer_initializing_formals
       _onAuthFailure = onAuthFailure;

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
  Stream<ConnectionStatus> watchStatus() {
    late StreamController<ConnectionStatus> out;
    StreamSubscription<ConnectionStatus>? sub;
    out = StreamController<ConnectionStatus>(
      onListen: () {
        sub = _statusController.stream.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
        out.add(_currentStatus);
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

  /// Stop polling for [duration], then auto-resume. Used by the 429 path —
  /// `Retry-After` from the server flows through here (falls back to
  /// [rateLimitFallback] when the header is missing). Multiple calls extend
  /// the backoff window only if the new deadline is later than the existing
  /// one; shorter overlapping calls are ignored.
  void pauseFor(Duration duration) {
    if (_disposed) return;
    if (duration <= Duration.zero) {
      // Treat zero-or-negative as "resume now".
      resume();
      return;
    }
    final deadline = clock().add(duration);
    final existing = _rateLimitedUntil;
    if (existing != null && existing.isAfter(deadline)) {
      // A longer backoff is already in effect; keep it.
      return;
    }
    _rateLimitedUntil = deadline;
    pause();
    _rateLimitTimer?.cancel();
    _rateLimitTimer = Timer(duration, () {
      _rateLimitTimer = null;
      _rateLimitedUntil = null;
      _refreshStatus();
      resume();
    });
    logger?.warn('polling rate-limited for ${duration.inSeconds}s');
    _refreshStatus();
  }

  @override
  bool get isStale {
    if (_lastAttemptFailed) return true;
    if (_rateLimitedUntil != null) return true;
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
    _rateLimitTimer?.cancel();
    _rateLimitTimer = null;
    await _controller.close();
    await _statusController.close();
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
    if (_rateLimitedUntil != null && clock().isBefore(_rateLimitedUntil!)) {
      // Still in backoff; skip this poll attempt.
      return;
    }
    _pollInFlight = true;
    _refreshStatus();
    try {
      final raw = await fetchJson();
      if (_disposed) return;
      final now = clock();
      await cache.write(CachedDevicesResponse(fetchedAt: now, response: raw));
      _lastSuccessAt = now;
      _lastAttemptFailed = false;
      _rateLimitedUntil = null;
      _rateLimitTimer?.cancel();
      _rateLimitTimer = null;
      _emit(
        DevicesSnapshot.fromResponseJson(
          json: raw,
          fetchedAt: now,
          fromCache: false,
        ),
      );
    } on NleRateLimitError catch (e) {
      _lastAttemptFailed = true;
      final wait = e.retryAfter ?? rateLimitFallback;
      pauseFor(wait);
    } on NleAuthError catch (_) {
      _lastAttemptFailed = true;
      _onAuthFailure?.call();
    } catch (_) {
      _lastAttemptFailed = true;
    } finally {
      _pollInFlight = false;
      _refreshStatus();
    }
  }

  void _emit(DevicesSnapshot snapshot) {
    _latest = snapshot;
    if (!_controller.isClosed) {
      _controller.add(snapshot);
    }
    _refreshStatus();
  }

  /// Recompute [_currentStatus] from the underlying signals and emit if it
  /// changed. Called from every site that mutates one of those signals.
  void _refreshStatus() {
    final now = clock();
    final stale =
        _lastAttemptFailed ||
        _rateLimitedUntil != null ||
        _lastSuccessAt == null ||
        now.difference(_lastSuccessAt!) > freshness;
    final next = ConnectionStatus(
      isFresh: !stale,
      // Reconnecting = a poll is in flight after a previous failure (or with
      // no successful poll yet on cold-start). When the very first poll is
      // in flight before any success/failure we don't count as "reconnecting"
      // since the pill copy ("Reconnecting…") implies recovery from a drop.
      isReconnecting: _pollInFlight && _lastAttemptFailed,
      isRateLimited: _rateLimitedUntil != null,
      rateLimitedUntil: _rateLimitedUntil,
      lastSuccessAt: _lastSuccessAt,
    );
    if (next == _currentStatus) return;
    _currentStatus = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }
}
