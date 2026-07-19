import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
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

Widget _host(Widget child, {bool disableAnimations = false}) {
  // Wrap in MaterialApp so Theme + Directionality + MediaQuery are present,
  // and force a known size so CustomPaint has stable bounds.
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Center(
          child: SizedBox(
            width: TemperatureDial.preferredDiameter,
            height: TemperatureDial.preferredDiameter,
            child: child,
          ),
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

  group('TemperatureDial.celsiusForTickIndex', () {
    test('inverts tickIndexForCelsius at the endpoints', () {
      expect(TemperatureDial.celsiusForTickIndex(0), 4.5);
      expect(
        TemperatureDial.celsiusForTickIndex(TemperatureDial.tickCount - 1),
        32.0,
      );
    });

    test('clamps out-of-range indexes', () {
      expect(TemperatureDial.celsiusForTickIndex(-5), 4.5);
      expect(TemperatureDial.celsiusForTickIndex(9999), 32.0);
    });

    test('round-trips for a sample tick', () {
      // tick 36 → roughly the midpoint. Round-tripping through
      // tickIndexForCelsius should return the same tick.
      final c = TemperatureDial.celsiusForTickIndex(36);
      expect(TemperatureDial.tickIndexForCelsius(c), 36);
    });
  });

  group('TemperatureDial.tickIndexForLocalPoint', () {
    const size = Size(240, 240);
    final cx = size.width / 2, cy = size.height / 2;

    test('center returns null (no angle)', () {
      expect(
        TemperatureDial.tickIndexForLocalPoint(Offset(cx, cy), size),
        isNull,
      );
    });

    test('south-west (tick 0) returns tick 0', () {
      // 135° in screen coords (y-down): cos=−√2/2, sin=+√2/2.
      const r = 100.0;
      final p = Offset(cx + r * -0.7071, cy + r * 0.7071);
      expect(TemperatureDial.tickIndexForLocalPoint(p, size), 0);
    });

    test('north (top) returns mid-arc tick (~tick 35)', () {
      // -π/2 in atan2 is straight up. From arcStart=3π/4, sweeping to
      // -π/2+2π = 3π/2, position = 3π/2 - 3π/4 = 3π/4. Step = 3π/2 / 71.
      // 3π/4 / step = (3π/4) / (3π/142) = 35.5 → rounds to 36 (or 35 by
      // tiebreak). We just assert it lands in mid-range.
      final p = Offset(cx, cy - 100);
      final tick = TemperatureDial.tickIndexForLocalPoint(p, size);
      expect(tick, isNotNull);
      expect(tick, inInclusiveRange(33, 38));
    });

    test('south-east (tick 71) returns final tick', () {
      // 45° in screen coords.
      const r = 100.0;
      final p = Offset(cx + r * 0.7071, cy + r * 0.7071);
      expect(
        TemperatureDial.tickIndexForLocalPoint(p, size),
        TemperatureDial.tickCount - 1,
      );
    });

    test('south (bottom-gap mid) snaps to one of the endpoints', () {
      // Straight down at angle +π/2. Falls in the bottom 90° gap; expect
      // a clamp to either 0 or tickCount-1.
      final p = Offset(cx, cy + 100);
      final tick = TemperatureDial.tickIndexForLocalPoint(p, size);
      expect(tick, anyOf(0, TemperatureDial.tickCount - 1));
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

    testWidgets('appends the humidity reading to the current label when '
        'humidityPercent is set', (tester) async {
      await tester.pumpWidget(
        _host(
          const TemperatureDial(
            currentTemperatureCelsius: 18.0,
            targetTemperatureCelsius: 20.0,
            mode: DeviceMode.heat,
            displayUnit: 'C',
            capabilities: _allCapable,
            humidityPercent: 45,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Currently 18° · 45%'), findsOneWidget);
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

  group('TemperatureDial reduced motion (§11.7)', () {
    testWidgets(
      'target tween snaps to the new value within a single frame when '
      'disableAnimations is true',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const TemperatureDial(
              currentTemperatureCelsius: 18.0,
              targetTemperatureCelsius: 20.0,
              mode: DeviceMode.heat,
              displayUnit: 'C',
              capabilities: _allCapable,
            ),
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        // Swap target. With reduced motion, the new label should be visible
        // on the very next frame — no 400ms wait.
        await tester.pumpWidget(
          _host(
            const TemperatureDial(
              currentTemperatureCelsius: 18.0,
              targetTemperatureCelsius: 25.0,
              mode: DeviceMode.heat,
              displayUnit: 'C',
              capabilities: _allCapable,
            ),
            disableAnimations: true,
          ),
        );
        await tester.pump(); // one frame
        expect(find.text('25°'), findsOneWidget);
      },
    );
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
