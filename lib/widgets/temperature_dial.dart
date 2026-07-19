import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/haptics.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Reports a resolved heat-cool `(low, high)` Celsius pair from a dual-band
/// gesture (Issue #116). Both bounds are always sent — a single drag can move
/// one marker and shove the other to preserve the deadband.
typedef RangeChanged = void Function(double low, double high);

/// Segmented-ring temperature dial per `docs/DESIGN.md` §10.3.
///
/// All temperatures flow through this widget in Celsius (the server's native
/// unit per DESIGN §8.1); display-time conversion to Fahrenheit happens here
/// based on [displayUnit] without ever changing the tick mapping.
///
/// When [onTargetDragUpdate] / [onTargetDragEnd] / [onTargetTap] are supplied,
/// the dial becomes interactive per DESIGN §11.3: tap-to-jump, drag-anywhere,
/// and a throttled tick-snap haptic. The widget never POSTs anything itself —
/// the parent (see `InteractiveTemperatureDial`) owns optimistic state and
/// the `set_temperature` write.
///
/// Visual contract:
/// - 72 discrete radial tick marks span 270° of arc (3.75° per tick), leaving
///   the bottom 90° open. Tick 0 anchors at angle 135° (south-west), then
///   sweeps clockwise through the top to tick 71 at angle 45° (south-east).
/// - Active ticks are everything from index 0 up to (and including) the tick
///   nearest the target temperature; they paint in the mode-gradient with a
///   `MaskFilter.blur(BlurStyle.solid, 2.0)` glow.
/// - Inactive ticks paint at `rgba(255, 255, 255, 0.06)`.
/// - A single brighter "current" tick is painted at the index nearest the
///   current temperature, on top of whichever band it falls in.
/// - Center text: target temp in Fraunces (`displayLarge`) above the current
///   temp readout in italic Instrument Serif (`bodyMediumItalic`).
class TemperatureDial extends StatefulWidget {
  /// Total tick count. Mid-range of the §10.3 60-80 spec. 60 ticks per 5° of
  /// arc + 12 trailing makes the math clean (3.75° per tick).
  static const int tickCount = 72;

  /// Minimum displayable temperature in Celsius. Maps to tick 0.
  /// Matches NLE's documented setpoint range (DESIGN §11.3).
  static const double minCelsius = 4.5;

  /// Maximum displayable temperature in Celsius. Maps to the final tick.
  static const double maxCelsius = 32.0;

  /// Minimum gap enforced between the heat (low) and cool (high) setpoints in
  /// heat-cool mode, in Celsius (≈3°F). A single app-wide constant (Issue #116)
  /// — the Schedule Auto event editor (#102) references the same value so the
  /// dial and the schedule never disagree on the deadband.
  static const double deadbandCelsius = 1.5;

  /// Arc start angle (radians). Tick 0 sits at the south-west, then ticks
  /// sweep clockwise across the top. Using Flutter's canvas convention where
  /// 0 rad points east and positive angles rotate clockwise.
  static const double arcStart = 3 * math.pi / 4; // 135°.

  /// Total arc swept by the tick band, in radians. 270° leaves a 90° gap at
  /// the bottom of the dial.
  static const double arcSweep = 3 * math.pi / 2;

  /// Diameter target in logical pixels (§10.3 "~240dp"). Provided so callers
  /// can wrap the widget in a `SizedBox`/`ConstrainedBox` with a known size;
  /// the widget itself just enforces a 1:1 `AspectRatio` and fills whatever
  /// box it's given.
  static const double preferredDiameter = 240.0;

  /// Current temperature in degrees Celsius.
  final double currentTemperatureCelsius;

  /// Target temperature in degrees Celsius. In heat-cool with a dual band
  /// (see [targetLowCelsius]/[targetHighCelsius]) this scalar is unused for
  /// rendering — the band drives the display.
  final double targetTemperatureCelsius;

  /// Heat (low) setpoint in Celsius for the heat-cool dual band (Issue #116).
  /// When [mode] is [DeviceMode.heatCool] and both this and [targetHighCelsius]
  /// are non-null, the dial renders two markers + a warm→cool band + a stacked
  /// HEAT/COOL readout. If either is null the dial falls back to the single
  /// [targetTemperatureCelsius] marker (today's behavior).
  final double? targetLowCelsius;

  /// Cool (high) setpoint in Celsius for the heat-cool dual band (Issue #116).
  /// See [targetLowCelsius].
  final double? targetHighCelsius;

  /// HVAC mode — drives the tick gradient colors.
  final DeviceMode mode;

  /// Display unit: `'C'` or `'F'`. Drives only the center-text formatting.
  final String displayUnit;

