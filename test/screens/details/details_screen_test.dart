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
import 'package:rest_thermostat/settings/numeral_font.dart';
import 'package:rest_thermostat/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Device _device({
  required double target,
  int humidity = 45,
  String ecoMode = 'schedule',
  String unit = 'F',
  String firmware = '5.9.3-9',
  bool isAvailable = true,
  String? mode,
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
  if (mode != null) entry['mode'] = mode;
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
  Map<String, String> overrides = const {},
  NumeralFont? numeralFont,
  VoidCallback? onDeviceNameTap,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        scheduleProvider(device.serial).overrideWith((ref) async => schedule),
        // The Details screen reads `activeServerProvider` for the URL row;
        // give it a fixed value.
        activeServerProvider.overrideWith(_FakeServer.new),
        if (numeralFont != null)
          numeralFontProvider.overrideWith(
            () => _FixedNumeralFont(numeralFont),
          ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DetailsScreen(
            device: device,
            lastSyncAt: lastSyncAt,
            now: () => now ?? DateTime(2026, 5, 13, 12, 0, 0),
            overrides: overrides,
            onDeviceNameTap: onDeviceNameTap,
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

/// Pins the numeral font without touching SharedPreferences (the real notifier
/// hydrates asynchronously), so tests can assert the selected face deterministically.
class _FixedNumeralFont extends NumeralFontNotifier {
  _FixedNumeralFont(this._font);
  final NumeralFont _font;
  @override
  NumeralFont build() => _font;
}

void main() {
  // DetailsScreen now reads numeralFontProvider, whose real notifier hydrates
  // from SharedPreferences. Without a mock the platform channel never resolves,
  // so tests that don't override the provider would depend on an abandoned
  // pending future. Seed an empty in-memory store to keep hydration deterministic.
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  group('DetailsScreen — current header (name + mode)', () {
    testWidgets('shows device name and mode, first-letter-uppercase', (
      tester,
    ) async {
      // Fixture device is named "Upstairs" with mode "cool".
      await _pumpHost(tester, device: _device(target: 22.0));
      expect(find.text('Upstairs · Cool'), findsOneWidget);
      // The old static section label is gone.
      expect(find.text('CURRENT'), findsNothing);
    });

    testWidgets('a rename override wins over the server name', (tester) async {
      final device = _device(target: 22.0);
      await _pumpHost(
        tester,
        device: device,
        overrides: {device.serial: 'Living Room'},
      );
      expect(find.textContaining('Living Room · '), findsOneWidget);
    });

    testWidgets('heat-cool renders as Auto', (tester) async {
      await _pumpHost(tester, device: _device(target: 22.0, mode: 'heat-cool'));
      expect(find.text('Upstairs · Auto'), findsOneWidget);
    });

    testWidgets('off renders as Off', (tester) async {
      await _pumpHost(tester, device: _device(target: 22.0, mode: 'off'));
      expect(find.text('Upstairs · Off'), findsOneWidget);
    });

    testWidgets('emergency (no v1 pill) falls back to Heat', (tester) async {
      await _pumpHost(tester, device: _device(target: 22.0, mode: 'emergency'));
      expect(find.text('Upstairs · Heat'), findsOneWidget);
    });
  });

  group('DetailsScreen — temperature tile', () {
    testWidgets('renders a TEMP tile with the current temperature', (
      tester,
    ) async {
      // Fixture current_temperature is 24.76999°C → 77°F.
      await _pumpHost(tester, device: _device(target: 20.0, unit: 'F'));
      expect(find.text('TEMP'), findsOneWidget);
      expect(find.text('77°'), findsOneWidget);
      // Setpoint (20°C = 68°F) stays distinct from the current temp.
      expect(find.text('68°'), findsOneWidget);
    });
  });

  group('DetailsScreen — setpoint range', () {
    testWidgets('heat-cool renders a low – high range', (tester) async {
      // Fixture low/high = 20/24°C → 68/75°F; the range is the wide value the
      // per-tile FittedBox(scaleDown) exists to keep on one line.
      await _pumpHost(
        tester,
        device: _device(target: 22.0, unit: 'F', mode: 'heat-cool'),
      );
      expect(find.text('68° – 75°'), findsOneWidget);
    });
  });

  group('DetailsScreen — tile styling', () {
    testWidgets('footer sub-labels are not italic', (tester) async {
      await _pumpHost(tester, device: _device(target: 22.0, humidity: 40));
      final comfort = tester.widget<Text>(find.text('Comfortable'));
      expect(comfort.style?.fontStyle, isNot(FontStyle.italic));
      final source = tester.widget<Text>(find.text('Manual'));
      expect(source.style?.fontStyle, isNot(FontStyle.italic));
    });

    testWidgets('tile values use the configured numeral font', (tester) async {
      await _pumpHost(
        tester,
        device: _device(target: 22.0, humidity: 42),
        numeralFont: NumeralFont.anton,
      );
      final humidity = tester.widget<Text>(find.text('42%'));
      expect(humidity.style?.fontFamily, 'Anton');
      // The new temperature tile (24.76999°C → 77°F) carries it too.
      final temp = tester.widget<Text>(find.text('77°'));
      expect(temp.style?.fontFamily, 'Anton');
    });
  });

  group('CURRENT header device picker (Issue #127)', () {
    testWidgets('renders a caret and invokes the callback when the header is '
        'tapped (multi-device)', (tester) async {
      var taps = 0;
      await _pumpHost(
        tester,
        device: _device(target: 22.0),
        onDeviceNameTap: () => taps++,
      );

      // The caret mirrors Home's affordance.
      expect(find.byIcon(Icons.expand_more), findsOneWidget);

      // The combined "{name} · {mode}" heading is the whole tap target.
      await tester.tap(find.textContaining('Upstairs'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('shows no caret and is not tappable when single-device '
        '(callback null)', (tester) async {
      await _pumpHost(tester, device: _device(target: 22.0));

      // Header still renders (Issue #100 combined header) but with no caret.
      expect(find.textContaining('Upstairs'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });
  });
}
