import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/services/device_display_name.dart';

Device _device({String? name, String serial = '02AA01AC041403JM'}) {
  final raw = File('test/fixtures/devices_one.json').readAsStringSync();
  final fixture = jsonDecode(raw) as Map<String, dynamic>;
  final entry =
      Map<String, dynamic>.from(
          (fixture['devices'] as List).first as Map<String, dynamic>,
        )
        ..['name'] = name
        ..['serial'] = serial;
  return Device.fromJson(entry);
}

void main() {
  group('displayNameFor', () {
    test('local override wins', () {
      final d = _device(name: 'Upstairs');
      expect(displayNameFor(d, {'02AA01AC041403JM': 'Den'}), 'Den');
    });

    test('falls through to NLE name when no override', () {
      final d = _device(name: 'Upstairs');
      expect(displayNameFor(d, const {}), 'Upstairs');
    });

    test('treats null name as missing → fallback', () {
      final d = _device(name: null);
      expect(displayNameFor(d, const {}), 'Thermostat (03JM)');
    });

    test('treats "unnamed" sentinel as missing → fallback', () {
      final d = _device(name: 'unnamed');
      expect(displayNameFor(d, const {}), 'Thermostat (03JM)');
    });

    test('fallback short serial uses entire serial', () {
      final d = _device(name: null, serial: 'AB');
      expect(displayNameFor(d, const {}), 'Thermostat (AB)');
    });
  });
}
