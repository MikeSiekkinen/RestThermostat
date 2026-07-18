import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/schedule.dart';

void main() {
  group('Schedule.fromJson', () {
    late Map<String, dynamic> fixture;

    setUp(() {
      // schedule_one.json mirrors the live GET /api/schedule response —
      // a {serial, schedule, object_revision, object_timestamp} envelope.
      // The `schedule` field is the inner object that Schedule.fromJson eats.
      final raw = File('test/fixtures/schedule_one.json').readAsStringSync();
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      fixture = envelope['schedule'] as Map<String, dynamic>;
    });

    test('parses top-level metadata', () {
      final schedule = Schedule.fromJson(fixture);
      expect(schedule.version, 2);
      expect(schedule.name, 'Current Schedule');
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

    test('drops entry_type=continuation entries from the read shape', () {
      final json = {
        'ver': 2,
        'schedule_mode': 'HEAT',
        'days': {
          '0': {
            '0': {
              'type': 'HEAT',
              'time': 0,
              'temp': 16.5,
              'entry_type': 'continuation',
              'touched_by': 1,
              'touched_at': 1748928957,
              'touched_tzo': -18000,
            },
            '1': {
              'type': 'HEAT',
              'time': 28800,
              'temp': 20.0,
              'entry_type': 'setpoint',
            },
          },
        },
      };
      final schedule = Schedule.fromJson(json);
      // The continuation is dropped; only the user-set setpoint survives.
      expect(schedule.eventsForDay(0), hasLength(1));
      expect(schedule.eventsForDay(0).first.targetTemp, 20.0);
      expect(schedule.eventsForDay(0).first.hour, 8);
    });

    test('parses the live read shape (days[N] as map keyed by index)', () {
      final json = {
        'ver': 2,
        'schedule_mode': 'COOL',
        'days': {
          '0': {
            '0': {
              'type': 'HEAT',
              'time': 21600,
              'temp': 20.0,
              'entry_type': 'setpoint',
            },
            '1': {
              'type': 'HEAT',
              'time': 28800,
              'temp': 17.0,
              'entry_type': 'setpoint',
            },
          },
        },
      };
      final schedule = Schedule.fromJson(json);
      expect(schedule.eventsForDay(0), hasLength(2));
      expect(schedule.eventsForDay(0).first.hour, 6);
      expect(schedule.eventsForDay(0).last.hour, 8);
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
      expect(e.toJson(), {
        'time': 23400,
        'type': 'HEAT',
        'entry_type': 'setpoint',
        'temp': 20.0,
      });
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
        'entry_type': 'setpoint',
        'temp-min': 18.0,
        'temp-max': 23.0,
      });
    });

    test(
      'conformedTo returns the event unchanged when types already agree',
      () {
        const e = ScheduleEvent(
          dayIndex: 0,
          hour: 6,
          minute: 0,
          type: 'HEAT',
          targetTemp: 20.0,
        );
        expect(e.conformedTo('HEAT'), same(e));
      },
    );

    test('conformedTo carries the single setpoint across HEAT/COOL', () {
      const e = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      final coerced = e.conformedTo('COOL');
      expect(coerced.type, 'COOL');
      expect(coerced.targetTemp, 20.0);
      expect(coerced.targetTempLow, isNull);
      expect(coerced.targetTempHigh, isNull);
    });

    test('conformedTo RANGE→HEAT keeps the low bound, RANGE→COOL the high', () {
      const e = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'RANGE',
        targetTempLow: 18.0,
        targetTempHigh: 23.0,
      );
      final heat = e.conformedTo('HEAT');
      expect(heat.type, 'HEAT');
      expect(heat.targetTemp, 18.0);
      expect(heat.targetTempLow, isNull);
      expect(heat.targetTempHigh, isNull);

      final cool = e.conformedTo('COOL');
      expect(cool.type, 'COOL');
      expect(cool.targetTemp, 23.0);
    });

    test('conformedTo falls back to the other bound when the preferred one '
        'is missing, and never emits a temp-less setpoint', () {
      // fromJson tolerates one-bound RANGE events (e.g. only temp-max), so
      // coercion must not strand a setpoint with no temperature at all —
      // the server rejects it, or worse, the device silently ignores the
      // whole bucket.
      const onlyHigh = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'RANGE',
        targetTempHigh: 24.0,
      );
      final heat = onlyHigh.conformedTo('HEAT');
      expect(heat.type, 'HEAT');
      expect(heat.targetTemp, 24.0, reason: 'falls back to the high bound');

      const onlyLow = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'RANGE',
        targetTempLow: 18.0,
      );
      final cool = onlyLow.conformedTo('COOL');
      expect(cool.type, 'COOL');
      expect(cool.targetTemp, 18.0, reason: 'falls back to the low bound');

      // Fully degenerate event (no temps at all) → editor defaults.
      const bare = ScheduleEvent(dayIndex: 0, hour: 6, minute: 0, type: 'COOL');
      expect(bare.conformedTo('HEAT').targetTemp, 20.0);
      const bareHeat = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'HEAT',
      );
      expect(bareHeat.conformedTo('COOL').targetTemp, 24.0);
    });

    test('conformedTo single→RANGE builds a ±1°C band around the setpoint', () {
      const e = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'COOL',
        targetTemp: 24.0,
      );
      final range = e.conformedTo('RANGE');
      expect(range.type, 'RANGE');
      expect(range.targetTemp, isNull);
      expect(range.targetTempLow, 23.0);
      expect(range.targetTempHigh, 25.0);
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

    // The write contract below was established by the Issue #93 live ablation
    // (2026-07-18): Gen 2 firmware silently ignores the whole bucket unless
    // days are MAPS keyed by string index, a top-level `name` is present, and
    // every event carries `entry_type: "setpoint"`. These tests assert on the
    // raw JSON (not round-trips) because the parser tolerantly accepts both
    // day shapes, so a regression to arrays would survive a round-trip test.

    test('toJson emits all seven days as empty maps even if empty', () {
      final schedule = emptyWeek();
      final json = schedule.toJson(scheduleMode: 'HEAT');
      expect(json['days'], isA<Map<String, dynamic>>());
      final days = json['days'] as Map<String, dynamic>;
      for (var i = 0; i < 7; i++) {
        expect(days['$i'], isA<Map<String, dynamic>>(), reason: 'day $i');
        expect(days['$i'], isEmpty, reason: 'day $i should be an empty map');
      }
    });

    test('toJson emits the exact top-level wire keys', () {
      const schedule = Schedule(
        events: {0: [], 1: [], 2: [], 3: [], 4: [], 5: [], 6: []},
        version: 2,
        name: 'Weekday/Weekend',
        mode: 'HEAT',
      );
      final json = schedule.toJson(scheduleMode: 'HEAT');
      expect(
        json.keys.toSet(),
        {'ver', 'schedule_mode', 'name', 'days'},
        reason:
            'exact top-level key set — the server silently accepts '
            'unknown/missing keys, so assert the full set',
      );
      expect(json['ver'], 2);
      expect(json['schedule_mode'], 'HEAT');
      expect(json['name'], 'Weekday/Weekend');
    });

    test('toJson wraps day events in maps keyed by string index, sorted by '
        'time', () {
      const dawn = ScheduleEvent(
        dayIndex: 5,
        hour: 6,
        minute: 0,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      const night = ScheduleEvent(
        dayIndex: 5,
        hour: 22,
        minute: 0,
        type: 'HEAT',
        targetTemp: 17.0,
      );
      // Build with events out of order to prove toJson emits time-sorted.
      const schedule = Schedule(
        events: {
          0: [],
          1: [],
          2: [],
          3: [],
          4: [],
          5: [night, dawn],
          6: [],
        },
      );
      final json = schedule.toJson(scheduleMode: 'HEAT');
      final saturday = (json['days'] as Map<String, dynamic>)['5'];
      expect(saturday, {
        '0': {
          'time': 21600,
          'type': 'HEAT',
          'entry_type': 'setpoint',
          'temp': 20.0,
        },
        '1': {
          'time': 79200,
          'type': 'HEAT',
          'entry_type': 'setpoint',
          'temp': 17.0,
        },
      });
      // Map iteration order must also be index order (JSON-encodes in order).
      expect((saturday as Map).keys.toList(), ['0', '1']);
    });

    test(
      'toJson emits the explicit scheduleMode, ignoring the stored mode',
      () {
        const schedule = Schedule(
          events: {0: [], 1: [], 2: [], 3: [], 4: [], 5: [], 6: []},
          mode: 'HEAT', // stale stored mode — must NOT leak onto the wire
        );
        final json = schedule.toJson(scheduleMode: 'COOL');
        expect(json['schedule_mode'], 'COOL');
      },
    );

    test('toJson defaults ver=2 and name="Current Schedule" when absent', () {
      const schedule = Schedule(
        events: {0: [], 1: [], 2: [], 3: [], 4: [], 5: [], 6: []},
      );
      final json = schedule.toJson(scheduleMode: 'HEAT');
      expect(json['ver'], 2);
      expect(json['name'], 'Current Schedule');
    });

    test('conformedTo coerces stale events across all days', () {
      const staleHeat = ScheduleEvent(
        dayIndex: 0,
        hour: 6,
        minute: 0,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      const staleRange = ScheduleEvent(
        dayIndex: 3,
        hour: 8,
        minute: 0,
        type: 'RANGE',
        targetTempLow: 18.0,
        targetTempHigh: 23.0,
      );
      const schedule = Schedule(
        events: {
          0: [staleHeat],
          1: [],
          2: [],
          3: [staleRange],
          4: [],
          5: [],
          6: [],
        },
      );
      final cooled = schedule.conformedTo('COOL');
      expect(cooled.eventsForDay(0).single.type, 'COOL');
      expect(cooled.eventsForDay(0).single.targetTemp, 20.0);
      expect(cooled.eventsForDay(3).single.type, 'COOL');
      expect(cooled.eventsForDay(3).single.targetTemp, 23.0);
      // Serialized payload contains no event conflicting with schedule_mode.
      final json = cooled.toJson(scheduleMode: 'COOL');
      final days = json['days'] as Map<String, dynamic>;
      for (final day in days.values) {
        for (final event in (day as Map<String, dynamic>).values) {
          expect((event as Map<String, dynamic>)['type'], 'COOL');
        }
      }
    });

    test('fromJson accepts ver+schedule_mode (current NLE shape)', () {
      final schedule = Schedule.fromJson({
        'ver': 3,
        'schedule_mode': 'COOL',
        'days': const {'0': []},
      });
      expect(schedule.version, 3);
      expect(schedule.mode, 'COOL');
    });

    test('fromJson still accepts legacy version+mode keys', () {
      final schedule = Schedule.fromJson({'version': 1, 'mode': 'HEAT'});
      expect(schedule.version, 1);
      expect(schedule.mode, 'HEAT');
    });
  });
}