  /// Capabilities of the underlying device. Reserved for future mode-color
  /// derivations (e.g., when `heatCool` is active and a side of the
  /// gradient should reflect capability availability).
  final Capabilities capabilities;

  /// Animation duration for the tween triggered by [targetTemperatureCelsius]
  /// changes. Defaults to 400ms per DESIGN §11.4.
  final Duration animationDuration;

  /// Animation curve for the target-temp tween. Defaults to `easeInOutCubic`.
  final Curve animationCurve;

  /// Called continuously while the user drags or taps the dial, with the new
  /// celsius target derived from the touch point. The parent uses this for
  /// the optimistic UI update during interaction. When this is `null`, the
  /// dial does not install a [GestureDetector] and stays purely presentational.
  final ValueChanged<double>? onTargetDragUpdate;

  /// Called once at the end of a pan gesture, with the final celsius target.
  /// The parent uses this to debounce + POST `set_temperature`. When `null`,
  /// drag-end is ignored.
  final ValueChanged<double>? onTargetDragEnd;

  /// Called for a tap-to-jump gesture. Behaves like an end-of-pan write: the
  /// parent should treat it as both an optimistic update AND a commit point.
  final ValueChanged<double>? onTargetTap;

  /// Dual-band (heat-cool) analogues of [onTargetDragUpdate]/[onTargetDragEnd]/
  /// [onTargetTap] (Issue #116). The dial resolves the nearest marker, applies
  /// the push + deadband + rail rules ([applyRangeDrag]), and reports the whole
  /// resulting `(low, high)` Celsius pair — one drag may move both bounds. Only
  /// consulted when the dial is rendering a dual band; null keeps the ring
  /// presentation-only in heat-cool.
  final RangeChanged? onRangeDragUpdate;
  final RangeChanged? onRangeDragEnd;
  final RangeChanged? onRangeTap;

  /// Optional callback wired to the [Semantics.onIncrease] action so screen
  /// readers (TalkBack/VoiceOver) can adjust the target temperature without
  /// the user needing to interact with the visual ring. Called with the
  /// requested ±direction; the parent owns the actual increment math + write.
  /// When `null`, no `onIncrease`/`onDecrease` actions are advertised to
  /// assistive tech — useful for the read-only fixture renderings in tests.
  final VoidCallback? onIncrease;

  /// Companion to [onIncrease] for the `onDecrease` action.
  final VoidCallback? onDecrease;

  /// Numeral face for the big target-temperature readout, merged onto the
  /// display style. Null keeps the theme's Fraunces display face.
  final TextStyle? numeralStyle;

  /// Current relative humidity as a whole percent, shown beside the measured
  /// temperature in the "Currently …" line. Null hides the humidity readout.
  final int? humidityPercent;

  /// Called when the large target-temperature readout is tapped, to open the
  /// keyboard-entry alternative to the ring. When `null`, the readout is not
  /// tappable (read-only renderings, and the ring's tap-to-jump is unaffected).
  /// Only the target number carries this — the "Currently …" line stays a
  /// plain readout.
  final VoidCallback? onTargetTextTap;

  /// Accessible label for the [onTargetTextTap] button (e.g. "Set
  /// temperature"). Required in practice whenever [onTargetTextTap] is set.
  final String? targetTapSemanticLabel;

  /// Visible "HEAT"/"COOL" labels for the stacked dual-band readout (Issue
  /// #116), supplied localized by the parent so the dial stays presentation-
  /// only. Only used when [isDualBand] is true.
  final String? rangeHeatLabel;
  final String? rangeCoolLabel;

  /// Screen-reader announcement for the heat-cool dual band, built by the
  /// parent (it owns localization). Only used when [isDualBand] is true.
  final String? rangeSemanticLabel;

  const TemperatureDial({
    super.key,
    required this.currentTemperatureCelsius,
    required this.targetTemperatureCelsius,
    required this.mode,
    required this.displayUnit,
    required this.capabilities,
    this.targetLowCelsius,
    this.targetHighCelsius,
    this.humidityPercent,
    this.animationDuration = const Duration(milliseconds: 400),
    this.animationCurve = Curves.easeInOutCubic,
    this.onTargetDragUpdate,
    this.onTargetDragEnd,
    this.onTargetTap,
    this.onRangeDragUpdate,
    this.onRangeDragEnd,
    this.onRangeTap,
    this.onIncrease,
    this.onDecrease,
    this.numeralStyle,
    this.onTargetTextTap,
    this.targetTapSemanticLabel,
    this.rangeHeatLabel,
    this.rangeCoolLabel,
    this.rangeSemanticLabel,
  }) : assert(
         onTargetTextTap == null || targetTapSemanticLabel != null,
         'targetTapSemanticLabel is required when onTargetTextTap is set, '
         'so the tappable readout has an accessible name.',
       );

