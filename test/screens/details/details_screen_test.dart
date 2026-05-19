import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/auth_config.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/models/schedule.dart';
import 'package:rest_thermostat/screens/details/details_screen.dart';
import 'package:rest_thermostat/state/providers.dart';

Device _device({
  required double target,
  int humidity = 45,
  String ecoMode = 'schedule',
  String unit = 'F',
  String firmware = '5.9.3-9',
  bool isAvailable = true,
}) {
  final raw = File('test/fixtures/devices_one.json').readAsStringSync();
  final entry = Map<String, dynamic>.from(
    (jsonDecode(raw) as Map<String, dynamic>)['devices'][0]
        as Map<String, dynamic>,
  );
  entry['target_temperature'] = target;
  entry['humidity'] = humidity;
  entry['eco_mode'] = ecoMode;
  entry['temperature_scale'] = unit;
  entry['software_version'] = firmware;
  entry['is_available'] = isAvailable;
  return Device.fromJson(entry);
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required Device device,
  Schedule? schedule,
  DateTime? lastSyncAt,
  DateTime? now,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        scheduleProvider(device.serial).overrideWith((ref) async => schedule),
        // The Details screen reads `activeServerProvider` for the URL row;
        // give it a fixed value.
        activeServerProvider.overrideWith(_FakeServer.new),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: DetailsScreen(
            device: device,
            lastSyncAt: lastSyncAt,
            now: () => now ?? DateTime(2026, 5, 13, 12, 0, 0),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _FakeServer extends ActiveServerNotifier {
  @override
  ActiveServer? build() =>
      (url: 'http://nest.home:8082', auth: const AuthNone());
}

void main() {
  group('DetailsScreen — setpoint source rendering', () {
    testWidgets('Manual when no schedule loaded', (tester) async {
      await _pumpHost(tester, device: _device(target: 22.0));
      expect(find.text('Manual'), findsOneWidget);
    });

    testWidgets('Away wins over everything else', (tester) async {
      await _pumpHost(
        tester,
        device: _device(target: 22.0, ecoMode: 'manual-eco'),
      );
      expect(find.text('Away'), findsOneWidget);
    });

    testWidgets('Scheduled when active schedule event matches target', (
      tester,
    ) async {
      final schedule = Schedule(
        events: {
          2: [
            const ScheduleEvent(
              dayIndex: 2,
              hour: 8,
              minute: 0,
              type: 'HEAT',
              targetTemp: 22.0,
            ),
          ],
        },
      );
      await _pumpHost(
        tester,
        device: _device(target: 22.0, unit: 'C'),
        schedule: schedule,
      );
      expect(find.text('Scheduled'), findsOneWidget);
    });
  });

  group('DetailsScreen — stats grid', () {
    testWidgets('humidity comfort labels: Dry/Comfortable/Humid', (
      tester,
    ) async {
      await _pumpHost(tester, device: _device(target: 22.0, humidity: 20));
      expect(find.text('Dry'), findsOneWidget);

      await _pumpHost(tester, device: _device(target: 22.0, humidity: 40));
      expect(find.text('Comfortable'), findsOneWidget);

      await _pumpHost(tester, device: _device(target: 22.0, humidity: 70));
      expect(find.text('Humid'), findsOneWidget);
    });

    testWidgets('humidity value renders with percent sign', (tester) async {
      await _pumpHost(tester, device: _device(target: 22.0, humidity: 42));
      expect(find.text('42%'), findsOneWidget);
    });

    testWidgets('setpoint renders in Fahrenheit when temperature_scale is F', (
      tester,
    ) async {
      // 20°C = 68°F.
      await _pumpHost(tester, device: _device(target: 20.0, unit: 'F'));
      expect(find.text('68°'), findsOneWidget);
    });
  });

  group('DetailsScreen — system info block', () {
    testWidgets('renders status / server / firmware rows', (tester) async {
      await _pumpHost(
        tester,
        device: _device(target: 22.0, firmware: '5.9.3-9'),
      );
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('http://nest.home:8082'), findsOneWidget);
      expect(find.text('5.9.3-9'), findsOneWidget);
    });

    testWidgets('Offline when is_available=false', (tester) async {
      await _pumpHost(
        tester,
        device: _device(target: 22.0, isAvailable: false),
      );
      expect(find.text('Offline'), findsOneWidget);
    });

    testWidgets('Last sync renders as relative time', (tester) async {
      final now = DateTime(2026, 5, 13, 12, 0, 0);
      final last = now.subtract(const Duration(minutes: 2));
      await _pumpHost(
        tester,
        device: _device(target: 22.0),
        lastSyncAt: last,
        now: now,
      );
      expect(find.text('2 minutes ago'), findsOneWidget);
    });

    testWidgets('Last sync renders em-dash when never synced', (tester) async {
      await _pumpHost(tester, device: _device(target: 22.0));
      expect(find.textContaining('—'), findsWidgets);
    });
  });
}
