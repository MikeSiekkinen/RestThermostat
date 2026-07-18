import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
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
  String? localIp,
  String? macAddress,
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
  // The fixture predates upstream local_ip/mac_address support, so leaving
  // these unset exercises the pre-release-server (absent-keys) path.
  if (localIp != null) entry['local_ip'] = localIp;
  if (macAddress != null) entry['mac_address'] = macAddress;
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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

  group('DetailsScreen — network rows (local_ip / mac_address)', () {
    testWidgets('renders IP and formatted MAC when server provides them', (
      tester,
    ) async {
      await _pumpHost(
        tester,
        device: _device(
          target: 22.0,
          localIp: '192.168.1.50',
          macAddress: '18b430aabbcc',
        ),
      );
      expect(find.text('LOCAL IP'), findsOneWidget);
      expect(find.text('192.168.1.50'), findsOneWidget);
      expect(find.text('MAC ADDRESS'), findsOneWidget);
      expect(find.text('18:b4:30:aa:bb:cc'), findsOneWidget);
    });

    testWidgets('hides both rows when the server omits the fields', (
      tester,
    ) async {
      await _pumpHost(tester, device: _device(target: 22.0));
      expect(find.text('LOCAL IP'), findsNothing);
      expect(find.text('MAC ADDRESS'), findsNothing);
    });

    testWidgets('renders one row independently of the other', (tester) async {
      await _pumpHost(
        tester,
        device: _device(target: 22.0, localIp: '10.0.0.7'),
      );
      expect(find.text('LOCAL IP'), findsOneWidget);
      expect(find.text('10.0.0.7'), findsOneWidget);
      expect(find.text('MAC ADDRESS'), findsNothing);
    });

    testWidgets('malformed MAC renders verbatim', (tester) async {
      await _pumpHost(
        tester,
        device: _device(target: 22.0, macAddress: 'not-a-mac'),
      );
      expect(find.text('MAC ADDRESS'), findsOneWidget);
      expect(find.text('not-a-mac'), findsOneWidget);
    });

    testWidgets('empty-string fields hide their rows', (tester) async {
      await _pumpHost(
        tester,
        device: _device(target: 22.0, localIp: '', macAddress: ''),
      );
      expect(find.text('LOCAL IP'), findsNothing);
      expect(find.text('MAC ADDRESS'), findsNothing);
    });
  });
}
