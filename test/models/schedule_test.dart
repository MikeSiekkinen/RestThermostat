import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/schedule.dart';

void main() {
  group('Schedule.fromJson', () {
    late Map<String, dynamic> fixture;

    setUp(() {
      final raw = File('test/fixtures/schedule_one.json').readAsStringSync();
      fixture = jsonDecode(raw) as Map<String, dynamic>;
    });

    test('parses top-level metadata', () {
      final schedule = Schedule.fromJson(fixture);
      expect(schedule.version, 2);
      expect(schedule.name, 'Weekday/Weekend');
      expect(schedule.mode, 'HEAT');
    });

    test('parses all seven days, including the empty Friday', () {
      final schedule = Schedule.fromJson(fixture);
      for (var i = 0; i < 7; i++) {
        expect(
          schedule.events.containsKey(i),
          isTrue,
          reason: 'day $i missing',
        );
      }
      expect(schedule.eventsForDay(4), isEmpty);
      expect(schedule.eventsForDay(0), hasLength(4));
    });

    test('parses time-of-day from seconds-since-midnight', () {
      final schedule = Schedule.fromJson(fixture);
      final mondayWake = schedule.eventsForDay(0).first;
      expect(mondayWake.hour, 6);
      expect(mondayWake.minute, 0);
    });

    test('sorts events within a day by time', () {
      final schedule = Schedule.fromJson(fixture);
      final monday = schedule.eventsForDay(0);
      for (var i = 1; i < monday.length; i++) {
        expect(
          monday[i].minutesOfDay,
          greaterThanOrEqualTo(monday[i - 1].minutesOfDay),
        );
      }
    });

    test('parses HEAT event temp', () {
      final schedule = Schedule.fromJson(fixture);
      final event = schedule.eventsForDay(0).first;
      expect(event.type, 'HEAT');
      expect(event.targetTemp, 20.0);
      expect(event.targetTempHigh, isNull);
      expect(event.targetTempLow, isNull);
    });

    test('parses RANGE event temp-min/temp-max', () {
      final schedule = Schedule.fromJson(fixture);
      final wednesdayWake = schedule.eventsForDay(3).first;
      expect(wednesdayWake.type, 'RANGE');
      expect(wednesdayWake.targetTemp, isNull);
      expect(wednesdayWake.targetTempLow, 18.0);
      expect(wednesdayWake.targetTempHigh, 23.0);
    });

    test('parses COOL event temp', () {
      final schedule = Schedule.fromJson(fixture);
      final wednesdayEvening = schedule.eventsForDay(3).last;
      expect(wednesdayEvening.type, 'COOL');
      expect(wednesdayEvening.targetTemp, 24.0);
    });

    test('uppercases type even if server lowercases', () {
      final json = {
        'days': {
          '0': [
            {'time': 0, 'type': 'heat', 'temp': 20.0},
          ],
        },
      };
      final schedule = Schedule.fromJson(json);
      expect(schedule.eventsForDay(0).first.type, 'HEAT');
    });

    test('handles list-of-lists day form', () {
      final json = {
        'mode': 'HEAT',
        'days': [
          [
            {'time': 0, 'type': 'HEAT', 'temp': 20.0},
          ],
          [],
          [],
          [],
          [],
          [],
          [],
        ],
      };
      final schedule = Schedule.fromJson(json);
      expect(schedule.eventsForDay(0), hasLength(1));
      expect(schedule.eventsForDay(1), isEmpty);
    });

    test('handles missing days map', () {
      final schedule = Schedule.fromJson({'version': 1, 'mode': 'HEAT'});
      // No day data — all queries return empty lists.
      for (var i = 0; i < 7; i++) {
        expect(schedule.eventsForDay(i), isEmpty);
      }
    });
  });

  group('ScheduleEvent', () {
    test('timeSeconds converts hour+minute to seconds-since-midnight', () {
      const e = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      expect(e.timeSeconds, 21600);
    });

    test('toJson round-trips HEAT events', () {
      const e = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 30,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      expect(e.toJson(), {'time': 23400, 'type': 'HEAT', 'temp': 20.0});
    });

    test('toJson emits temp-min / temp-max for RANGE events', () {
      const e = ScheduleEvent(
        dayIndex: 3,
        hour: 6,
        minute: 0,
        type: 'RANGE',
        targetTempLow: 18.0,
        targetTempHigh: 23.0,
      );
      expect(e.toJson(), {
        'time': 21600,
        'type': 'RANGE',
        'temp-min': 18.0,
        'temp-max': 23.0,
      });
    });

    test('== compares by all fields', () {
      const a = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      const b = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      const c = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'HEAT',
        targetTemp: 21.0,
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('copyWith mutates only the named fields', () {
      const e = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      final updated = e.copyWith(hour: 7, targetTemp: 22.0);
      expect(updated.hour, 7);
      expect(updated.targetTemp, 22.0);
      expect(updated.dayIndex, 0);
      expect(updated.type, 'HEAT');
    });

    test('copyWith with nullify* clears nullable fields', () {
      const e = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'RANGE',
        targetTempLow: 18.0,
        targetTempHigh: 23.0,
      );
      final cleared = e.copyWith(
        nullifyTargetTempLow: true,
        nullifyTargetTempHigh: true,
      );
      expect(cleared.targetTempLow, isNull);
      expect(cleared.targetTempHigh, isNull);
    });
  });

  group('Schedule mutation helpers', () {
    Schedule emptyWeek() => const Schedule(
      events: {0: [], 1: [], 2: [], 3: [], 4: [], 5: [], 6: []},
      mode: 'HEAT',
    );

    test('addEvent appends and keeps the day sorted by time', () {
      var schedule = emptyWeek();
      const noon = ScheduleEvent(
        dayIndex: 0,
        hour: 12,
        minute: 0,
        type: 'HEAT',
        targetTemp: 21.0,
      );
      const dawn = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      schedule = schedule.addEvent(noon).addEvent(dawn);
      expect(schedule.eventsForDay(0), [dawn, noon]);
    });

    test('replaceEvent swaps within a day and re-sorts', () {
      var schedule = emptyWeek();
      const original = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      schedule = schedule.addEvent(original);
      final shifted = original.copyWith(hour: 8, targetTemp: 22.0);
      schedule = schedule.replaceEvent(original, shifted);
      expect(schedule.eventsForDay(0), [shifted]);
    });

    test('replaceEvent is a no-op when the original isn\'t present', () {
      final schedule = emptyWeek();
      const missing = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      final after = schedule.replaceEvent(missing, missing.copyWith(hour: 7));
      expect(after.eventsForDay(0), isEmpty);
    });

    test('removeEvent drops the matching entry', () {
      var schedule = emptyWeek();
      const a = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      const b = ScheduleEvent(
        dayIndex: 0,
        hour: 12,
        minute: 0,
        type: 'HEAT',
        targetTemp: 21.0,
      );
      schedule = schedule.addEvent(a).addEvent(b);
      schedule = schedule.removeEvent(a);
      expect(schedule.eventsForDay(0), [b]);
    });

    test('toJson emits all seven days even if empty', () {
      final schedule = emptyWeek();
      final json = schedule.toJson();
      expect(json['days'], isA<Map<String, dynamic>>());
      final days = json['days'] as Map<String, dynamic>;
      for (var i = 0; i < 7; i++) {
        expect(days.containsKey('$i'), isTrue, reason: 'day $i missing');
      }
    });

    test('toJson preserves version, name, and mode', () {
      const schedule = Schedule(
        events: {0: [], 1: [], 2: [], 3: [], 4: [], 5: [], 6: []},
        version: 2,
        name: 'Weekday/Weekend',
        mode: 'HEAT',
      );
      final json = schedule.toJson();
      expect(json['version'], 2);
      expect(json['name'], 'Weekday/Weekend');
      expect(json['mode'], 'HEAT');
    });
  });
}
