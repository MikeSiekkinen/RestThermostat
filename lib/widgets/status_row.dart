import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/device_display_name.dart';
import '../services/state_derivation.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Home-screen status row per `docs/DESIGN.md` §9.2 + `docs/PRD.md` §5.2.
///
/// Renders a pulsing color-coded dot, the derived status label, and the
/// device display name (per [displayNameFor], DESIGN §4.4). Sits above the
/// dial on the home screen.
///
/// The dot's brightness pulses on a 2.5s ease-in-out repeat per DESIGN §11.4.
/// The pulse pauses when:
/// - the app is backgrounded (`AppLifecycleState.paused` / `.inactive` /
///   `.hidden` / `.detached`), per §11.4
/// - reduced-motion is requested via `MediaQuery.disableAnimations`, per §11.7
class StatusRow extends StatefulWidget {
  /// The device whose status this row reflects.
  final Device device;

  /// Map of `serial → user-supplied override name`. Forwarded to
  /// [displayNameFor] for §4.4 resolution.
  final Map<String, String> nameOverrides;

  const StatusRow({
    super.key,
    required this.device,
    this.nameOverrides = const {},
  });

  @override
  State<StatusRow> createState() => _StatusRowState();
}

class _StatusRowState extends State<StatusRow>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.of(context).disableAnimations;
    _syncAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncAnimation();
    } else {
      _controller.stop();
    }
  }

  void _syncAnimation() {
    if (_reducedMotion) {
      _controller.stop();
      _controller.value = 1.0; // hold at full brightness
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = deriveStatus(widget.device);
    final name = displayNameFor(widget.device, widget.nameOverrides);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _PulsingDot(color: status.dotColor, controller: _controller),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status.label,
                style: EmberTypography.labelSmall(
                  color: EmberColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: EmberTypography.bodyMedium(
                  color: EmberColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatelessWidget {
  final Color color;
  final AnimationController controller;

  const _PulsingDot({required this.color, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Glow strength oscillates 0 → 1 → 0 across the controller cycle.
        // Curves.easeInOut keeps the pulse soft at the extremes per §11.4.
        final t = Curves.easeInOut.transform(controller.value);
        final glowAlpha = 0.30 + 0.50 * t; // 0.30 .. 0.80
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: glowAlpha),
                blurRadius: 8 + 4 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}
