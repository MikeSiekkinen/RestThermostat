import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../services/nle_error.dart';
import '../state/auth_failure_coordinator.dart';
import '../state/providers.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';
import 'fan_widget.dart';

/// Default fan-on duration when the user taps (rather than long-pressing for a
/// custom value): 1 hour per `docs/DESIGN.md` §9.3.
const _defaultFanOnDuration = Duration(hours: 1);

/// Duration choices for the long-press bottom sheet, per §9.3.
const _fanDurationChoices = [
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 4),
  Duration(hours: 8),
];

/// Stateful Riverpod consumer wrapping [FanWidget] with the interactive
/// write-path per `docs/DESIGN.md` §9.3.
///
/// Behavior:
/// - **Tap when auto** → light haptic + optimistic `On (1h)` + POST `set_fan`
///   value `3600` + `DeviceStateSource.refresh()`.
/// - **Tap when on** → light haptic + optimistic `auto` + POST `set_fan` value
///   `"auto"` + refresh.
/// - **Long-press** → medium haptic + bottom sheet of duration choices; choice
///   triggers the same optimistic + POST + refresh flow.
///
/// Optimistic state synthesizes `fan_timer_timeout = now + duration` locally
/// so the countdown is visible immediately. When the next snapshot arrives
/// with `fan_timer_active` matching the optimistic state, the override clears
/// and [FanWidget]'s built-in 1Hz `Timer.periodic` keeps the label fresh from
/// then on.
class InteractiveFanWidget extends ConsumerStatefulWidget {
  final Device device;

  /// Clock injection so the synthesized timeout uses the same `now()` as
  /// [FanWidget]'s countdown.
  final DateTime Function() now;

  /// Show-bottom-sheet override for tests — defaults to [showModalBottomSheet].
  /// Returns the chosen duration in seconds, or `null` if dismissed.
  final Future<int?> Function(BuildContext)? showDurationSheet;

  const InteractiveFanWidget({
    super.key,
    required this.device,
    this.now = DateTime.now,
    this.showDurationSheet,
  });

  @override
  ConsumerState<InteractiveFanWidget> createState() =>
      _InteractiveFanWidgetState();
}

class _InteractiveFanWidgetState extends ConsumerState<InteractiveFanWidget> {
  /// Optimistic override of `fan_timer_active`. `null` means "trust device".
  bool? _optimisticActive;

  /// Optimistic override of `fan_timer_timeout` (Unix epoch seconds, UTC).
  /// Only meaningful when [_optimisticActive] is true.
  int? _optimisticTimeoutEpochSec;

  bool get _displayedActive =>
      _optimisticActive ?? widget.device.fanTimerActive;

  int get _displayedTimeout {
    if (_optimisticActive == true && _optimisticTimeoutEpochSec != null) {
      return _optimisticTimeoutEpochSec!;
    }
    return widget.device.fanTimerTimeout;
  }

  @override
  void didUpdateWidget(covariant InteractiveFanWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Snapshot reconciliation: once the server agrees with the optimistic
    // `fan_timer_active`, drop the override. The server's actual
    // `fan_timer_timeout` then drives the countdown — usually within a few
    // seconds of the synthesized value.
    if (_optimisticActive != null &&
        widget.device.fanTimerActive == _optimisticActive) {
      _optimisticActive = null;
      _optimisticTimeoutEpochSec = null;
    }
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    if (_displayedActive) {
      await _setAuto();
    } else {
      await _setOn(_defaultFanOnDuration);
    }
  }

  Future<void> _onLongPress() async {
    HapticFeedback.mediumImpact();
    final show = widget.showDurationSheet ?? _defaultShowSheet;
    final chosenSeconds = await show(context);
    if (chosenSeconds == null || !mounted) return;
    await _setOn(Duration(seconds: chosenSeconds));
  }

  Future<int?> _defaultShowSheet(BuildContext context) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _FanDurationSheet(),
    );
  }

  Future<void> _setOn(Duration duration) async {
    final newTimeout =
        widget.now().toUtc().millisecondsSinceEpoch ~/ 1000 +
        duration.inSeconds;
    setState(() {
      _optimisticActive = true;
      _optimisticTimeoutEpochSec = newTimeout;
    });
    await _post(value: duration.inSeconds, onErrorRevert: true);
  }

  Future<void> _setAuto() async {
    setState(() {
      _optimisticActive = false;
      _optimisticTimeoutEpochSec = null;
    });
    await _post(value: 'auto', onErrorRevert: true);
  }

  Future<void> _post({
    required Object value,
    required bool onErrorRevert,
  }) async {
    final client = ref.read(nleApiClientProvider);
    try {
      await client.sendCommand(
        serial: widget.device.serial,
        command: 'set_fan',
        value: value,
      );
    } on NleAuthError catch (_) {
      if (!mounted) return;
      ref.read(authFailureCoordinatorProvider).fire();
      if (onErrorRevert) _revertOptimistic();
      return;
    } on NleError catch (e) {
      if (!mounted) return;
      if (onErrorRevert) _revertOptimistic();
      _showSnack(_messageFor(e));
      return;
    } catch (_) {
      if (!mounted) return;
      if (onErrorRevert) _revertOptimistic();
      _showSnack('Couldn\'t change fan');
      return;
    }
    if (!mounted) return;
    ref.read(deviceStateSourceProvider).refresh();
  }

  void _revertOptimistic() {
    setState(() {
      _optimisticActive = null;
      _optimisticTimeoutEpochSec = null;
    });
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageFor(NleError e) {
    if (e.serverMessage != null && e.serverMessage!.isNotEmpty) {
      return e.serverMessage!;
    }
    return switch (e) {
      NleClientError() => 'Server rejected fan command',
      _ => "Couldn't change fan",
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.device.capabilities.hasFan) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      onLongPress: _onLongPress,
      child: FanWidget(
        hasFan: widget.device.capabilities.hasFan,
        fanTimerActive: _displayedActive,
        fanTimerTimeout: _displayedTimeout,
        now: widget.now,
      ),
    );
  }
}

/// Ember-themed bottom sheet listing the §9.3 fan-on duration choices.
///
/// Pops the selected duration in seconds back to the caller. Dismissed by
/// tapping outside or by dragging down — both return `null`.
class _FanDurationSheet extends StatelessWidget {
  const _FanDurationSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D12),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: EmberColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
              alignment: Alignment.center,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('RUN FAN FOR', style: EmberTypography.labelSmall()),
            ),
            for (final choice in _fanDurationChoices)
              _DurationTile(duration: choice),
          ],
        ),
      ),
    );
  }
}

class _DurationTile extends StatelessWidget {
  final Duration duration;

  const _DurationTile({required this.duration});

  String get _label {
    if (duration.inHours >= 1) {
      final h = duration.inHours;
      return h == 1 ? '1 HOUR' : '$h HOURS';
    }
    return '${duration.inMinutes} MINUTES';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(duration.inSeconds),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Text(
          _label,
          style: EmberTypography.labelSmall(color: EmberColors.textPrimary),
        ),
      ),
    );
  }
}
