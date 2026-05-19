import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/widgets/mode_pills.dart';

const _allCapabilities = Capabilities(
  canHeat: true,
  canCool: true,
  hasFan: true,
  hasEmerHeat: false,
  hasHumidifier: false,
  hasDehumidifier: false,
);

const _heatOnly = Capabilities(
  canHeat: true,
  canCool: false,
  hasFan: false,
  hasEmerHeat: false,
  hasHumidifier: false,
  hasDehumidifier: false,
);

const _coolOnly = Capabilities(
  canHeat: false,
  canCool: true,
  hasFan: false,
  hasEmerHeat: false,
  hasHumidifier: false,
  hasDehumidifier: false,
);

const _bothDisabled = Capabilities(
  canHeat: false,
  canCool: false,
  hasFan: false,
  hasEmerHeat: false,
  hasHumidifier: false,
  hasDehumidifier: false,
);

void main() {
  group('ModePillOption', () {
    test('labels are uppercase strings', () {
      expect(ModePillOption.off.label, 'OFF');
      expect(ModePillOption.heat.label, 'HEAT');
      expect(ModePillOption.cool.label, 'COOL');
      expect(ModePillOption.auto.label, 'AUTO');
    });

    test('toDeviceMode round-trips with fromDeviceMode for v1 modes', () {
      for (final option in ModePillOption.values) {
        final mode = option.toDeviceMode();
        expect(ModePillOption.fromDeviceMode(mode), option);
      }
    });

    test('auto maps to heat-cool on the API', () {
      expect(ModePillOption.auto.toDeviceMode(), DeviceMode.heatCool);
      expect(ModePillOption.auto.toDeviceMode().toApi(), 'heat-cool');
    });

    test('emergency mode has no pill representation', () {
      expect(ModePillOption.fromDeviceMode(DeviceMode.emergency), isNull);
    });
  });

  group('visiblePillsFor', () {
    test('all capabilities show all four pills in order', () {
      expect(visiblePillsFor(_allCapabilities), [
        ModePillOption.off,
        ModePillOption.heat,
        ModePillOption.cool,
        ModePillOption.auto,
      ]);
    });

    test('heat-only hides Cool and Auto', () {
      expect(visiblePillsFor(_heatOnly), [
        ModePillOption.off,
        ModePillOption.heat,
      ]);
    });

    test('cool-only hides Heat and Auto', () {
      expect(visiblePillsFor(_coolOnly), [
        ModePillOption.off,
        ModePillOption.cool,
      ]);
    });

    test('both disabled leaves only OFF visible', () {
      expect(visiblePillsFor(_bothDisabled), [ModePillOption.off]);
    });
  });

  group('ModePills widget', () {
    Future<void> pumpPills(
      WidgetTester tester, {
      required DeviceMode currentMode,
      required Capabilities capabilities,
      ValueChanged<ModePillOption>? onModeTap,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ModePills(
              currentMode: currentMode,
              capabilities: capabilities,
              onModeTap: onModeTap,
            ),
          ),
        ),
      );
    }

    testWidgets('all-capabilities renders OFF/HEAT/COOL/AUTO', (tester) async {
      await pumpPills(
        tester,
        currentMode: DeviceMode.heat,
        capabilities: _allCapabilities,
      );

      expect(find.text('OFF'), findsOneWidget);
      expect(find.text('HEAT'), findsOneWidget);
      expect(find.text('COOL'), findsOneWidget);
      expect(find.text('AUTO'), findsOneWidget);
    });

    testWidgets('heat-only hides COOL and AUTO', (tester) async {
      await pumpPills(
        tester,
        currentMode: DeviceMode.heat,
        capabilities: _heatOnly,
      );

      expect(find.text('OFF'), findsOneWidget);
      expect(find.text('HEAT'), findsOneWidget);
      expect(find.text('COOL'), findsNothing);
      expect(find.text('AUTO'), findsNothing);
    });

    testWidgets('cool-only hides HEAT and AUTO', (tester) async {
      await pumpPills(
        tester,
        currentMode: DeviceMode.cool,
        capabilities: _coolOnly,
      );

      expect(find.text('OFF'), findsOneWidget);
      expect(find.text('COOL'), findsOneWidget);
      expect(find.text('HEAT'), findsNothing);
      expect(find.text('AUTO'), findsNothing);
    });

    testWidgets('both-disabled shows only OFF', (tester) async {
      await pumpPills(
        tester,
        currentMode: DeviceMode.off,
        capabilities: _bothDisabled,
      );

      expect(find.text('OFF'), findsOneWidget);
      expect(find.text('HEAT'), findsNothing);
      expect(find.text('COOL'), findsNothing);
      expect(find.text('AUTO'), findsNothing);
    });

    testWidgets('active pill paints with a mode-tinted border', (tester) async {
      await pumpPills(
        tester,
        currentMode: DeviceMode.cool,
        capabilities: _allCapabilities,
        onModeTap: (_) {},
      );

      // The HEAT pill is inactive (currentMode is cool) — its border should be
      // the 10%-white inactive color, not full-opacity mode accent.
      final inactiveContainer = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text('HEAT'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final inactiveDecoration = inactiveContainer.decoration as BoxDecoration;
      final inactiveAlpha = inactiveDecoration.border!.top.color.a;
      expect(inactiveAlpha, lessThan(0.5));

      // The COOL pill is active — opaque border.
      final activeContainer = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text('COOL'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final activeDecoration = activeContainer.decoration as BoxDecoration;
      final activeAlpha = activeDecoration.border!.top.color.a;
      expect(activeAlpha, greaterThan(0.9));
    });

    testWidgets('tap on a pill invokes the callback with that option', (
      tester,
    ) async {
      final taps = <ModePillOption>[];
      await pumpPills(
        tester,
        currentMode: DeviceMode.off,
        capabilities: _allCapabilities,
        onModeTap: taps.add,
      );

      await tester.tap(find.text('HEAT'));
      await tester.tap(find.text('AUTO'));
      await tester.pump();

      expect(taps, [ModePillOption.heat, ModePillOption.auto]);
    });

    testWidgets('emergency mode highlights no pill', (tester) async {
      await pumpPills(
        tester,
        currentMode: DeviceMode.emergency,
        capabilities: _allCapabilities,
      );

      // No pill should be in the active state. Check every pill border has
      // the inactive (low-alpha) color.
      for (final label in ['OFF', 'HEAT', 'COOL', 'AUTO']) {
        final container = tester.widget<AnimatedContainer>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final decoration = container.decoration as BoxDecoration;
        expect(
          decoration.border!.top.color.a,
          lessThan(0.5),
          reason: 'No pill should be active in emergency mode ($label)',
        );
      }
    });
  });

  group('a11y', () {
    testWidgets('each pill exposes a Semantics node with button + label', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ModePills(
              currentMode: DeviceMode.heat,
              capabilities: _allCapabilities,
              onModeTap: (_) {},
            ),
          ),
        ),
      );

      // Look up the Semantics annotation for the HEAT pill — the framework
      // hoists onTap into a button role. The inner Text is ExcludeSemantics'd
      // so TalkBack hears the label exactly once.
      final semantics = tester.getSemantics(find.text('HEAT'));
      expect(semantics.label, 'HEAT');
      // The currently-active pill carries `selected`. `flagsCollection`
      // returns a Tristate (true/false/unset) so we compare via `toString()`
      // rather than the deprecated `hasFlag`.
      expect(
        semantics.flagsCollection.isSelected.toString(),
        contains('isTrue'),
        reason: 'active pill should expose selected=true to assistive tech',
      );
    });

    testWidgets('hit target reaches at least 48dp tall per Material guidance', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ModePills(
              currentMode: DeviceMode.off,
              capabilities: _allCapabilities,
              onModeTap: (_) {},
            ),
          ),
        ),
      );

      // The gesture-bearing ConstrainedBox is the inner Container with
      // minHeight: 48 inside the per-pill Semantics. Find its size via the
      // RenderBox of the GestureDetector child.
      final detector = find.descendant(
        of: find.byType(ModePills),
        matching: find.byType(GestureDetector),
      );
      expect(detector, findsWidgets);
      for (final element in detector.evaluate()) {
        final size = (element.renderObject as RenderBox).size;
        expect(
          size.height,
          greaterThanOrEqualTo(48),
          reason: 'mode pill tap target must be ≥48dp',
        );
      }
    });
  });
}
