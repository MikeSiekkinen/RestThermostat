import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/theme/colors.dart';
import 'package:rest_thermostat/widgets/temperature_dial.dart';

const _allCapable = Capabilities(
  canHeat: true,
  canCool: true,
  hasFan: true,
  hasEmerHeat: false,
  hasHumidifier: false,
  hasDehumidifier: false,
);

Widget _host(Widget child) {
  // Wrap in MaterialApp so Theme + Directionality + MediaQuery are present,
  // and force a known size so CustomPaint has stable bounds.
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: TemperatureDial.preferredDiameter,
          height: TemperatureDial.preferredDiameter,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('TemperatureDial.tickIndexForCelsius', () {
    test('minimum (4.5°C) maps to tick 0', () {
      expect(TemperatureDial.tickIndexForCelsius(4.5), 0);
    });

    test('maximum (32°C) maps to the final tick (71)', () {
      expect(
        TemperatureDial.tickIndexForCelsius(32.0),
        TemperatureDial.tickCount - 1,
      );
    });

    test('midpoint (~18.25°C) lands near the middle of the tick set', () {
      // Halfway between 4.5 and 32 is 18.25. ratio = 0.5 → 0.5 * 71 = 35.5,
      // which rounds to 36 — the tick just past the geometric midpoint.
      expect(TemperatureDial.tickIndexForCelsius(18.25), 36);
    });

    test('clamps below minimum to tick 0', () {
      expect(TemperatureDial.tickIndexForCelsius(-10.0), 0);
    });

    test('clamps above maximum to final tick', () {
      expect(
        TemperatureDial.tickIndexForCelsius(99.0),
        TemperatureDial.tickCount - 1,
      );
    });
  });

  group('TemperatureDial.celsiusToDisplay', () {
    test('returns Celsius unchanged when unit is C', () {
      expect(TemperatureDial.celsiusToDisplay(20.0, 'C'), 20.0);
    });

    test('converts to Fahrenheit when unit is F', () {
      expect(TemperatureDial.celsiusToDisplay(0.0, 'F'), 32.0);
      expect(TemperatureDial.celsiusToDisplay(100.0, 'F'), 212.0);
    });

    test('case-insensitive unit handling', () {
      expect(TemperatureDial.celsiusToDisplay(0.0, 'f'), 32.0);
      expect(TemperatureDial.celsiusToDisplay(20.0, 'c'), 20.0);
    });
  });

  group('TemperatureDial.gradientColorsFor', () {
    test('heat uses heatGradient', () {
      expect(
        TemperatureDial.gradientColorsFor(DeviceMode.heat),
        EmberColors.heatGradient,
      );
    });

    test('emergency aliases to heat gradient', () {
      expect(
        TemperatureDial.gradientColorsFor(DeviceMode.emergency),
        EmberColors.heatGradient,
      );
    });

    test('cool uses coolGradient', () {
      expect(
        TemperatureDial.gradientColorsFor(DeviceMode.cool),
        EmberColors.coolGradient,
      );
    });

    test('off and heatCool use a neutral grey gradient (2 stops)', () {
      final off = TemperatureDial.gradientColorsFor(DeviceMode.off);
      final auto = TemperatureDial.gradientColorsFor(DeviceMode.heatCool);
      expect(off.length, 2);
      expect(auto.length, 2);
      // Both modes should share the same neutral pair so the dial reads
      // identically in either "no mode color" state.
      expect(off, auto);
    });
  });

  group('TemperatureDial widget', () {
    testWidgets('renders target + current label in °F when unit is F', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const TemperatureDial(
            // 20°C = 68°F; 18°C = 64.4°F → rounds to 64°F.
            currentTemperatureCelsius: 18.0,
            targetTemperatureCelsius: 20.0,
            mode: DeviceMode.heat,
            displayUnit: 'F',
            capabilities: _allCapable,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('68°'), findsOneWidget);
      expect(find.text('Currently 64°'), findsOneWidget);
    });

    testWidgets('renders target + current label in °C when unit is C', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const TemperatureDial(
            currentTemperatureCelsius: 18.0,
            targetTemperatureCelsius: 20.0,
            mode: DeviceMode.heat,
            displayUnit: 'C',
            capabilities: _allCapable,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('20°'), findsOneWidget);
      expect(find.text('Currently 18°'), findsOneWidget);
    });

    testWidgets('mounts a CustomPaint for the dial drawing', (tester) async {
      await tester.pumpWidget(
        _host(
          const TemperatureDial(
            currentTemperatureCelsius: 20.0,
            targetTemperatureCelsius: 22.0,
            mode: DeviceMode.cool,
            displayUnit: 'C',
            capabilities: _allCapable,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // At least one CustomPaint descendant — Flutter mounts internal
      // CustomPaints for some Material widgets, so we filter to the
      // TemperatureDial subtree.
      final dialPaints = find.descendant(
        of: find.byType(TemperatureDial),
        matching: find.byType(CustomPaint),
      );
      expect(dialPaints, findsWidgets);
    });

    testWidgets('rebuilds when target temperature changes', (tester) async {
      await tester.pumpWidget(
        _host(
          const TemperatureDial(
            currentTemperatureCelsius: 18.0,
            targetTemperatureCelsius: 20.0,
            mode: DeviceMode.heat,
            displayUnit: 'C',
            capabilities: _allCapable,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Swap in a new target — the tween in DESIGN §11.4 is 400ms.
      await tester.pumpWidget(
        _host(
          const TemperatureDial(
            currentTemperatureCelsius: 18.0,
            targetTemperatureCelsius: 25.0,
            mode: DeviceMode.heat,
            displayUnit: 'C',
            capabilities: _allCapable,
          ),
        ),
      );

      // Pump the full animation duration plus a frame to let TweenAnimationBuilder
      // settle on the new target.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('25°'), findsOneWidget);
    });
  });

  group('TemperatureDial constants', () {
    test('tick count is in the 60-80 spec range', () {
      expect(TemperatureDial.tickCount, greaterThanOrEqualTo(60));
      expect(TemperatureDial.tickCount, lessThanOrEqualTo(80));
    });

    test('exact tick count is 72 (60 + 12, 3.75° per tick over 270°)', () {
      expect(TemperatureDial.tickCount, 72);
    });

    test('range covers 4.5°C to 32°C per DESIGN §11.3', () {
      expect(TemperatureDial.minCelsius, 4.5);
      expect(TemperatureDial.maxCelsius, 32.0);
    });
  });
}
