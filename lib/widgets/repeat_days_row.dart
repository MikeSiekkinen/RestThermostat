import 'package:flutter/material.dart';

import '../screens/schedule/day_index.dart';
import '../theme/colors.dart';

/// Seven toggleable day panels for the Edit Event "new" mode, per
/// `docs/DESIGN.md` §6.4. Order follows the user's locale (Mon-first vs
/// Sun-first); internal indexing stays Monday=0. Each panel shows the weekday
/// abbreviation over the day-of-month of that weekday's next occurrence, e.g.
///
///     Sat
///     18
///
/// At least one day must remain selected — tapping the only selected day is a
/// no-op (the widget short-circuits before calling [onChanged]).
class RepeatDaysRow extends StatelessWidget {
  /// Set of internal day indexes (Mon=0..Sun=6) currently selected.
  final Set<int> selectedDays;
  final ValueChanged<Set<int>> onChanged;
  final Locale locale;

  /// Numeral face for the date numbers, merged onto their text style.
  final TextStyle? numeralStyle;

  const RepeatDaysRow({
    super.key,
    required this.selectedDays,
    required this.onChanged,
    required this.locale,
    this.numeralStyle,
  });

  @override
  Widget build(BuildContext context) {
    final order = localeDayOrder(locale);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // dayIndex Mon=0..Sun=6; DateTime.weekday Mon=1..Sun=7. Dart % is
    // non-negative → days until the next occurrence (0 = today).
    int dateNumFor(int dayIndex) =>
        today.add(Duration(days: (dayIndex + 1 - now.weekday) % 7)).day;

    return Row(
      children: [
        for (final dayIndex in order)
          _DayPanel(
            dow: fullDayNames[dayIndex].substring(0, 3),
            dateNum: dateNumFor(dayIndex),
            dayIndex: dayIndex,
            fullName: fullDayNames[dayIndex],
            selected: selectedDays.contains(dayIndex),
            numeralStyle: numeralStyle,
            onTap: () => _toggle(dayIndex),
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

class _DayPanel extends StatelessWidget {
  final String dow;
  final int dateNum;
  final int dayIndex;
  final String fullName;
  final bool selected;
  final TextStyle? numeralStyle;
  final VoidCallback onTap;

  const _DayPanel({
    required this.dow,
    required this.dateNum,
    required this.dayIndex,
    required this.fullName,
    required this.selected,
    required this.numeralStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? EmberColors.textPrimary : EmberColors.textSecondary;
    final bg = selected
        ? EmberColors.textPrimary.withValues(alpha: 0.18)
        : Colors.transparent;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Semantics(
          button: true,
          selected: selected,
          label: fullName,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              key: ValueKey('repeat-day-$dayIndex'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? EmberColors.textPrimary
                      : EmberColors.textTertiary,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dow,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dateNum',
                    style:
                        (Theme.of(context).textTheme.titleMedium ??
                                const TextStyle())
                            .copyWith(color: fg, fontWeight: FontWeight.w600)
                            .merge(numeralStyle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