  /// Whether the dial should render the heat-cool dual band (Issue #116): a
  /// heat-cool device that reports both bounds. A null bound falls back to the
  /// single-marker rendering.
  bool get isDualBand =>
      mode == DeviceMode.heatCool &&
      targetLowCelsius != null &&
      targetHighCelsius != null;

  bool get _interactive =>
      onTargetDragUpdate != null ||
      onTargetDragEnd != null ||
      onTargetTap != null ||
      onRangeDragUpdate != null ||
      onRangeDragEnd != null ||
      onRangeTap != null;

  @override
  State<TemperatureDial> createState() => _TemperatureDialState();

  /// Map a Celsius temperature to a discrete tick index in `[0, tickCount)`.
  /// Clamps out-of-range values; never throws.
  static int tickIndexForCelsius(double celsius) {
    final clamped = celsius.clamp(minCelsius, maxCelsius);
    final ratio = (clamped - minCelsius) / (maxCelsius - minCelsius);
    final raw = (ratio * (tickCount - 1)).round();
    return raw.clamp(0, tickCount - 1);
  }

  /// Inverse of [tickIndexForCelsius]. Maps a tick index to the celsius
  /// value at that position on the ring. Out-of-range indexes are clamped.
  static double celsiusForTickIndex(int index) {
    final clamped = index.clamp(0, tickCount - 1);
    final ratio = clamped / (tickCount - 1);
    return minCelsius + ratio * (maxCelsius - minCelsius);
  }

  /// Map a local touch point inside a square widget [size] to a tick index,
  /// or `null` if the touch falls in the bottom-90° gap that the ring doesn't
  /// cover. Beyond-arc but still-meaningful angles are clamped to the
  /// nearest end-tick (so the user can drag past the top edge without losing
  /// the target).
  @visibleForTesting
  static int? tickIndexForLocalPoint(Offset local, Size size) {
    final dx = local.dx - size.width / 2;
    final dy = local.dy - size.height / 2;
    if (dx == 0 && dy == 0) return null;

    var theta = math.atan2(dy, dx); // [-π, π], east=0, south=+π/2.
    if (theta < arcStart) {
      // Normalize into [arcStart, arcStart + 2π) so the bottom half of the
      // arc lands on the positive side of the sweep.
      theta += 2 * math.pi;
    }
    final pos = theta - arcStart; // arc-local angle, 0 at tick 0.
    if (pos > arcSweep) {
      // Touch landed in the bottom-90° gap. Snap to whichever end is closer
      // so a drag past the bottom doesn't suddenly drop tracking.
      final gapMid = arcSweep + (2 * math.pi - arcSweep) / 2;
      return pos < gapMid ? tickCount - 1 : 0;
    }
    final step = arcSweep / (tickCount - 1);
    return (pos / step).round().clamp(0, tickCount - 1);
  }

  /// Convert a Celsius value to the chosen display unit. The temperature
  /// mapping that drives the ring is always in Celsius — this affects only
  /// the center-text rendering. Also reused by Details / Schedule callers
  /// that need to render the same conversion.
  static double celsiusToDisplay(double celsius, String unit) {
    if (unit.toUpperCase() == 'F') return celsius * 9 / 5 + 32;
    return celsius;
  }

  /// Pick the mode-appropriate gradient stops for active ticks. Also reused by
  /// [InteractiveTemperatureDial] to derive a mode-matched accent for the
  /// keyboard-entry dialog.
  ///
  /// Note heat-cool stays neutral grey here: that gradient only drives the
  /// single-marker fallback (a heat-cool device that reports a null bound). The
  /// dual band (Issue #116) paints a warm→cool gradient via [rangeBandColors]
  /// instead — see [_TemperatureDialPainter].
  static List<Color> gradientColorsFor(DeviceMode mode) {
    switch (mode) {
      case DeviceMode.heat:
      case DeviceMode.emergency:
        return EmberColors.heatGradient;
      case DeviceMode.cool:
        return EmberColors.coolGradient;
      case DeviceMode.heatCool:
      case DeviceMode.off:
        // No mode-color cue — desaturated grey so the dial reads as inert
        // without going invisible. Matches the §10.3 "mode gradient" spec
        // by still being a 2-stop gradient, just neutral.
        return const [Color(0xFFA0A0A0), Color(0xFF606060)];
    }
  }

  /// Endpoint colors for the heat-cool dual band (Issue #116): the warm heat
  /// tone at the HEAT (low) marker lerping to the cool tone at the COOL (high)
  /// marker. Drawn from [EmberColors.heatGradient]/[EmberColors.coolGradient]
  /// so the band's ends match the single-mode heat and cool fills.
  static const List<Color> rangeBandColors = [
    Color(0xFFFF8A50), // EmberColors.heatGradient.first — warm, at HEAT.
    Color(0xFF3070D0), // EmberColors.coolGradient.last — cool, at COOL.
  ];

