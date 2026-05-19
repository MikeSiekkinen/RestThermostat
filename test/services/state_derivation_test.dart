import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/services/state_derivation.dart';

Device _device({
  required DeviceMode mode,
  required bool heater,
  required bool ac,
  required bool fan,
}) {
  final raw = File('test/fixtures/devices_one.json').readAsStringSync();
  final fixture = jsonDecode(raw) as Map<String, dynamic>;
  final entry = Map<String, dynamic>.from(
    (fixture['devices'] as List).first as Map<String, dynamic>,
  );
  entry['mode'] = mode.toApi();
  final hvac = Map<String, dynamic>.from(entry['hvac'] as Map<String, dynamic>);
  hvac['heater'] = heater;
  hvac['ac'] = ac;
  hvac['fan'] = fan;
  entry['hvac'] = hvac;
  return Device.fromJson(entry);
}

void main() {
  group('deriveStatus — DESIGN §9.2 table', () {
    test('heater true → Heating (regardless of mode)', () {
      expect(
        deriveStatus(
          _device(mode: DeviceMode.heat, heater: true, ac: false, fan: false),
        ),
        DeviceStatus.heating,
      );
      expect(
        deriveStatus(
          _device(
            mode: DeviceMode.heatCool,
            heater: true,
            ac: false,
            fan: false,
          ),
        ),
        DeviceStatus.heating,
      );
      // Even when "off" — defensive: if the equipment says it's heating, we
      // believe the equipment.
      expect(
        deriveStatus(
          _device(mode: DeviceMode.off, heater: true, ac: false, fan: false),
        ),
        DeviceStatus.heating,
      );
    });

    test('ac true → Cooling (regardless of mode)', () {
      expect(
        deriveStatus(
          _device(mode: DeviceMode.cool, heater: false, ac: true, fan: false),
        ),
        DeviceStatus.cooling,
      );
      expect(
        deriveStatus(
          _device(
            mode: DeviceMode.heatCool,
            heater: false,
            ac: true,
            fan: false,
          ),
        ),
        DeviceStatus.cooling,
      );
    });

    test('heat/cool/heat-cool with no hvac → Idle', () {
      for (final mode in [
        DeviceMode.heat,
        DeviceMode.cool,
        DeviceMode.heatCool,
      ]) {
        expect(
          deriveStatus(
            _device(mode: mode, heater: false, ac: false, fan: false),
          ),
          DeviceStatus.idle,
          reason: 'mode=$mode',
        );
      }
    });

    test('heat/cool/heat-cool with only fan running → Fan only', () {
      for (final mode in [
        DeviceMode.heat,
        DeviceMode.cool,
        DeviceMode.heatCool,
      ]) {
        expect(
          deriveStatus(
            _device(mode: mode, heater: false, ac: false, fan: true),
          ),
          DeviceStatus.fanOnly,
          reason: 'mode=$mode',
        );
      }
    });

    test('off + fan running → Fan only', () {
      expect(
        deriveStatus(
          _device(mode: DeviceMode.off, heater: false, ac: false, fan: true),
        ),
        DeviceStatus.fanOnly,
      );
    });

    test('off + nothing → Off', () {
      expect(
        deriveStatus(
          _device(mode: DeviceMode.off, heater: false, ac: false, fan: false),
        ),
        DeviceStatus.off,
      );
    });
  });

  group('deriveStatus — edge cases', () {
    test('heater wins over fan when both true', () {
      expect(
        deriveStatus(
          _device(mode: DeviceMode.heat, heater: true, ac: false, fan: true),
        ),
        DeviceStatus.heating,
      );
    });

    test('ac wins over fan when both true', () {
      expect(
        deriveStatus(
          _device(mode: DeviceMode.cool, heater: false, ac: true, fan: true),
        ),
        DeviceStatus.cooling,
      );
    });

    test(
      'emergency mode with no hvac → Idle (not in table; falls through)',
      () {
        expect(
          deriveStatus(
            _device(
              mode: DeviceMode.emergency,
              heater: false,
              ac: false,
              fan: false,
            ),
          ),
          DeviceStatus.idle,
        );
      },
    );
  });

  group('DeviceStatus labels', () {
    test('match DESIGN §9.2 wording', () {
      expect(DeviceStatus.heating.label, 'Heating');
      expect(DeviceStatus.cooling.label, 'Cooling');
      expect(DeviceStatus.fanOnly.label, 'Fan only');
      expect(DeviceStatus.idle.label, 'Idle');
      expect(DeviceStatus.off.label, 'Off');
    });
  });
}
