import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/models/schedule.dart';
import 'package:rest_thermostat/services/setpoint_source.dart';

Device _device({required double target, String ecoMode = 'schedule'}) {
  final raw = File('test/fixtures/devices_one.json').readAsStringSync();
  final entry = Map<String, dynamic>.from(
    (jsonDecode(raw) as Map<String, dynamic>)['devices'][0]
        as Map<String, dynamic>,
  );
  entry['target_temperature'] = target;
  entry['eco_mode'] = ecoMode;
  return Device.fromJson(entry);
}

ScheduleEvent _ev({required int day, required int hour, double temp = 20.0}) =>
    ScheduleEvent(
      dayIndex: day,
      hour: hour,
      minute: 0,
      type: 'HEAT',
      targetTemp: temp,
    );

final DateTime _wedNoon = DateTime(2026, 5, 13, 12, 0, 0);

void main() {
  group('deriveSetpointSource', () {
    test('away wins over everything else', () {
      final device = _device(target: 20.0, ecoMode: 'manual-eco');
      final schedule = Schedule(
        events: {
          2: [_ev(day: 2, hour: 8, temp: 20.0)],
        },
      );
      final source = deriveSetpointSource(
        device: device,
        schedule: schedule,
        now: _wedNoon,
      );
      expect(source, SetpointSource.away);
    });

    test('null schedule → manual', () {
      final device = _device(target: 20.0);
      final source = deriveSetpointSource(
        device: device,
        schedule: null,
        now: _wedNoon,
      );
      expect(source, SetpointSource.manual);
    });

    test('schedule without an active event → manual', () {
      final device = _device(target: 20.0);
      final schedule = Schedule(
        events: {
          2: [_ev(day: 2, hour: 17, temp: 20.0)], // future event
        },
      );
      final source = deriveSetpointSource(
        device: device,
        schedule: schedule,
        now: _wedNoon,
      );
      expect(source, SetpointSource.manual);
    });

    test('active event matching target → scheduled', () {
      final device = _device(target: 20.0);
      final schedule = Schedule(
        events: {
          2: [_ev(day: 2, hour: 8, temp: 20.0)],
        },
      );
      final source = deriveSetpointSource(
        device: device,
        schedule: schedule,
        now: _wedNoon,
      );
      expect(source, SetpointSource.scheduled);
    });

    test('active event within half-tick epsilon → scheduled', () {
      // Half-tick at 72 ticks over [4.5, 32]°C is ~0.193°C.
      final device = _device(target: 20.15);
      final schedule = Schedule(
        events: {
          2: [_ev(day: 2, hour: 8, temp: 20.0)],
        },
      );
      final source = deriveSetpointSource(
        device: device,
        schedule: schedule,
        now: _wedNoon,
      );
      expect(source, SetpointSource.scheduled);
    });

    test('active event differs by more than half-tick → manual', () {
      final device = _device(target: 22.0);
      final schedule = Schedule(
        events: {
          2: [_ev(day: 2, hour: 8, temp: 20.0)],
        },
      );
      final source = deriveSetpointSource(
        device: device,
        schedule: schedule,
        now: _wedNoon,
      );
      expect(source, SetpointSource.manual);
    });

    test('range event with no single targetTemp → manual', () {
      final device = _device(target: 20.0);
      final schedule = Schedule(
        events: {
          2: [
            ScheduleEvent(
              dayIndex: 2,
              hour: 8,
              minute: 0,
              type: 'RANGE',
              targetTempLow: 18.0,
              targetTempHigh: 24.0,
            ),
          ],
        },
      );
      final source = deriveSetpointSource(
        device: device,
        schedule: schedule,
        now: _wedNoon,
      );
      expect(source, SetpointSource.manual);
    });
  });

  // SetpointSource.label is now context-bound — see app_en.arb keys
  // detailsSetpointSourceAway / detailsSetpointSourceScheduled /
  // detailsSetpointSourceManual. The localized rendering is exercised
  // through the Details-screen widget test.
}
