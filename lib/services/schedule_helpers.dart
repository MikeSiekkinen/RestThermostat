import '../models/schedule.dart';

/// Find the schedule event that is **currently in effect** at [now] per
/// `docs/DESIGN.md` §9.5. Returns `null` if no event has been crossed in
/// the past seven days (i.e., the schedule is effectively empty).
///
/// "Currently in effect" = the most recent setpoint event before-or-at
/// `now`'s weekday + time-of-day, walking backwards across days if today
/// has no earlier event. The setpoint that event configures is what the
/// thermostat *should* be holding right now — comparing it to the device's
/// `target_temperature` is how the Details screen decides between
/// "Scheduled" and "Manual" sources.
///
/// Weekday indexing matches the schedule wire format: 0=Mon..6=Sun (NOT
/// JavaScript-standard). [DateTime.weekday] in Dart is 1=Mon..7=Sun, so
/// we subtract one.
ScheduleEvent? findActiveEvent(Schedule schedule, DateTime now) {
  final localNow = now.toLocal();
  final todayIndex = localNow.weekday - 1; // 0=Mon..6=Sun
  final nowSeconds =
      localNow.hour * 3600 + localNow.minute * 60 + localNow.second;

  // Walk back across the week, up to 7 days, checking each day's events.
  for (var offset = 0; offset < 7; offset++) {
    final dayIndex = (todayIndex - offset + 7) % 7;
    final dayEvents = schedule.eventsForDay(dayIndex);
    if (dayEvents.isEmpty) continue;

    // For "today" (offset 0) we want events at-or-before `nowSeconds`.
    // For any prior day we want any event — the LAST one of the day, which
    // is the most-recent one before midnight (and thus before `now`).
    final eligible = offset == 0
        ? dayEvents
              .where((e) => e.hour * 3600 + e.minute * 60 <= nowSeconds)
              .toList()
        : dayEvents.toList();

    if (eligible.isEmpty) continue;

    // Pick the event with the largest time-of-day. Events within a day
    // aren't guaranteed sorted by the wire format, so we sort defensively.
    eligible.sort(
      (a, b) =>
          (a.hour * 3600 + a.minute * 60) - (b.hour * 3600 + b.minute * 60),
    );
    return eligible.last;
  }
  return null;
}