  /// Which marker a touch at [draggedC] grabs: the HEAT (low) marker if it is
  /// nearest by tick distance, else COOL (high). An exact-midpoint tie grabs
  /// HEAT. The grab is resolved once at gesture start and held for the whole
  /// drag, so pushing one marker past the other doesn't hand the drag off.
  static bool nearestIsLow({
    required double low,
    required double high,
    required double draggedC,
  }) {
    final dragTick = tickIndexForCelsius(
      draggedC.clamp(minCelsius, maxCelsius),
    );
    final distLow = (dragTick - tickIndexForCelsius(low)).abs();
    final distHigh = (dragTick - tickIndexForCelsius(high)).abs();
    return distLow <= distHigh; // tie → HEAT/low
  }

  /// Move the grabbed marker to [draggedC], preserving the [deadbandCelsius]
  /// gap by shoving the other marker, and clamping both to the
  /// `[minCelsius, maxCelsius]` rails — when the shoved marker hits a rail the
  /// dragged one stops too, so the gap is never violated. [moveLow] selects
  /// the HEAT (low) marker; false selects COOL (high). Pure and total.
  static ({double low, double high}) moveMarker({
    required double low,
    required double high,
    required bool moveLow,
    required double draggedC,
  }) {
    final dragged = draggedC.clamp(minCelsius, maxCelsius);
    if (moveLow) {
      var newLow = dragged;
      var newHigh = high;
      if (newLow > newHigh - deadbandCelsius) {
        newHigh = newLow + deadbandCelsius;
        if (newHigh > maxCelsius) {
          newHigh = maxCelsius;
          newLow = maxCelsius - deadbandCelsius;
        }
      }
      return (low: newLow, high: newHigh);
    } else {
      var newHigh = dragged;
      var newLow = low;
      if (newHigh < newLow + deadbandCelsius) {
        newLow = newHigh - deadbandCelsius;
        if (newLow < minCelsius) {
          newLow = minCelsius;
          newHigh = minCelsius + deadbandCelsius;
        }
      }
      return (low: newLow, high: newHigh);
    }
  }
}

class _TemperatureDialState extends State<TemperatureDial> {
  /// Last tick index for which a selection-click haptic fired. Used to throttle
  /// haptics to once per tick crossed (DESIGN §11.3 + §11.5).
  int? _lastHapticTick;

  /// ~30/sec rate-limiter for `selectionClick`. Lives in
  /// `lib/services/haptics.dart` so the throttle is unit-testable in isolation.
  final ThrottledSelectionClick _hapticThrottle = ThrottledSelectionClick();

  /// Last celsius value observed during a drag — used as the commit value on
  /// `onPanEnd` since [DragEndDetails] doesn't carry a position.
  double? _lastDragCelsius;

  /// Dual-band analogue of [_lastDragCelsius]: the last resolved `(low, high)`
  /// pair during a heat-cool drag, committed on `onPanEnd` (Issue #116).
  ({double low, double high})? _lastDragRange;

  /// Which marker the active dual-band pan grabbed — resolved once at pan start
  /// and held for the gesture so a push doesn't hand the drag to the other
  /// marker. `null` between gestures.
  bool? _rangeGrabLow;

  void _dispatchPan(Offset local, Size size) {
    final tick = TemperatureDial.tickIndexForLocalPoint(local, size);
    if (tick == null) return;
    final celsius = TemperatureDial.celsiusForTickIndex(tick);
    _lastDragCelsius = celsius;
    _maybeHaptic(tick);
    widget.onTargetDragUpdate?.call(celsius);
  }

  void _dispatchPanEnd() {
    final celsius = _lastDragCelsius;
    _lastDragCelsius = null;
    if (celsius == null) return;
    widget.onTargetDragEnd?.call(celsius);
  }

  void _dispatchTap(Offset local, Size size) {
    final tick = TemperatureDial.tickIndexForLocalPoint(local, size);
    if (tick == null) return;
    final celsius = TemperatureDial.celsiusForTickIndex(tick);
    _maybeHaptic(tick);
    // A tap pushes the optimistic value AND commits — parent treats both
    // callbacks as a single user intent.
    widget.onTargetDragUpdate?.call(celsius);
    widget.onTargetTap?.call(celsius);
  }

