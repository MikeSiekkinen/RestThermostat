import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/schedule.dart';
import 'package:rest_thermostat/services/schedule_helpers.dart';

ScheduleEvent _ev({
  required int day,
  required int hour,
  int minute = 0,
  double temp = 20.0,
}) {
  return ScheduleEvent(
    dayIndex: day,
    hour: hour,
    minute: minute,
    type: 'HEAT',
    targetTemp: temp,
  );
}

/// Wednesday 2026-05-13 12:00 local. weekday=3 (Wed) → todayIndex=2.
final DateTime _wedNoon = DateTime(2026, 5, 13, 12, 0, 0);

void main() {
  group('findActiveEvent — same-day path', () {
    test('returns the most recent event before now in today\'s list', () {
      final schedule = Schedule(
        events: {
          2: [
            _ev(day: 2, hour: 6, temp: 20),
            _ev(day: 2, hour: 8, temp: 19),
            _ev(day: 2, hour: 17, temp: 21), // future, ignored
          ],
        },
      );
      final event = findActiveEvent(schedule, _wedNoon);
      expect(event?.hour, 8);
      expect(event?.targetTemp, 19);
    });

    test('exact-match at-or-before counts as active', () {
      final schedule = Schedule(
        events: {
          2: [_ev(day: 2, hour: 12, minute: 0, temp: 22)],
        },
      );
      final event = findActiveEvent(schedule, _wedNoon);
      expect(event?.targetTemp, 22);
    });

    test('returns null when all today events are in the future and no '
        'earlier-day events exist', () {
      final schedule = Schedule(
        events: {
          2: [_ev(day: 2, hour: 17, temp: 21)],
        },
      );
      final event = findActiveEvent(schedule, _wedNoon);
      expect(event, isNull);
    });
  });

  group('findActiveEvent — walk-back path', () {
    test('falls back to yesterday\'s last event when today has no earlier '
        'events', () {
      final schedule = Schedule(
        events: {
          1: [_ev(day: 1, hour: 22, temp: 18)], // Tuesday 22:00
          2: [_ev(day: 2, hour: 17, temp: 21)], // Wed future
        },
      );
      final event = findActiveEvent(schedule, _wedNoon);
      expect(event?.dayIndex, 1);
      expect(event?.targetTemp, 18);
    });

    test('skips empty days', () {
      final schedule = Schedule(
        events: {
          0: [_ev(day: 0, hour: 20, temp: 17)], // Monday 20:00
          1: const [], // Tuesday empty
          2: const [], // Wednesday empty
        },
      );
      final event = findActiveEvent(schedule, _wedNoon);
      expect(event?.dayIndex, 0);
      expect(event?.targetTemp, 17);
    });

    test('wraps across the week boundary (Sun → Mon)', () {
      // Monday 2026-05-11 09:00 → todayIndex=0; only Sunday has events.
      final monMorning = DateTime(2026, 5, 11, 9, 0);
      final schedule = Schedule(
        events: {
          6: [_ev(day: 6, hour: 23, temp: 16)], // Sunday 23:00 from prev week
        },
      );
      final event = findActiveEvent(schedule, monMorning);
      expect(event?.dayIndex, 6);
      expect(event?.targetTemp, 16);
    });
  });

  group('findActiveEvent — empty', () {
    test('returns null on an entirely empty schedule', () {
      final event = findActiveEvent(const Schedule(events: {}), _wedNoon);
      expect(event, isNull);
    });
  });
}
