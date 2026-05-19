import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../services/nle_error.dart';
import '../state/auth_failure_coordinator.dart';
import '../state/devices_snapshot.dart';
import '../state/providers.dart';
import 'temperature_dial.dart';

/// Stateful wrapper that adds the interactive write-path around
/// [TemperatureDial] per `docs/DESIGN.md` §3.4 + §11.3.
///
/// Responsibilities the inner [TemperatureDial] does **not** own:
/// 1. **Optimistic state.** While the user is dragging, the dial reflects the
///    finger position immediately. We keep an `_optimisticC` that overrides
///    the server-reported target until reconciliation matches it (or fails).
/// 2. **Pan-end debounce.** A 250ms timer after `onPanEnd` ensures the user
///    has truly stopped before we POST. Restarted on each new pan/tap.
/// 3. **POST `set_temperature` + reconciliation.** On commit we send the new
///    Celsius target, then kick [DeviceStateSource.refresh] (per ticket #5
///    that schedules +1/+3/+7s reconciliation polls). We listen to the
///    devices stream until either: (a) the next snapshot's target matches
///    the optimistic value → clear local override, or (b) 7s pass with no
///    match → show a "Couldn't confirm" snackbar with a retry action.
/// 4. **Failure path.** A `DioException` after the 1 internal retry surfaces
///    a "Couldn't update temperature" snackbar and reverts the optimistic UI.
///
/// Mode handling:
/// - `heat`, `cool`, `off`, `emergency`: writes `set_temperature` with a
///   single number (Celsius).
/// - `heat-cool`: v1 scope per the ticket — picks whichever bound (low/high)
///   is closer to the new target and POSTs `{"high": h, "low": l}` with that
///   bound replaced. Proper dual-marker UI is a follow-up ticket.
class InteractiveTemperatureDial extends ConsumerStatefulWidget {
  final Device device;

  /// The unit drive: 'C' or 'F'. Just forwarded to the inner dial.
  final String displayUnit;

  /// Optional override for the inner dial's diameter constraint. The caller
  /// is expected to wrap us in a sized box, same as the original dial.
  const InteractiveTemperatureDial({
    super.key,
    required this.device,
    required this.displayUnit,
  });

  @override
  ConsumerState<InteractiveTemperatureDial> createState() =>
      _InteractiveTemperatureDialState();
}