  /// The large target readout. When [TemperatureDial.onTargetTextTap] is set
  /// (interactive Home), wrap it as a tappable "set temperature" button: a
  /// nested [GestureDetector] wins the tap over the ring's ancestor tap-to-jump
  /// while pans still fall through to the ring, and the [Semantics] node gives
  /// screen-reader users a typed-entry action alongside the adjustable slider.
  /// With no callback it's a plain readout (read-only renderings).
  Widget _buildTargetLabel(String targetLabel) {
    final text = Text(
      targetLabel,
      style: EmberTypography.displayLarge().merge(widget.numeralStyle),
    );
    final onTap = widget.onTargetTextTap;
    if (onTap == null) return text;
    return Semantics(
      button: true,
      label: widget.targetTapSemanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: text,
      ),
    );
  }

  void _maybeHaptic(int tick) {
    if (_lastHapticTick == tick) {
      return;
    }
    _lastHapticTick = tick;
    // The throttler silently drops the click if it's within minGap of the last
    // one; the tick-tracking above is what ensures we don't spam the throttler
    // with the same tick repeatedly across drag updates.
    _hapticThrottle.tryClick();
  }

  /// Compute the display-unit value of the tick [direction] steps away from
  /// [fromIndex], clamping at the band ends so the screen reader's
  /// "increasedValue"/"decreasedValue" preview never reports out-of-range.
  static double _adjacentDisplay(
    int fromIndex,
    int direction,
    TemperatureDial widget,
  ) {
    final next = (fromIndex + direction).clamp(
      0,
      TemperatureDial.tickCount - 1,
    );
    final celsius = TemperatureDial.celsiusForTickIndex(next);
    return TemperatureDial.celsiusToDisplay(celsius, widget.displayUnit);
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = TemperatureDial.tickIndexForCelsius(
      widget.currentTemperatureCelsius,
    );

    // Reduced motion (§11.7): snap the target-tween to a 0ms duration so the
    // dial jumps instead of animating. Keep the curve identity — for zero
    // duration the curve doesn't matter, but we don't want to special-case
    // the builder.
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final tweenDuration = reducedMotion
        ? Duration.zero
        : widget.animationDuration;

    final currentDisplay = TemperatureDial.celsiusToDisplay(
      widget.currentTemperatureCelsius,
      widget.displayUnit,
    );
    final currentLabel = widget.humidityPercent != null
        ? '${currentDisplay.round()}° · ${widget.humidityPercent}%'
        : '${currentDisplay.round()}°';

    return widget.isDualBand
        ? _buildDual(context, currentIndex, tweenDuration, currentLabel)
        : _buildSingle(context, currentIndex, tweenDuration, currentLabel);
  }

  /// Wrap the center readout in the shared dial scaffolding: a 1:1
  /// [AspectRatio], the ring [CustomPaint], and the §14.5 text-scale clamp so
  /// the center never blows out of the 240dp circle.
  Widget _dialScaffold({
    required CustomPainter painter,
    required Widget centerColumn,
    required Widget Function(Widget canvas, Size size) wrap,
  }) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final canvas = CustomPaint(
            painter: painter,
            child: Center(
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: MediaQuery.of(
                    context,
                  ).textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.4),
                ),
                child: centerColumn,
              ),
            ),
          );
          return wrap(canvas, size);
        },
      ),
    );
  }

  /// Single-marker dial (heat/cool/off, and heat-cool with a null bound).
  Widget _buildSingle(
    BuildContext context,
    int currentIndex,
    Duration tweenDuration,
    String currentLabel,
  ) {
    final targetIndex = TemperatureDial.tickIndexForCelsius(
      widget.targetTemperatureCelsius,
    );
    final targetDisplay = TemperatureDial.celsiusToDisplay(
      widget.targetTemperatureCelsius,
      widget.displayUnit,
    );
    final targetLabel = '${targetDisplay.round()}°';

    // Screen-reader announcement: TalkBack/VoiceOver reads the label, then the
    // value, then "tap to adjust" implicit on the slider role. The
    // increase/decrease actions become swipe-up/swipe-down gestures.
    final semanticUnit = widget.displayUnit.toUpperCase() == 'F'
        ? 'Fahrenheit'
        : 'Celsius';
    final humiditySemantics = widget.humidityPercent != null
        ? ' Humidity ${widget.humidityPercent} percent.'
        : '';
    final semanticLabel =
        'Target temperature, '
        'currently set to ${targetDisplay.round()} $semanticUnit. '
        'Current temperature ${_currentDisplayRounded()} $semanticUnit.'
        '$humiditySemantics';

    return TweenAnimationBuilder<double>(
      // TweenAnimationBuilder tracks the previously-rendered value as the new
      // `begin` automatically: when the widget rebuilds with a different
      // `tween.end`, the framework animates from the last drawn value over
      // `duration`. So we only need to set `end` to the live target index.
      // The initial frame uses tween.begin verbatim (no animation).
      tween: Tween<double>(
        begin: targetIndex.toDouble(),
        end: targetIndex.toDouble(),
      ),
      duration: tweenDuration,
      curve: widget.animationCurve,
      builder: (context, animatedIndex, _) {
        final centerColumn = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTargetLabel(targetLabel),
            const SizedBox(height: 8),
            Text(
              currentLabel,
              style: EmberTypography.bodyMedium(
                color: EmberColors.textSecondary,
              ).merge(widget.numeralStyle),
            ),
          ],
        );
        return _dialScaffold(
          painter: _TemperatureDialPainter(
            lowFillIndex: 0,
            highFillIndex: animatedIndex,
            dual: false,
            currentIndex: currentIndex,
            gradientColors: TemperatureDial.gradientColorsFor(widget.mode),
          ),
          centerColumn: centerColumn,
          wrap: (canvas, size) {
            if (!widget._interactive) {
              return Semantics(
                label: semanticLabel,
                value: '${targetDisplay.round()}°$semanticUnit',
                readOnly: true,
                child: canvas,
              );
            }
            // increasedValue/decreasedValue describe what the value will
            // BECOME after the increase/decrease action — required by the
            // Semantics framework whenever the corresponding onIncrease /
            // onDecrease actions are set. Compute the next/prev tick's
            // display value so screen readers can preview the change.
            final nextDisplay = _adjacentDisplay(targetIndex, 1, widget);
            final prevDisplay = _adjacentDisplay(targetIndex, -1, widget);
            return Semantics(
              slider: true,
              label: semanticLabel,
              value: '${targetDisplay.round()}°$semanticUnit',
              increasedValue: '${nextDisplay.round()}°$semanticUnit',
              decreasedValue: '${prevDisplay.round()}°$semanticUnit',
              onIncrease: widget.onIncrease,
              onDecrease: widget.onDecrease,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => _dispatchPan(d.localPosition, size),
                onPanUpdate: (d) => _dispatchPan(d.localPosition, size),
                onPanEnd: (_) => _dispatchPanEnd(),
                onTapUp: (d) => _dispatchTap(d.localPosition, size),
                child: canvas,
              ),
            );
          },
        );
      },
    );
  }

  /// Heat-cool dual-band dial (Issue #116): two markers, a warm→cool band, and
  /// a stacked HEAT/COOL readout. Both bounds animate together via a
  /// [_DialBand] tween so reduced-motion and the +1/+3/+7s reconciliation
  /// tween the two markers in lockstep.
  Widget _buildDual(
    BuildContext context,
    int currentIndex,
    Duration tweenDuration,
    String currentLabel,
  ) {
    final lowC = widget.targetLowCelsius!;
    final highC = widget.targetHighCelsius!;
    final lowIndex = TemperatureDial.tickIndexForCelsius(lowC);
    final highIndex = TemperatureDial.tickIndexForCelsius(highC);
    final lowLabel =
        '${TemperatureDial.celsiusToDisplay(lowC, widget.displayUnit).round()}°';
    final highLabel =
        '${TemperatureDial.celsiusToDisplay(highC, widget.displayUnit).round()}°';

    return TweenAnimationBuilder<_DialBand>(
      tween: _DialBandTween(
        begin: _DialBand(lowIndex.toDouble(), highIndex.toDouble()),
        end: _DialBand(lowIndex.toDouble(), highIndex.toDouble()),
      ),
      duration: tweenDuration,
      curve: widget.animationCurve,
      builder: (context, band, _) {
        final centerColumn = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRangeReadout(lowLabel: lowLabel, highLabel: highLabel),
            const SizedBox(height: 8),
            Text(
              currentLabel,
              style: EmberTypography.bodyMedium(
                color: EmberColors.textSecondary,
              ).merge(widget.numeralStyle),
            ),
          ],
        );
        return _dialScaffold(
          painter: _TemperatureDialPainter(
            lowFillIndex: band.lowIndex,
            highFillIndex: band.highIndex,
            dual: true,
            currentIndex: currentIndex,
            gradientColors: TemperatureDial.rangeBandColors,
          ),
          centerColumn: centerColumn,
          wrap: (canvas, size) {
            final semanticsChild = Semantics(
              label: widget.rangeSemanticLabel,
              container: true,
              child: canvas,
            );
            if (!widget._interactive) return semanticsChild;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _dispatchRangePanStart(d.localPosition, size),
              onPanUpdate: (d) =>
                  _dispatchRangePanUpdate(d.localPosition, size),
              onPanEnd: (_) => _dispatchRangePanEnd(),
              onTapUp: (d) => _dispatchRangeTap(d.localPosition, size),
              child: semanticsChild,
            );
          },
        );
      },
    );
  }

  /// The display-unit current temperature, rounded — used in the single-mode
  /// semantic label.
  int _currentDisplayRounded() => TemperatureDial.celsiusToDisplay(
    widget.currentTemperatureCelsius,
    widget.displayUnit,
  ).round();

  /// Stacked HEAT / value / divider / value / COOL readout for the dual band.
  /// The whole stack is one tap target (Issue #116) that opens the dual-field
  /// range dialog via [TemperatureDial.onTargetTextTap]. Combined height is
  /// tuned to roughly match the single-setpoint number.
  Widget _buildRangeReadout({
    required String lowLabel,
    required String highLabel,
  }) {
    final numberStyle = EmberTypography.displayLarge()
        .merge(widget.numeralStyle)
        .copyWith(fontSize: 42, letterSpacing: -1.0, height: 1.0);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.rangeHeatLabel ?? '',
          style: EmberTypography.labelSmall(color: EmberColors.heatGlow),
        ),
        Text(lowLabel, style: numberStyle),
        Container(
          height: 1.5,
          width: 44,
          margin: const EdgeInsets.symmetric(vertical: 3),
          color: EmberColors.textTertiary,
        ),
        Text(highLabel, style: numberStyle),
        Text(
          widget.rangeCoolLabel ?? '',
          style: EmberTypography.labelSmall(color: EmberColors.coolGlow),
        ),
      ],
    );
    final onTap = widget.onTargetTextTap;
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: widget.targetTapSemanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }

  void _dispatchRangePanStart(Offset local, Size size) {
    final tick = TemperatureDial.tickIndexForLocalPoint(local, size);
    if (tick == null) {
      _rangeGrabLow = null;
      return;
    }
    final draggedC = TemperatureDial.celsiusForTickIndex(tick);
    // Resolve the grabbed marker once, at the start of the gesture.
    _rangeGrabLow = TemperatureDial.nearestIsLow(
      low: widget.targetLowCelsius!,
      high: widget.targetHighCelsius!,
      draggedC: draggedC,
    );
    _applyRangeMove(draggedC, tick);
  }

  void _dispatchRangePanUpdate(Offset local, Size size) {
    final tick = TemperatureDial.tickIndexForLocalPoint(local, size);
    if (tick == null) return;
    final draggedC = TemperatureDial.celsiusForTickIndex(tick);
    // If the pan started in the bottom gap (null tick), grab on first update.
    _rangeGrabLow ??= TemperatureDial.nearestIsLow(
      low: widget.targetLowCelsius!,
      high: widget.targetHighCelsius!,
      draggedC: draggedC,
    );
    _applyRangeMove(draggedC, tick);
  }

  void _applyRangeMove(double draggedC, int tick) {
    final next = TemperatureDial.moveMarker(
      low: widget.targetLowCelsius!,
      high: widget.targetHighCelsius!,
      moveLow: _rangeGrabLow!,
      draggedC: draggedC,
    );
    _lastDragRange = next;
    // The grabbed marker follows the dragged tick, so haptics keyed off the
    // dragged tick fire per-tick on the marker that is actually moving.
    _maybeHaptic(tick);
    widget.onRangeDragUpdate?.call(next.low, next.high);
  }

  void _dispatchRangePanEnd() {
    _rangeGrabLow = null;
    final r = _lastDragRange;
    _lastDragRange = null;
    if (r == null) return;
    widget.onRangeDragEnd?.call(r.low, r.high);
  }

  void _dispatchRangeTap(Offset local, Size size) {
    final tick = TemperatureDial.tickIndexForLocalPoint(local, size);
    if (tick == null) return;
    final draggedC = TemperatureDial.celsiusForTickIndex(tick);
    // A tap grabs the nearest marker for its single-shot move.
    final moveLow = TemperatureDial.nearestIsLow(
      low: widget.targetLowCelsius!,
      high: widget.targetHighCelsius!,
      draggedC: draggedC,
    );
    final next = TemperatureDial.moveMarker(
      low: widget.targetLowCelsius!,
      high: widget.targetHighCelsius!,
      moveLow: moveLow,
      draggedC: draggedC,
    );
    _maybeHaptic(tick);
    widget.onRangeDragUpdate?.call(next.low, next.high);
    widget.onRangeTap?.call(next.low, next.high);
  }
}

