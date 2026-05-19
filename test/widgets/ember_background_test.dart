import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/theme/colors.dart';
import 'package:rest_thermostat/widgets/ember_background.dart';

void main() {
  group('EmberBackground.backgroundColorsFor', () {
    test('heat uses warm gradient', () {
      expect(
        EmberBackground.backgroundColorsFor(DeviceMode.heat),
        EmberColors.heatBackground,
      );
    });

    test('emergency aliases to heat', () {
      expect(
        EmberBackground.backgroundColorsFor(DeviceMode.emergency),
        EmberColors.heatBackground,
      );
    });

    test('cool uses cool gradient', () {
      expect(
        EmberBackground.backgroundColorsFor(DeviceMode.cool),
        EmberColors.coolBackground,
      );
    });

    test('off and auto use neutral gradient', () {
      expect(
        EmberBackground.backgroundColorsFor(DeviceMode.off),
        EmberColors.neutralBackground,
      );
      expect(
        EmberBackground.backgroundColorsFor(DeviceMode.heatCool),
        EmberColors.neutralBackground,
      );
    });
  });

  group('EmberBackground.glowColorFor', () {
    test('heat glows orange', () {
      expect(
        EmberBackground.glowColorFor(DeviceMode.heat),
        EmberColors.heatGlow,
      );
    });

    test('cool glows blue', () {
      expect(
        EmberBackground.glowColorFor(DeviceMode.cool),
        EmberColors.coolGlow,
      );
    });

    test('off and auto have transparent glow (no mode color)', () {
      expect(EmberBackground.glowColorFor(DeviceMode.off), Colors.transparent);
      expect(
        EmberBackground.glowColorFor(DeviceMode.heatCool),
        Colors.transparent,
      );
    });
  });

  group('EmberBackground widget', () {
    testWidgets('renders child inside a stack with gradient container', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EmberBackground(
            mode: DeviceMode.heat,
            child: Text('hello', textDirection: TextDirection.ltr),
          ),
        ),
      );

      expect(find.text('hello'), findsOneWidget);
      // The outer AnimatedContainer should be present.
      expect(find.byType(AnimatedContainer), findsWidgets);
    });

    testWidgets('rebuilds with new mode without throwing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EmberBackground(
            mode: DeviceMode.heat,
            child: SizedBox.shrink(),
          ),
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: EmberBackground(
            mode: DeviceMode.cool,
            child: SizedBox.shrink(),
          ),
        ),
      );

      // Let the 300ms transition settle.
      await tester.pump(const Duration(milliseconds: 300));
      // No assertion failure means animated container handled the transition.
      expect(find.byType(EmberBackground), findsOneWidget);
    });
  });
}
