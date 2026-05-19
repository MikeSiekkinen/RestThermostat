import 'package:flutter/material.dart';

import '../screens/schedule/day_index.dart';
import '../theme/colors.dart';

/// Seven toggleable day circles for the Edit Event "new" mode, per
/// `docs/DESIGN.md` §6.4. Order follows the user's locale (Mon-first vs
/// Sun-first); internal indexing stays Monday=0.
///
/// At least one day must remain selected — tapping the only selected day is a
/// no-op (the widget short-circuits before calling [onChanged]).
class RepeatDaysRow extends StatelessWidget {
  /// Set of internal day indexes (Mon=0..Sun=6) currently selected.
  final Set<int> selectedDays;
  final ValueChanged<Set<int>> onChanged;
  final Locale locale;

  const RepeatDaysRow({
    super.key,
    required this.selectedDays,
    required this.onChanged,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final order = localeDayOrder(locale);
    final labels = displayDayLabels(locale);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < order.length; i++)
          _DayCircle(
            label: labels[i],
            dayIndex: order[i],
            fullName: fullDayNames[order[i]],
            selected: selectedDays.contains(order[i]),
            onTap: () => _toggle(order[i]),
          ),
      ],
    );
  }

  void _toggle(int dayIndex) {
    final next = Set<int>.from(selectedDays);
    if (next.contains(dayIndex)) {
      if (next.length == 1) return; // enforce at-least-one
      next.remove(dayIndex);
    } else {
      next.add(dayIndex);
    }
    onChanged(next);
  }
}

class _DayCircle extends StatelessWidget {
  final String label;
  final int dayIndex;
  final String fullName;
  final bool selected;
  final VoidCallback onTap;

  const _DayCircle({
    required this.label,
    required this.dayIndex,
    required this.fullName,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? EmberColors.textPrimary
        : EmberColors.textSecondary;
    final bg = selected
        ? EmberColors.textPrimary.withValues(alpha: 0.18)
        : Colors.transparent;
    return Semantics(
      button: true,
      selected: selected,
      label: fullName,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          key: ValueKey('repeat-day-$dayIndex'),
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? EmberColors.textPrimary
                  : EmberColors.textTertiary,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}