/// The pair of animated fill indices for the heat-cool dual band, so a single
/// [TweenAnimationBuilder] tweens both the HEAT and COOL markers together.
class _DialBand {
  final double lowIndex;
  final double highIndex;
  const _DialBand(this.lowIndex, this.highIndex);
}

class _DialBandTween extends Tween<_DialBand> {
  _DialBandTween({
    required _DialBand super.begin,
    required _DialBand super.end,
  });

  @override
  _DialBand lerp(double t) => _DialBand(
    lerpDouble(begin!.lowIndex, end!.lowIndex, t)!,
    lerpDouble(begin!.highIndex, end!.highIndex, t)!,
  );
}

class _TemperatureDialPainter extends CustomPainter {
  /// Lower edge of the active fill, a continuous value in `[0, tickCount - 1]`.
  /// Single-marker mode fills from tick 0, so this is 0; the heat-cool dual
  /// band (Issue #116) fills from the animated HEAT marker instead.
  final double lowFillIndex;

  /// Upper edge of the active fill (the single target marker, or the COOL
  /// marker in dual mode). Ticks in `[lowFillIndex, highFillIndex]` paint
  /// active; the rest inactive.
  final double highFillIndex;

  /// Whether to render the heat-cool dual band: two discrete markers at
  /// [lowFillIndex]/[highFillIndex] and a warm→cool gradient across the band.
  final bool dual;

