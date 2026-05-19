import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Segmented-ring temperature dial per `docs/DESIGN.md` §10.3.
///
/// Presentational only — no gesture handling. Gestures land in issue #11.
/// All temperatures flow through this widget in Celsius (the server's native
/// unit per DESIGN §8.1); display-time conversion to Fahrenheit happens here
/// based on [displayUnit] without ever changing the tick mapping.
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
class TemperatureDial extends StatelessWidget {
  /// Total tick count. Mid-range of the §10.3 60-80 spec. 60 ticks per 5° of
  /// arc + 12 trailing makes the math clean (3.75° per tick).
  static const int tickCount = 72;

  /// Minimum displayable temperature in Celsius. Maps to tick 0.
  /// Matches NLE's documented setpoint range (DESIGN §11.3).
  static const double minCelsius = 4.5;

  /// Maximum displayable temperature in Celsius. Maps to the final tick.
  static const double maxCelsius = 32.0;

  /// Arc start angle (radians). Tick 0 sits at the south-west, then ticks
  /// sweep clockwise across the top. Using Flutter's canvas convention where
  /// 0 rad points east and positive angles rotate clockwise.
  static const double _arcStart = 3 * math.pi / 4; // 135°.

  /// Total arc swept by the tick band, in radians. 270° leaves a 90° gap at
  /// the bottom of the dial.
  static const double _arcSweep = 3 * math.pi / 2;

  /// Diameter target in logical pixels (§10.3 "~240dp"). Provided so callers
  /// can wrap the widget in a `SizedBox`/`ConstrainedBox` with a known size;
  /// the widget itself just enforces a 1:1 `AspectRatio` and fills whatever
  /// box it's given.
  static const double preferredDiameter = 240.0;

  /// Current temperature in degrees Celsius.
  final double currentTemperatureCelsius;

  /// Target temperature in degrees Celsius.
  final double targetTemperatureCelsius;

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

  const TemperatureDial({
    super.key,
    required this.currentTemperatureCelsius,
    required this.targetTemperatureCelsius,
    required this.mode,
    required this.displayUnit,
    required this.capabilities,
    this.animationDuration = const Duration(milliseconds: 400),
    this.animationCurve = Curves.easeInOutCubic,
  });

  /// Map a Celsius temperature to a discrete tick index in `[0, tickCount)`.
  /// Clamps out-of-range values; never throws.
  @visibleForTesting
  static int tickIndexForCelsius(double celsius) {
    final clamped = celsius.clamp(minCelsius, maxCelsius);
    final ratio = (clamped - minCelsius) / (maxCelsius - minCelsius);
    final raw = (ratio * (tickCount - 1)).round();
    return raw.clamp(0, tickCount - 1);
  }

  /// Convert a Celsius value to the chosen display unit. The temperature
  /// mapping that drives the ring is always in Celsius — this affects only
  /// the center-text rendering.
  @visibleForTesting
  static double celsiusToDisplay(double celsius, String unit) {
    if (unit.toUpperCase() == 'F') return celsius * 9 / 5 + 32;
    return celsius;
  }

  /// Pick the mode-appropriate gradient stops for active ticks.
  @visibleForTesting
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

  @override
  Widget build(BuildContext context) {
    final targetIndex = tickIndexForCelsius(targetTemperatureCelsius);
    final currentIndex = tickIndexForCelsius(currentTemperatureCelsius);

    // Format center text up-front so we don't recompute on every paint.
    final targetDisplay = celsiusToDisplay(
      targetTemperatureCelsius,
      displayUnit,
    );
    final currentDisplay = celsiusToDisplay(
      currentTemperatureCelsius,
      displayUnit,
    );

    final targetLabel = '${targetDisplay.round()}°';
    final currentLabel = 'Currently ${currentDisplay.round()}°';

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
      duration: animationDuration,
      curve: animationCurve,
      builder: (context, animatedIndex, _) {
        return AspectRatio(
          aspectRatio: 1.0,
          child: CustomPaint(
            painter: _TemperatureDialPainter(
              animatedActiveIndex: animatedIndex,
              currentIndex: currentIndex,
              gradientColors: gradientColorsFor(mode),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(targetLabel, style: EmberTypography.displayLarge()),
                  const SizedBox(height: 8),
                  Text(currentLabel, style: EmberTypography.bodyMediumItalic()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TemperatureDialPainter extends CustomPainter {
  /// Animated fill cursor — a continuous value in `[0, tickCount - 1]` that
  /// the tween interpolates between target-temp changes. Ticks with index
  /// `<= animatedActiveIndex` paint as "active"; the rest paint inactive.
  final double animatedActiveIndex;

  /// Index of the tick that should pop as the "current temperature" indicator.
  final int currentIndex;

  /// Mode-gradient stops (high -> low) for active ticks.
  final List<Color> gradientColors;

  static const _tickStrokeWidth = 3.0;
  static const _tickLengthRatio = 0.10; // fraction of radius
  static const _inactiveColor = Color(0x0FFFFFFF); // rgba(255, 255, 255, 0.06)

  _TemperatureDialPainter({
    required this.animatedActiveIndex,
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
        TemperatureDial._arcSweep / (TemperatureDial.tickCount - 1);
    final lastIndex = TemperatureDial.tickCount - 1;

    for (int i = 0; i < TemperatureDial.tickCount; i++) {
      final theta = TemperatureDial._arcStart + i * stepRadians;
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

      if (i <= animatedActiveIndex) {
        // Interpolate along the mode gradient so the band has a subtle
        // value shift from start to end. `gradientColors` is (high, low).
        final t = i / lastIndex;
        paint
          ..color = Color.lerp(gradientColors[0], gradientColors[1], t)!
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.0);
      } else {
        paint.color = _inactiveColor;
      }

      canvas.drawLine(inner, outer, paint);

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
    return old.animatedActiveIndex != animatedActiveIndex ||
        old.currentIndex != currentIndex ||
        old.gradientColors != gradientColors;
  }
}
