import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/colors.dart';

/// Mode-aware radial-gradient background per `docs/DESIGN.md` §10.7 / §11.2.
///
/// Renders the per-mode background gradient with a soft accent-color glow
/// overlay. Animates between gradients over 300ms with `easeInOutCubic` when
/// `mode` changes (e.g., user swipes between devices, or toggles modes).
///
/// Intentionally does NOT use `BackdropFilter` — that path is GPU-expensive on
/// Android API 24-26 hardware, which is in our supported range.
class EmberBackground extends StatelessWidget {
  /// The active device mode. Drives gradient + glow color selection.
  final DeviceMode mode;

  /// Child content rendered on top of the gradient.
  final Widget child;

  /// Animation duration for mode-swap transitions. Defaults to 300ms per spec.
  final Duration duration;

  /// Animation curve for mode-swap transitions. Defaults to `easeInOutCubic`.
  final Curve curve;

  const EmberBackground({
    super.key,
    required this.mode,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeInOutCubic,
  });

  /// Glow-overlay geometry, exposed so other screen-local glow layers (e.g.
  /// the Schedule-in-control tint, Issue #97) can reuse the exact same visual
  /// vocabulary instead of re-hardcoding drift-prone literals.
  static const double glowAlpha = 0.18;
  static const Alignment glowCenter = Alignment(0.0, -0.3);
  static const double glowRadius = 0.9;

  /// The base radial-gradient color stops for the given mode.
  @visibleForTesting
  static List<Color> backgroundColorsFor(DeviceMode mode) {
    switch (mode) {
      case DeviceMode.heat:
      case DeviceMode.emergency:
        return EmberColors.heatBackground;
      case DeviceMode.cool:
        return EmberColors.coolBackground;
      case DeviceMode.heatCool:
      case DeviceMode.off:
        return EmberColors.neutralBackground;
    }
  }

  /// The soft accent glow color for the given mode, or transparent for off /
  /// auto where no mode-specific glow applies.
  @visibleForTesting
  static Color glowColorFor(DeviceMode mode) {
    switch (mode) {
      case DeviceMode.heat:
      case DeviceMode.emergency:
        return EmberColors.heatGlow;
      case DeviceMode.cool:
        return EmberColors.coolGlow;
      case DeviceMode.heatCool:
      case DeviceMode.off:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColors = backgroundColorsFor(mode);
    final glow = glowColorFor(mode);

    return AnimatedContainer(
      duration: duration,
      curve: curve,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: backgroundColors,
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Mode-color glow overlay. Lives in its own AnimatedContainer so the
          // glow gradient interpolates independently from the base gradient.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: duration,
                curve: curve,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: glowCenter,
                    radius: glowRadius,
                    colors: [
                      glow.withValues(alpha: glowAlpha),
                      glow.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
