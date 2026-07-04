import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/models/devices_response.dart';

void main() {
  group('DeviceMode', () {
    test('fromApi maps each canonical value', () {
      expect(DeviceMode.fromApi('off'), DeviceMode.off);
      expect(DeviceMode.fromApi('heat'), DeviceMode.heat);
      expect(DeviceMode.fromApi('cool'), DeviceMode.cool);
      expect(DeviceMode.fromApi('heat-cool'), DeviceMode.heatCool);
      expect(DeviceMode.fromApi('emergency'), DeviceMode.emergency);
    });

    test('fromApi accepts "range" as an alias for heat-cool', () {
      // The live NLE server normalizes the write value `"heat-cool"` to
      // `"range"` on read; both must parse back to the same logical mode.
      expect(DeviceMode.fromApi('range'), DeviceMode.heatCool);
    });

    test('toApi roundtrips', () {
      for (final mode in DeviceMode.values) {
        expect(DeviceMode.fromApi(mode.toApi()), mode);
      }
    });

    test('fromApi throws on unknown value', () {
      expect(
        () => DeviceMode.fromApi('bogus'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Device.isAway', () {
    late Map<String, dynamic> base;

    setUp(() {
      final raw = File('test/fixtures/devices_one.json').readAsStringSync();
      base =
          (jsonDecode(raw) as Map<String, dynamic>)['devices'][0]
              as Map<String, dynamic>;
    });

    Device deviceWith({String? ecoMode}) {
      final entry = Map<String, dynamic>.from(base);
      entry['eco_mode'] = ecoMode;
      return Device.fromJson(entry);
    }

    test('eco_mode "manual-eco" → isAway true', () {
      expect(deviceWith(ecoMode: 'manual-eco').isAway, isTrue);
    });

    test('eco_mode "schedule" → isAway false', () {
      expect(deviceWith(ecoMode: 'schedule').isAway, isFalse);
    });

    test('eco_mode null → isAway false', () {
      expect(deviceWith(ecoMode: null).isAway, isFalse);
    });

    test('eco_mode anything-else → isAway false', () {
      expect(deviceWith(ecoMode: 'energy-savings').isAway, isFalse);
    });
  });

  group('DevicesResponse.fromJson', () {
    late Map<String, dynamic> fixture;

    setUp(() {
      final raw = File('test/fixtures/devices_one.json').readAsStringSync();
      fixture = jsonDecode(raw) as Map<String, dynamic>;
    });

    test('parses envelope', () {
      final response = DevicesResponse.fromJson(fixture);
      expect(response.total, 1);
      expect(response.devices, hasLength(1));
    });

    test('parses device top-level fields', () {
      final device = DevicesResponse.fromJson(fixture).devices.first;
      expect(device.serial, '02AA01AC041403JM');
      expect(device.apiKey, 'a.SCRUBBED_FOR_PUBLIC_REPO');
      expect(device.name, 'Upstairs');
      expect(device.isAvailable, isTrue);
      expect(device.isOnline, isFalse);
      expect(device.lastSeen, DateTime.parse('2026-05-19T01:16:11.339520'));
      expect(device.currentTemperature, closeTo(24.76999, 0.00001));
      expect(device.targetTemperature, closeTo(24.4444444, 0.00001));
      expect(device.targetTemperatureHigh, 24.0);
      expect(device.targetTemperatureLow, 20.0);
      expect(device.humidity, 60);
      expect(device.mode, DeviceMode.cool);
      expect(device.fanTimerActive, isFalse);
      expect(device.fanTimerTimeout, 0);
      expect(device.hasLeaf, isFalse);
      expect(device.softwareVersion, '5.9.4-5');
      expect(device.temperatureScale, 'F');
      expect(device.ecoMode, 'schedule');
      expect(device.timeToTarget, 0);
      expect(device.away, isFalse);
      expect(device.scheduleMode, isNull);
      expect(device.structureId, isNull);
      expect(device.backplateTemperature, closeTo(24.76999, 0.00001));
      expect(device.subscriptionCount, 2);
    });

    test('parses HVAC state', () {
      final hvac = DevicesResponse.fromJson(fixture).devices.first.hvac;
      expect(hvac.heater, isFalse);
      expect(hvac.ac, isTrue);
      expect(hvac.fan, isTrue);
      expect(hvac.coolX2, isFalse);
      expect(hvac.auxHeat, isFalse);
      expect(hvac.emerHeat, isFalse);
    });

    test('parses capabilities', () {
      final caps = DevicesResponse.fromJson(fixture).devices.first.capabilities;
      expect(caps.canHeat, isTrue);
      expect(caps.canCool, isTrue);
      expect(caps.hasFan, isTrue);
      expect(caps.hasEmerHeat, isFalse);
      expect(caps.hasHumidifier, isFalse);
      expect(caps.hasDehumidifier, isFalse);
    });

    test('parses eco temperatures', () {
      final eco = DevicesResponse.fromJson(
        fixture,
      ).devices.first.ecoTemperatures;
      expect(eco, isNotNull);
      expect(eco!.high, closeTo(25.43195, 0.00001));
      expect(eco.low, closeTo(21.11098, 0.00001));
    });

    test('handles null name when absent', () {
      final modified = Map<String, dynamic>.from(fixture);
      final device = Map<String, dynamic>.from(modified['devices'][0] as Map);
      device['name'] = null;
      modified['devices'] = [device];

      final parsed = DevicesResponse.fromJson(modified).devices.first;
      expect(parsed.name, isNull);
    });

    test('handles null eco_temperatures', () {
      final modified = Map<String, dynamic>.from(fixture);
      final device = Map<String, dynamic>.from(modified['devices'][0] as Map);
      device['eco_temperatures'] = null;
      modified['devices'] = [device];

      final parsed = DevicesResponse.fromJson(modified).devices.first;
      expect(parsed.ecoTemperatures, isNull);
    });

    // local_ip / mac_address only exist on NLE-SelfHosted servers running
    // main newer than 2026-06-29 (upstream PR #24). The exact wire keys
    // below are copied from that PR's diff — don't rename them.
    test('parses local_ip and mac_address when present', () {
      final modified = Map<String, dynamic>.from(fixture);
      final device = Map<String, dynamic>.from(modified['devices'][0] as Map);
      device['local_ip'] = '192.168.1.50';
      device['mac_address'] = '18b430aabbcc';
      modified['devices'] = [device];

      final parsed = DevicesResponse.fromJson(modified).devices.first;
      expect(parsed.localIp, '192.168.1.50');
      expect(parsed.macAddress, '18b430aabbcc');
    });

    test(
      'local_ip and mac_address are null when absent (pre-release server)',
      () {
        // The fixture predates the upstream change and carries neither key.
        final device = DevicesResponse.fromJson(fixture).devices.first;
        expect(device.localIp, isNull);
        expect(device.macAddress, isNull);
      },
    );
  });
}