class _InteractiveTemperatureDialState
    extends ConsumerState<InteractiveTemperatureDial> {
  /// Local override of the target temperature while the user interacts and
  /// while we wait for the server to reconcile. `null` means "trust the
  /// device snapshot".
  double? _optimisticC;

  /// Pending pan-end commit. Cancelled and restarted by every new pan/tap.
  Timer? _commitTimer;

  /// 7-second timeout after a successful POST. Fires if we never see a
  /// matching snapshot target.
  Timer? _confirmTimer;

  /// Subscription to the devices stream used to watch for reconciliation
  /// during the pending-confirm window.
  ProviderSubscription<AsyncValue<DevicesSnapshot>>? _confirmSub;

  /// The value we're currently waiting to reconcile against, if any.
  double? _pendingConfirmC;

  /// Per-tick gap used by the [TemperatureDial.tickIndexForCelsius] mapping —
  /// reconciliation tolerates a difference of <= half-a-tick so server-side
  /// rounding doesn't false-trigger a mismatch tween.
  static double get _confirmEpsilonC =>
      (TemperatureDial.maxCelsius - TemperatureDial.minCelsius) /
      (TemperatureDial.tickCount - 1) /
      2;

  @override
  void dispose() {
    _commitTimer?.cancel();
    _confirmTimer?.cancel();
    _confirmSub?.close();
    super.dispose();
  }

  void _onDragUpdate(double celsius) {
    setState(() => _optimisticC = celsius);
    // A new drag invalidates any pending pan-end commit — we'll restart the
    // debounce on the next onPanEnd / onTapUp.
    _commitTimer?.cancel();
    _commitTimer = null;
  }

  void _onDragEnd(double celsius) {
    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 250), () {
      _commit(celsius);
    });
  }

  void _onTap(double celsius) {
    // Tap means commit-now: same 250ms debounce so an immediate follow-up
    // pan can cancel it.
    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 250), () {
      _commit(celsius);
    });
  }

  Future<void> _commit(double celsius) async {
    final clamped = celsius.clamp(
      TemperatureDial.minCelsius,
      TemperatureDial.maxCelsius,
    );
    setState(() {
      _optimisticC = clamped;
      _pendingConfirmC = clamped;
    });

    final client = ref.read(nleApiClientProvider);
    try {
      await client.sendCommand(
        serial: widget.device.serial,
        command: 'set_temperature',
        value: _buildValue(clamped),
      );
    } on NleAuthError catch (_) {
      if (!mounted) return;
      ref.read(authFailureCoordinatorProvider).fire();
      setState(() {
        _optimisticC = null;
        _pendingConfirmC = null;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      _showSnack('Couldn\'t update temperature', retryC: clamped);
      setState(() {
        _optimisticC = null;
        _pendingConfirmC = null;
      });
      return;
    }

    if (!mounted) return;
    // Kick the post-command reconciliation cadence (+1/+3/+7s) per §3.3.
    ref.read(deviceStateSourceProvider).refresh();
    _startConfirmWatch(clamped);
  }

  /// Build the `value` payload for `set_temperature`. Heat-cool replaces one
  /// bound; everything else sends a single number.
  Object _buildValue(double clamped) {
    if (widget.device.mode != DeviceMode.heatCool) return clamped;
    final low = widget.device.targetTemperatureLow ?? clamped;
    final high = widget.device.targetTemperatureHigh ?? clamped;
    final distLow = (clamped - low).abs();
    final distHigh = (clamped - high).abs();
    if (distLow <= distHigh) {
      return {'low': clamped, 'high': high};
    }
    return {'low': low, 'high': clamped};
  }

  void _startConfirmWatch(double expectedC) {
    _confirmTimer?.cancel();
    _confirmSub?.close();
    _confirmSub = ref.listenManual<AsyncValue<DevicesSnapshot>>(
      devicesSnapshotProvider,
      (_, next) {
        final pending = _pendingConfirmC;
        if (pending == null) return;
        next.whenData((snapshot) {
          final match = snapshot.devices.firstWhere(
            (d) => d.serial == widget.device.serial,
            orElse: () => widget.device,
          );
          if ((match.targetTemperature - pending).abs() <= _confirmEpsilonC) {
            // Reconciled — clear optimistic override and let the snapshot
            // drive the displayed value (the dial's TweenAnimationBuilder
            // already handles the tween to the new value).
            if (!mounted) return;
            setState(() {
              _optimisticC = null;
              _pendingConfirmC = null;
            });
            _confirmTimer?.cancel();
            _confirmSub?.close();
            _confirmSub = null;
          }
        });
      },
    );
    _confirmTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      _showSnack('Couldn\'t confirm new temperature', retryC: expectedC);
      _confirmSub?.close();
      _confirmSub = null;
      _pendingConfirmC = null;
      // Keep optimistic value visible per §3.4 — don't auto-revert.
    });
  }

  void _showSnack(String message, {required double retryC}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => _commit(retryC),
        ),
      ),
    );
  }

  /// Bump the target by one tick in the requested direction and commit it.
  /// Used by the `Semantics(onIncrease/onDecrease, ...)` actions in the
  /// inner dial — TalkBack swipe-up / VoiceOver flick reads land here so
  /// the user can adjust the setpoint without touching the visual ring.
  void _bump(int direction) {
    final current = _optimisticC ?? widget.device.targetTemperature;
    final currentIndex = TemperatureDial.tickIndexForCelsius(current);
    final nextIndex = (currentIndex + direction).clamp(
      0,
      TemperatureDial.tickCount - 1,
    );
    final nextCelsius = TemperatureDial.celsiusForTickIndex(nextIndex);
    if ((nextCelsius - current).abs() < 1e-9) return;
    setState(() => _optimisticC = nextCelsius);
    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 250), () {
      _commit(nextCelsius);
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayedC = _optimisticC ?? widget.device.targetTemperature;
    return TemperatureDial(
      currentTemperatureCelsius: widget.device.currentTemperature,
      targetTemperatureCelsius: displayedC,
      mode: widget.device.mode,
      displayUnit: widget.displayUnit,
      capabilities: widget.device.capabilities,
      onTargetDragUpdate: _onDragUpdate,
      onTargetDragEnd: _onDragEnd,
      onTargetTap: _onTap,
      onIncrease: () => _bump(1),
      onDecrease: () => _bump(-1),
    );
  }
}
