import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/models/devices_response.dart';
import 'package:rest_thermostat/onboarding/device_picker_screen.dart';

List<Device> _fixtureDevices() {
  final body =
      jsonDecode(File('test/fixtures/devices_one.json').readAsStringSync())
          as Map<String, dynamic>;
  return DevicesResponse.fromJson(body).devices;
}

void main() {
  testWidgets('renders each device with name and serial', (tester) async {
    final base = _fixtureDevices().first;
    final devices = [
      base,
      Device(
        serial: '02BB02BD041404KL',
        apiKey: 'a.OTHER',
        name: 'Downstairs',
        isAvailable: base.isAvailable,
        isOnline: base.isOnline,
        lastSeen: base.lastSeen,
        currentTemperature: base.currentTemperature,
        targetTemperature: base.targetTemperature,
        targetTemperatureHigh: base.targetTemperatureHigh,
        targetTemperatureLow: base.targetTemperatureLow,
        humidity: base.humidity,
        targetHumidity: base.targetHumidity,
        targetHumidityEnabled: base.targetHumidityEnabled,
        mode: base.mode,
        hvac: base.hvac,
        fanTimerActive: base.fanTimerActive,
        fanTimerTimeout: base.fanTimerTimeout,
        ecoTemperatures: base.ecoTemperatures,
        hasLeaf: base.hasLeaf,
        softwareVersion: base.softwareVersion,
        temperatureScale: base.temperatureScale,
        capabilities: base.capabilities,
        ecoMode: base.ecoMode,
        timeToTarget: base.timeToTarget,
        away: base.away,
        scheduleMode: base.scheduleMode,
        structureId: base.structureId,
        backplateTemperature: base.backplateTemperature,
        subscriptionCount: base.subscriptionCount,
      ),
    ];

    Device? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: DevicePickerScreen(devices: devices, onPick: (d) => picked = d),
      ),
    );

    expect(find.text('Upstairs'), findsOneWidget);
    expect(find.text('Downstairs'), findsOneWidget);
    expect(find.text('02BB02BD041404KL'), findsOneWidget);

    await tester.tap(find.text('Downstairs'));
    expect(picked?.serial, '02BB02BD041404KL');
  });

  testWidgets('NoDevicesScreen surfaces blocking copy and back action', (
    tester,
  ) async {
    var backTapped = false;
    await tester.pumpWidget(
      MaterialApp(home: NoDevicesScreen(onBack: () => backTapped = true)),
    );

    expect(find.text('No thermostats registered.'), findsOneWidget);
    await tester.tap(find.text('Go back'));
    expect(backTapped, isTrue);
  });
}