  /// Index of the tick that should pop as the "current temperature" indicator.
  final int currentIndex;

  /// Active-tick gradient stops. Single mode: the mode gradient (high → low),
  /// interpolated across the whole ring. Dual mode: [TemperatureDial.rangeBandColors]
  /// (warm → cool), interpolated across the band only.
  final List<Color> gradientColors;

  static const _tickStrokeWidth = 3.0;
  static const _tickLengthRatio = 0.10; // fraction of radius
  static const _inactiveColor = Color(0x0FFFFFFF); // rgba(255, 255, 255, 0.06)

  _TemperatureDialPainter({
    required this.lowFillIndex,
    required this.highFillIndex,
    required this.dual,
    required this.currentIndex,
    required this.gradientColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    // Outer edge of the tick sits ~6dp in from the widget bounds. Tick length
    // is a fraction of the dial radius so it scales gracefully.
    final tickOuter = radius - 6;
    final tickInner = tickOuter - radius * _tickLengthRatio;

    final stepRadians =
        TemperatureDial.arcSweep / (TemperatureDial.tickCount - 1);
    final lastIndex = TemperatureDial.tickCount - 1;
    final lowMarker = lowFillIndex.round();
    final highMarker = highFillIndex.round();
    final bandSpan = highFillIndex - lowFillIndex;

    for (int i = 0; i < TemperatureDial.tickCount; i++) {
      final theta = TemperatureDial.arcStart + i * stepRadians;
      final cosTheta = math.cos(theta);
      final sinTheta = math.sin(theta);
      final outer = Offset(
        center.dx + tickOuter * cosTheta,
        center.dy + tickOuter * sinTheta,
      );
      final inner = Offset(
        center.dx + tickInner * cosTheta,
        center.dy + tickInner * sinTheta,
      );

      final paint = Paint()
        ..strokeWidth = _tickStrokeWidth
        ..strokeCap = StrokeCap.round;

      // Active = within the fill. Single mode fills from 0; dual fills only
      // between the two markers.
      final active = dual
          ? (i >= lowFillIndex && i <= highFillIndex)
          : (i <= highFillIndex);
      if (active) {
        // Interpolate along the gradient. Single mode shifts across the whole
        // ring; dual mode shifts across the band so the warm→cool blend is
        // visible regardless of where the band sits.
        final t = dual
            ? (bandSpan.abs() < 1e-6
                  ? 0.0
                  : ((i - lowFillIndex) / bandSpan).clamp(0.0, 1.0))
            : i / lastIndex;
        paint
          ..color = Color.lerp(gradientColors[0], gradientColors[1], t)!
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.0);
      } else {
        paint.color = _inactiveColor;
      }

      canvas.drawLine(inner, outer, paint);

      // Dual-band markers: a thicker, saturated handle at each setpoint tick so
      // the two draggable bounds read as discrete markers over the band.
      if (dual && (i == lowMarker || i == highMarker)) {
        final marker = Paint()
          ..color = i == lowMarker ? gradientColors.first : gradientColors.last
          ..strokeWidth = _tickStrokeWidth + 2.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.5);
        canvas.drawLine(inner, outer, marker);
      }

      // Current-temperature pop: a slightly thicker, brighter overlay tick.
      // Drawn last so it sits on top of whichever band it falls in.
      if (i == currentIndex) {
        final overlay = Paint()
          ..color = EmberColors.textPrimary
          ..strokeWidth = _tickStrokeWidth + 1.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.5);
        canvas.drawLine(inner, outer, overlay);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TemperatureDialPainter old) {
    return old.lowFillIndex != lowFillIndex ||
        old.highFillIndex != highFillIndex ||
        old.dual != dual ||
        old.currentIndex != currentIndex ||
        old.gradientColors != gradientColors;
  }
}
