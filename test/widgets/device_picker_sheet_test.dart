import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/models/devices_response.dart';
import 'package:rest_thermostat/widgets/device_picker_sheet.dart';

List<Device> _fixture() {
  final body =
      jsonDecode(File('test/fixtures/devices_one.json').readAsStringSync())
          as Map<String, dynamic>;
  final base = DevicesResponse.fromJson(body).devices.first;
  return [
    base,
    Device(
      serial: '02BB02BD041404KL',
      apiKey: 'a.OTHER',
      name: 'Downstairs',
      isAvailable: base.isAvailable,
      isOnline: base.isOnline,
      lastSeen: base.lastSeen,
      currentTemperature: 19.0,
      targetTemperature: base.targetTemperature,
      targetTemperatureHigh: base.targetTemperatureHigh,
      targetTemperatureLow: base.targetTemperatureLow,
      humidity: base.humidity,
      targetHumidity: base.targetHumidity,
      targetHumidityEnabled: base.targetHumidityEnabled,
      mode: DeviceMode.heat,
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
}

void main() {
  testWidgets('shows every device row with display name', (tester) async {
    final devices = _fixture();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DevicePickerSheet(
            devices: devices,
            activeSerial: devices.first.serial,
          ),
        ),
      ),
    );

    expect(find.text('Upstairs'), findsOneWidget);
    expect(find.text('Downstairs'), findsOneWidget);
  });

  testWidgets('tapping a row pops with that serial', (tester) async {
    final devices = _fixture();
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await DevicePickerSheet.show(
                    context,
                    devices: devices,
                    activeSerial: devices.first.serial,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Downstairs'));
    await tester.pumpAndSettle();

    expect(picked, '02BB02BD041404KL');
  });

  testWidgets('renders a check next to the currently active device', (
    tester,
  ) async {
    final devices = _fixture();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DevicePickerSheet(
            devices: devices,
            activeSerial: devices.first.serial,
          ),
        ),
      ),
    );

    // Exactly one check icon (next to "Upstairs", which is `activeSerial`).
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
