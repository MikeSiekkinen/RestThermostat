import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/device.dart';
import '../services/nle_error.dart';
import '../settings/numeral_font.dart';
import '../state/auth_failure_coordinator.dart';
import '../state/devices_snapshot.dart';
import '../state/providers.dart';
import '../theme/colors.dart';
import 'range_entry_dialog.dart';
import 'temp_entry_dialog.dart';
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
///   single number (Celsius); single optimistic scalar + confirm-watch.
/// - `heat-cool` with both bounds present (Issue #116): a true dual band — a
///   paired optimistic `(low, high)` state, POSTs the explicit
///   `{"low": l, "high": h}` the user set (no nearest-bound inference), and a
///   dual confirm-watch that reconciles both bounds. A heat-cool device that
///   reports a null bound falls back to the single-scalar path above.
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

  /// Paired optimistic overrides for the heat-cool dual band (Issue #116).
  /// Both are set/cleared together; `null` means "trust the snapshot bounds".
  double? _optimisticLowC;
  double? _optimisticHighC;

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

  /// The dual-band pair we're waiting to reconcile against (Issue #116).
  double? _pendingConfirmLowC;
  double? _pendingConfirmHighC;

  /// Whether the device should render/write the heat-cool dual band: heat-cool
  /// with both bounds reported. A null bound falls back to the single path.
  bool get _isDual =>
      widget.device.mode == DeviceMode.heatCool &&
      widget.device.targetTemperatureLow != null &&
      widget.device.targetTemperatureHigh != null;

  bool get _isF => widget.displayUnit.toUpperCase() != 'C';

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
      _showSnack(
        AppLocalizations.of(context).dialTemperatureFailed,
        onRetry: () => _commit(clamped),
      );
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
      _showSnack(
        AppLocalizations.of(context).dialTemperatureNotConfirmed,
        onRetry: () => _commit(expectedC),
      );
      _confirmSub?.close();
      _confirmSub = null;
      _pendingConfirmC = null;
      // Keep optimistic value visible per §3.4 — don't auto-revert.
    });
  }

  // ---- Heat-cool dual band (Issue #116) -----------------------------------

  void _onRangeDragUpdate(double low, double high) {
    setState(() {
      _optimisticLowC = low;
      _optimisticHighC = high;
    });
    _commitTimer?.cancel();
    _commitTimer = null;
  }

  void _onRangeDragEnd(double low, double high) {
    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 250), () {
      _commitRange(low, high);
    });
  }

  void _onRangeTap(double low, double high) {
    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 250), () {
      _commitRange(low, high);
    });
  }

  /// POST the explicit `{low, high}` the user set (no nearest-bound inference),
  /// then reconcile both bounds. Mirrors [_commit]'s optimistic + failure
  /// handling, but for the paired state.
  Future<void> _commitRange(double low, double high) async {
    final clampedLow = low.clamp(
      TemperatureDial.minCelsius,
      TemperatureDial.maxCelsius,
    );
    final clampedHigh = high.clamp(
      TemperatureDial.minCelsius,
      TemperatureDial.maxCelsius,
    );
    setState(() {
      _optimisticLowC = clampedLow;
      _optimisticHighC = clampedHigh;
      _pendingConfirmLowC = clampedLow;
      _pendingConfirmHighC = clampedHigh;
    });

    final client = ref.read(nleApiClientProvider);
    try {
      await client.sendCommand(
        serial: widget.device.serial,
        command: 'set_temperature',
        value: {'low': clampedLow, 'high': clampedHigh},
      );
    } on NleAuthError catch (_) {
      if (!mounted) return;
      ref.read(authFailureCoordinatorProvider).fire();
      _revertRange();
      return;
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        AppLocalizations.of(context).dialTemperatureFailed,
        onRetry: () => _commitRange(clampedLow, clampedHigh),
      );
      _revertRange();
      return;
    }

    if (!mounted) return;
    ref.read(deviceStateSourceProvider).refresh();
    _startRangeConfirmWatch(clampedLow, clampedHigh);
  }

  void _revertRange() {
    setState(() {
      _optimisticLowC = null;
      _optimisticHighC = null;
      _pendingConfirmLowC = null;
      _pendingConfirmHighC = null;
    });
  }

  void _startRangeConfirmWatch(double expectedLow, double expectedHigh) {
    _confirmTimer?.cancel();
    _confirmSub?.close();
    _confirmSub = ref.listenManual<AsyncValue<DevicesSnapshot>>(
      devicesSnapshotProvider,
      (_, next) {
        final pLow = _pendingConfirmLowC;
        final pHigh = _pendingConfirmHighC;
        if (pLow == null || pHigh == null) return;
        next.whenData((snapshot) {
          final match = snapshot.devices.firstWhere(
            (d) => d.serial == widget.device.serial,
            orElse: () => widget.device,
          );
          final mLow = match.targetTemperatureLow;
          final mHigh = match.targetTemperatureHigh;
          // Both bounds must land within half-a-tick of what we wrote.
          if (mLow != null &&
              mHigh != null &&
              (mLow - pLow).abs() <= _confirmEpsilonC &&
              (mHigh - pHigh).abs() <= _confirmEpsilonC) {
            if (!mounted) return;
            setState(() {
              _optimisticLowC = null;
              _optimisticHighC = null;
              _pendingConfirmLowC = null;
              _pendingConfirmHighC = null;
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
      _showSnack(
        AppLocalizations.of(context).dialTemperatureNotConfirmed,
        onRetry: () => _commitRange(expectedLow, expectedHigh),
      );
      _confirmSub?.close();
      _confirmSub = null;
      _pendingConfirmLowC = null;
      _pendingConfirmHighC = null;
      // Keep the optimistic band visible per §3.4 — don't auto-revert.
    });
  }

  /// Open the dual-field range dialog as an alternative to the ring. Prefills
  /// the currently displayed band, and on confirm commits both bounds via
  /// [_commitRange]. The deadband is enforced inside the dialog.
  Future<void> _openRangeKeyboard() async {
    final l = AppLocalizations.of(context);
    _commitTimer?.cancel();
    final low = _optimisticLowC ?? widget.device.targetTemperatureLow!;
    final high = _optimisticHighC ?? widget.device.targetTemperatureHigh!;
    // Unit-aware display of the enforced gap for the inline error copy.
    final gapDisplay = _isF
        ? '${(TemperatureDial.deadbandCelsius * 9 / 5).round()}°F'
        : '${TemperatureDial.deadbandCelsius}°C';
    final result = await showDialog<RangeEntryResult>(
      context: context,
      builder: (_) => RangeEntryDialog(
        lowC: low,
        highC: high,
        scale: widget.displayUnit,
        heatAccent: EmberColors.heatGlow,
        coolAccent: EmberColors.coolGlow,
        numeralStyle: ref.read(numeralFontProvider).style,
        minCelsius: TemperatureDial.minCelsius,
        maxCelsius: TemperatureDial.maxCelsius,
        deadbandCelsius: TemperatureDial.deadbandCelsius,
        title: l.homeRangeEntryTitle,
        heatLabel: l.homeRangeEntryHeatField,
        coolLabel: l.homeRangeEntryCoolField,
        confirmLabel: l.homeTempEntryConfirm,
        cancelLabel: l.homeTempEntryCancel,
        deadbandError: l.homeRangeEntryDeadbandError(gapDisplay),
      ),
    );
    if (!mounted || result == null) return;
    _commitRange(result.lowC, result.highC);
  }

  void _showSnack(String message, {required VoidCallback onRetry}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: AppLocalizations.of(context).dialRetry,
          onPressed: onRetry,
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

  /// Open the keyboard-entry dialog as an alternative to the ring. Prefills the
  /// currently displayed setpoint, and on confirm commits the typed value
  /// straight through [_commit] — no debounce, since a modal dismissal has no
  /// follow-up pan to coalesce. Integer-only entry keeps the typed value in
  /// sync with the dial's whole-degree readout (Issue #113).
  Future<void> _openKeyboard() async {
    final l = AppLocalizations.of(context);
    // Supersede any pending pan/tap debounce up front, so a ring interaction in
    // the 250ms before this tap can't fire its commit while the dialog is open
    // (which would write the transient ring value on top of the typed one).
    _commitTimer?.cancel();
    final displayedC = _optimisticC ?? widget.device.targetTemperature;
    final celsius = await showDialog<double>(
      context: context,
      builder: (_) => TempEntryDialog(
        valueC: displayedC,
        scale: widget.displayUnit,
        accent: TemperatureDial.gradientColorsFor(widget.device.mode).first,
        numeralStyle: ref.read(numeralFontProvider).style,
        allowDecimal: false,
        title: l.homeTempEntryTitle,
        confirmLabel: l.homeTempEntryConfirm,
        cancelLabel: l.homeTempEntryCancel,
      ),
    );
    if (!mounted || celsius == null) return;
    _commit(celsius);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final device = widget.device;

    if (_isDual) {
      final low = _optimisticLowC ?? device.targetTemperatureLow!;
      final high = _optimisticHighC ?? device.targetTemperatureHigh!;
      return TemperatureDial(
        currentTemperatureCelsius: device.currentTemperature,
        // The scalar is unused for the dual band, but the widget still requires
        // it — pass the midpoint so a mid-gesture fallback (a bound going null)
        // lands somewhere sane.
        targetTemperatureCelsius: (low + high) / 2,
        targetLowCelsius: low,
        targetHighCelsius: high,
        mode: device.mode,
        displayUnit: widget.displayUnit,
        capabilities: device.capabilities,
        onRangeDragUpdate: _onRangeDragUpdate,
        onRangeDragEnd: _onRangeDragEnd,
        onRangeTap: _onRangeTap,
        numeralStyle: ref.watch(numeralFontProvider).style,
        humidityPercent: device.humidity,
        onTargetTextTap: _openRangeKeyboard,
        targetTapSemanticLabel: l.homeSetTemperature,
        rangeHeatLabel: l.homeDialHeatLabel,
        rangeCoolLabel: l.homeDialCoolLabel,
        rangeSemanticLabel: l.homeDialRangeSemantics(
          _fmt(low),
          _fmt(high),
          _fmt(device.currentTemperature),
          device.humidity > 0 ? ' Humidity ${device.humidity} percent.' : '',
        ),
      );
    }

    final displayedC = _optimisticC ?? device.targetTemperature;
    return TemperatureDial(
      currentTemperatureCelsius: device.currentTemperature,
      targetTemperatureCelsius: displayedC,
      mode: device.mode,
      displayUnit: widget.displayUnit,
      capabilities: device.capabilities,
      onTargetDragUpdate: _onDragUpdate,
      onTargetDragEnd: _onDragEnd,
      onTargetTap: _onTap,
      onIncrease: () => _bump(1),
      onDecrease: () => _bump(-1),
      numeralStyle: ref.watch(numeralFontProvider).style,
      humidityPercent: device.humidity,
      onTargetTextTap: _openKeyboard,
      targetTapSemanticLabel: l.homeSetTemperature,
    );
  }

  /// Format a Celsius value as a rounded, unit-suffixed display string (e.g.
  /// "68°F") for the dual-band screen-reader announcement.
  String _fmt(double celsius) {
    final display = TemperatureDial.celsiusToDisplay(
      celsius,
      widget.displayUnit,
    ).round();
    return '$display°${_isF ? 'F' : 'C'}';
  }
}
