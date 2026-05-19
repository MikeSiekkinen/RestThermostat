import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Fan-state widget per `docs/DESIGN.md` §10.2 + `docs/PRD.md` §4.2.
///
/// IP-safety note (DESIGN §1): this widget intentionally renders **concentric
/// pulsing rings**, not three curved blades. The blade design from PRD §4.5
/// would read as Nest-derivative and is forbidden by the legal posture.
///
/// Visual contract:
/// - 52dp circular container with three thin silver concentric rings.
/// - When the fan timer is active: rings pulse outward in a 1.6s linear
///   repeat, staggered by one-third of the cycle so they appear to ripple.
///   Each ring scales from the innermost radius to the outermost while its
///   alpha fades to zero — an outward-radiating shimmer.
/// - When the fan is auto (no timer): rings render at a dimmed neutral
///   gradient, no animation.
/// - Label below the circle: `FAN AUTO` (auto) or `FAN ON • M:SS` (active
///   timer) in JetBrains Mono uppercase.
///
/// Visibility: caller is expected to render the widget only when
/// `device.capabilities.has_fan` is true — but a defensive `has_fan` check
/// inside [build] returns an empty `SizedBox.shrink()` so the row collapses
/// cleanly even if a caller forgets.
///
/// Animation lifecycle: pulse controller pauses on background lifecycle
/// transitions (§11.4) and when `MediaQuery.disableAnimations` is set (§11.7).
class FanWidget extends StatefulWidget {
  /// Whether the device supports a fan (`capabilities.has_fan`). When false
  /// the widget collapses to a zero-size [SizedBox.shrink], so callers can
  /// place it unconditionally and the row collapses cleanly.
  final bool hasFan;

  /// Whether a fan timer is currently active.
  final bool fanTimerActive;

  /// Unix epoch second (UTC) at which the active fan timer expires. Only
  /// meaningful when [fanTimerActive] is true. Verified semantics: this is
  /// a fixed deadline, not a seconds-remaining counter (see
  /// [[nle-api-reference]] memory).
  final int fanTimerTimeout;

  /// Clock injection for tests. Production calls [DateTime.now].
  final DateTime Function() now;

  /// Optional fixed diameter. Defaults to the §10.2 spec of 52dp.
  final double diameter;

  const FanWidget({
    super.key,
    required this.hasFan,
    required this.fanTimerActive,
    required this.fanTimerTimeout,
    this.now = DateTime.now,
    this.diameter = 52.0,
  });

  @override
  State<FanWidget> createState() => _FanWidgetState();

  /// Visible-for-testing: derives the countdown remaining at [now] for a
  /// `fan_timer_timeout` value interpreted as a Unix epoch second.
  @visibleForTesting
  static Duration remainingFor(int timeoutSeconds, DateTime now) =>
      _remainingFor(timeoutSeconds, now);

  /// Visible-for-testing: formats a remaining duration as `M:SS`.
  @visibleForTesting
  static String formatCountdown(Duration d) => _formatCountdown(d);
}

class _FanWidgetState extends State<FanWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseController;
  Timer? _countdownTicker;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    WidgetsBinding.instance.addObserver(this);
    _maybeStartCountdownTicker();
  }

  @override
  void didUpdateWidget(covariant FanWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fanTimerActive != widget.fanTimerActive) {
      _syncPulse();
      _maybeStartCountdownTicker();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.of(context).disableAnimations;
    _syncPulse();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPulse();
      _maybeStartCountdownTicker();
    } else {
      _pulseController.stop();
      _countdownTicker?.cancel();
      _countdownTicker = null;
    }
  }

  void _syncPulse() {
    final shouldRun = widget.fanTimerActive && !_reducedMotion;
    if (shouldRun) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat();
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  void _maybeStartCountdownTicker() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
    if (!widget.fanTimerActive) return;
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTicker?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasFan) return const SizedBox.shrink();

    final active = widget.fanTimerActive;
    final remaining = active
        ? _remainingFor(widget.fanTimerTimeout, widget.now())
        : Duration.zero;
    final l = AppLocalizations.of(context);
    final countdownStr = _formatCountdown(remaining);
    final label = active ? l.fanLabelOn(countdownStr) : l.fanLabelAuto;

    // Screen-reader announcement: describe state + tap affordance. Includes
    // the countdown when the timer is active so blind users hear the same
    // information that's painted onto the label. The `button: true` role
    // signals tap behavior to TalkBack/VoiceOver.
    final semanticLabel = active
        ? l.fanSemanticOn(countdownStr)
        : l.fanSemanticAuto;

    return Semantics(
      label: semanticLabel,
      button: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return SizedBox(
                  width: widget.diameter,
                  height: widget.diameter,
                  child: CustomPaint(
                    painter: _FanRingsPainter(
                      phase: _pulseController.value,
                      active: active,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(label, style: EmberTypography.labelSmall()),
          ],
        ),
      ),
    );
  }
}

Duration _remainingFor(int timeoutSeconds, DateTime now) {
  final timeout = DateTime.fromMillisecondsSinceEpoch(
    timeoutSeconds * 1000,
    isUtc: true,
  );
  final diff = timeout.difference(now);
  return diff.isNegative ? Duration.zero : diff;
}

String _formatCountdown(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds - m * 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Paints three concentric silver rings. Active mode ripples them outward
/// with staggered phases; idle mode draws them static at low opacity.
class _FanRingsPainter extends CustomPainter {
  /// Master pulse phase in `[0, 1)`. Each of the three rings reads a phase
  /// shifted by `i / 3` so they cascade outward.
  final double phase;
  final bool active;

  _FanRingsPainter({required this.phase, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = math.min(size.width, size.height) / 2 - 1;
    final innerR = outerR * 0.35;

    if (!active) {
      // Static three-ring layout. Even spacing between innerR and outerR.
      for (var i = 0; i < 3; i++) {
        final t = i / 2; // 0, 0.5, 1
        final r = innerR + (outerR - innerR) * t;
        canvas.drawCircle(center, r, _ringPaint(0.35));
      }
      return;
    }

    // Active: each ring's local phase ripples 0 → 1; we draw the ring at a
    // radius interpolated from inner→outer, with alpha decaying as it grows.
    for (var i = 0; i < 3; i++) {
      final local = (phase + i / 3) % 1.0;
      final r = innerR + (outerR - innerR) * local;
      // Fade from 1.0 → 0.0 across the local phase; keep a small floor so
      // the leading edge of the next ring is visible.
      final alpha = (1.0 - local).clamp(0.15, 1.0);
      canvas.drawCircle(center, r, _ringPaint(alpha));
    }
  }

  Paint _ringPaint(double alpha) {
    // Silver gradient at the requested alpha. Linear is fine for thin rings;
    // the radial gradient would be visually indistinguishable at this size.
    return Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
        colors: EmberColors.fanActiveGradient
            .map((c) => c.withValues(alpha: alpha))
            .toList(growable: false),
      ).createShader(const Rect.fromLTWH(0, 0, 52, 52));
  }

  @override
  bool shouldRepaint(covariant _FanRingsPainter old) =>
      old.phase != phase || old.active != active;
}
