import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/colors.dart';

/// Page-indicator dots rendered under the dial when ≥2 devices are present
/// (DESIGN §4.2). The active dot is colored by the active device's mode; the
/// rest are dim. Used purely as a non-interactive position indicator — the
/// `PageView` itself owns the swipe gesture.
class DeviceIndicatorDots extends StatelessWidget {
  final int count;
  final int activeIndex;
  final DeviceMode activeMode;

  const DeviceIndicatorDots({
    super.key,
    required this.count,
    required this.activeIndex,
    required this.activeMode,
  });

  Color _activeColor() {
    switch (activeMode) {
      case DeviceMode.heat:
      case DeviceMode.emergency:
        return EmberColors.heatGlow;
      case DeviceMode.cool:
        return EmberColors.coolGlow;
      case DeviceMode.heatCool:
      case DeviceMode.off:
        return EmberColors.textPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox.shrink();
    final active = _activeColor();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == activeIndex
                    ? active
                    : EmberColors.textTertiary.withValues(alpha: 0.6),
              ),
            ),
          ),
      ],
    );
  }
}
