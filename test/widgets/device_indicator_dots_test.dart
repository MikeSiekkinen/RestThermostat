import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/theme/colors.dart';
import 'package:rest_thermostat/widgets/device_indicator_dots.dart';

void main() {
  testWidgets('renders nothing when count < 2', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DeviceIndicatorDots(
            count: 1,
            activeIndex: 0,
            activeMode: DeviceMode.heat,
          ),
        ),
      ),
    );
    // No animated containers, no dots.
    expect(find.byType(AnimatedContainer), findsNothing);
  });

  testWidgets('renders one dot per device when count >= 2', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DeviceIndicatorDots(
            count: 3,
            activeIndex: 1,
            activeMode: DeviceMode.cool,
          ),
        ),
      ),
    );
    expect(find.byType(AnimatedContainer), findsNWidgets(3));
  });

  testWidgets('active dot uses mode-colored fill', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DeviceIndicatorDots(
            count: 2,
            activeIndex: 0,
            activeMode: DeviceMode.heat,
          ),
        ),
      ),
    );
    final dots = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .toList();
    final firstColor = (dots[0].decoration as BoxDecoration).color;
    expect(firstColor, EmberColors.heatGlow);
  });
}
