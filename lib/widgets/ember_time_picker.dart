import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Custom Ember-themed time picker per `docs/DESIGN.md` §13.6.
///
/// The PRD asked for a platform-native time wheel; DESIGN overrides that with
/// a custom picker that matches the Ember palette on both platforms. We use a
/// pair of `ListWheelScrollView` columns (hours / minutes) — minute resolution
/// only, even though NLE accepts seconds-resolution `time`s, because a
/// per-second UI would be silly. The two wheels render Fraunces digits in
/// `EmberColors.textPrimary` with dimmed siblings via the built-in
/// magnification + dim of `ListWheelScrollView`.
///
/// `hour` is 0..23. The `use24Hour` flag toggles between a 24-cell hour wheel
/// (00..23) and a 12-cell wheel + AM/PM selector. Minute step is 5 by default
/// (configurable via [minuteStep]); arbitrary user-entered minutes are snapped
/// to the nearest step in the callback.
class EmberTimePicker extends StatefulWidget {
  final int initialHour;
  final int initialMinute;
  final bool use24Hour;
  final int minuteStep;
  final void Function(int hour, int minute) onChanged;

  const EmberTimePicker({
    super.key,
    required this.initialHour,
    required this.initialMinute,
    required this.onChanged,
    this.use24Hour = false,
    this.minuteStep = 5,
  }) : assert(minuteStep > 0 && minuteStep <= 30);

  /// Round [minute] to the nearest [step] (e.g. 5 → snap to 0/5/10/...).
  /// Wraps minute=60 back to 0 — callers should bump the hour accordingly.
  static int roundMinute(int minute, int step) {
    final snapped = ((minute + step / 2) ~/ step) * step;
    return snapped % 60;
  }

  @override
  State<EmberTimePicker> createState() => _EmberTimePickerState();
}

class _EmberTimePickerState extends State<EmberTimePicker> {
  late int _hour;
  late int _minute;
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minuteCtrl;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialHour.clamp(0, 23);
    _minute = EmberTimePicker.roundMinute(
      widget.initialMinute.clamp(0, 59),
      widget.minuteStep,
    );
    final hourIndex = widget.use24Hour ? _hour : _to12Index(_hour);
    _hourCtrl = FixedExtentScrollController(initialItem: hourIndex);
    _minuteCtrl = FixedExtentScrollController(
      initialItem: _minute ~/ widget.minuteStep,
    );
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  int _to12Index(int hour24) {
    final h = hour24 % 12;
    return h == 0 ? 11 : h - 1; // wheel shows 1..12; index 11 == 12
  }

  int _from12(int wheelIndex) {
    // wheelIndex 0..11 maps to 1..12 hour-of-half-day
    final hour12 = wheelIndex + 1;
    final isPm = _hour >= 12;
    if (hour12 == 12) {
      return isPm ? 12 : 0;
    }
    return isPm ? hour12 + 12 : hour12;
  }

  void _emit() => widget.onChanged(_hour, _minute);

  @override
  Widget build(BuildContext context) {
    final minuteCount = 60 ~/ widget.minuteStep;
    final hourCount = widget.use24Hour ? 24 : 12;

    return SizedBox(
      height: 180,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _wheel(
            controller: _hourCtrl,
            childCount: hourCount,
            label: (i) => widget.use24Hour
                ? i.toString().padLeft(2, '0')
                : (i + 1).toString(),
            onSelect: (i) {
              setState(() {
                _hour = widget.use24Hour ? i : _from12(i);
              });
              _emit();
            },
          ),
          const _Colon(),
          _wheel(
            controller: _minuteCtrl,
            childCount: minuteCount,
            label: (i) => (i * widget.minuteStep).toString().padLeft(2, '0'),
            onSelect: (i) {
              setState(() {
                _minute = i * widget.minuteStep;
              });
              _emit();
            },
          ),
          if (!widget.use24Hour) ...[
            const SizedBox(width: 12),
            _AmPmToggle(
              isPm: _hour >= 12,
              onChanged: (pm) {
                setState(() {
                  if (pm && _hour < 12) {
                    _hour += 12;
                  } else if (!pm && _hour >= 12) {
                    _hour -= 12;
                  }
                });
                _emit();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int childCount,
    required String Function(int index) label,
    required ValueChanged<int> onSelect,
  }) {
    return SizedBox(
      width: 72,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 44,
        physics: const FixedExtentScrollPhysics(),
        perspective: 0.003,
        diameterRatio: 1.6,
        onSelectedItemChanged: onSelect,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: childCount,
          builder: (context, index) {
            return Center(
              child: Text(
                label(index),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: EmberColors.textPrimary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Colon extends StatelessWidget {
  const _Colon();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        ':',
        style: Theme.of(
          context,
        ).textTheme.headlineLarge?.copyWith(color: EmberColors.textPrimary),
      ),
    );
  }
}

class _AmPmToggle extends StatelessWidget {
  final bool isPm;
  final ValueChanged<bool> onChanged;

  const _AmPmToggle({required this.isPm, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill(
          context,
          label: 'AM',
          selected: !isPm,
          onTap: () => onChanged(false),
        ),
        const SizedBox(height: 6),
        _pill(
          context,
          label: 'PM',
          selected: isPm,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }

  Widget _pill(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? EmberColors.textPrimary.withValues(alpha: 0.18)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? EmberColors.textPrimary
                  : EmberColors.textTertiary,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected
                  ? EmberColors.textPrimary
                  : EmberColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
