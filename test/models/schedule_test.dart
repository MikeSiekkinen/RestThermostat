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
}
