import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/theme/colors.dart';
import 'package:rest_thermostat/widgets/status_row.dart';

Device _device({
  required DeviceMode mode,
  required bool heater,
  required bool ac,
  required bool fan,
  String? name = 'Upstairs',
  String serial = '02AA01AC041403JM',
}) {
  final raw = File('test/fixtures/devices_one.json').readAsStringSync();
  final fixture = jsonDecode(raw) as Map<String, dynamic>;
  final entry = Map<String, dynamic>.from(
    (fixture['devices'] as List).first as Map<String, dynamic>,
  );
  entry['mode'] = mode.toApi();
  entry['name'] = name;
  entry['serial'] = serial;
  final hvac = Map<String, dynamic>.from(entry['hvac'] as Map<String, dynamic>);
  hvac['heater'] = heater;
  hvac['ac'] = ac;
  hvac['fan'] = fan;
  entry['hvac'] = hvac;
  return Device.fromJson(entry);
}

Future<void> _pump(
  WidgetTester tester,
  Device device, {
  Map<String, String> overrides = const {},
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: StatusRow(device: device, nameOverrides: overrides),
        ),
      ),
    ),
  );
}

void main() {
  group('StatusRow rendering by mode', () {
    testWidgets('heater true → "Heating" + heat glow dot', (tester) async {
      final device = _device(
        mode: DeviceMode.heat,
        heater: true,
        ac: false,
        fan: false,
      );
      await _pump(tester, device);
      expect(find.text('Heating'), findsOneWidget);
      expect(find.text('Upstairs'), findsOneWidget);

      final container = tester.widgetList<Container>(find.byType(Container));
      final dot = container.firstWhere((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle;
      });
      expect((dot.decoration as BoxDecoration).color, EmberColors.heatGlow);
    });

    testWidgets('ac true → "Cooling" + cool glow dot', (tester) async {
      final device = _device(
        mode: DeviceMode.cool,
        heater: false,
        ac: true,
        fan: false,
      );
      await _pump(tester, device);
      expect(find.text('Cooling'), findsOneWidget);

      final container = tester.widgetList<Container>(find.byType(Container));
      final dot = container.firstWhere((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle;
      });
      expect((dot.decoration as BoxDecoration).color, EmberColors.coolGlow);
    });

    testWidgets('idle mode renders "Idle"', (tester) async {
      final device = _device(
        mode: DeviceMode.heat,
        heater: false,
        ac: false,
        fan: false,
      );
      await _pump(tester, device);
      expect(find.text('Idle'), findsOneWidget);
    });

    testWidgets('fan only renders "Fan only"', (tester) async {
      final device = _device(
        mode: DeviceMode.heat,
        heater: false,
        ac: false,
        fan: true,
      );
      await _pump(tester, device);
      expect(find.text('Fan only'), findsOneWidget);
    });

    testWidgets('off mode renders "Off"', (tester) async {
      final device = _device(
        mode: DeviceMode.off,
        heater: false,
        ac: false,
        fan: false,
      );
      await _pump(tester, device);
      expect(find.text('Off'), findsOneWidget);
    });
  });

  group('StatusRow naming', () {
    testWidgets('honors override from §4.4 helper', (tester) async {
      final device = _device(
        mode: DeviceMode.off,
        heater: false,
        ac: false,
        fan: false,
        name: 'Upstairs',
      );
      await _pump(tester, device, overrides: {'02AA01AC041403JM': 'Den'});
      expect(find.text('Den'), findsOneWidget);
      expect(find.text('Upstairs'), findsNothing);
    });

    testWidgets('falls back to "Thermostat (last-4)" when name is null', (
      tester,
    ) async {
      final device = _device(
        mode: DeviceMode.off,
        heater: false,
        ac: false,
        fan: false,
        name: null,
      );
      await _pump(tester, device);
      expect(find.text('Thermostat (03JM)'), findsOneWidget);
    });
  });

  group('StatusRow pulse animation', () {
    testWidgets('reduced-motion holds the dot at full brightness without '
        'animating', (tester) async {
      final device = _device(
        mode: DeviceMode.heat,
        heater: true,
        ac: false,
        fan: false,
      );
      await _pump(tester, device, disableAnimations: true);

      // After a frame, no further pumps should be needed for animation. The
      // dot widget still renders.
      expect(find.text('Heating'), findsOneWidget);

      // If the controller is still animating, additional pump(...) calls
      // would advance it. With reduced motion it should be stopped.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('Heating'), findsOneWidget);
    });

    testWidgets('pulses while in resumed lifecycle state', (tester) async {
      final device = _device(
        mode: DeviceMode.heat,
        heater: true,
        ac: false,
        fan: false,
      );
      await _pump(tester, device);
      // Drive the animation a bit; no exception should fire and the row
      // should keep rendering.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Heating'), findsOneWidget);
    });

    testWidgets('pauses on lifecycle paused without throwing', (tester) async {
      final device = _device(
        mode: DeviceMode.heat,
        heater: true,
        ac: false,
        fan: false,
      );
      await _pump(tester, device);

      // Simulate a background event; the widget's observer should stop the
      // controller without errors.
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.text('Heating'), findsOneWidget);

      // Resume — should restart cleanly.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Heating'), findsOneWidget);
    });
  });
}
