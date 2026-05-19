import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/widgets/ember_time_picker.dart';

void main() {
  group('EmberTimePicker.roundMinute', () {
    test('snaps to the nearest multiple of step', () {
      expect(EmberTimePicker.roundMinute(0, 5), 0);
      expect(EmberTimePicker.roundMinute(2, 5), 0);
      expect(EmberTimePicker.roundMinute(3, 5), 5);
      expect(EmberTimePicker.roundMinute(7, 5), 5);
      expect(EmberTimePicker.roundMinute(8, 5), 10);
      expect(EmberTimePicker.roundMinute(59, 5), 0); // wraps to next hour
    });

    test('round-half-up at the halfway point', () {
      expect(
        EmberTimePicker.roundMinute(2, 5),
        0,
      ); // .5 → 5 by floor((2+2.5)/5)*5? 4/5=0 → 0
      expect(EmberTimePicker.roundMinute(15, 10), 20);
    });

    test('step of 1 is a pass-through (mod 60)', () {
      expect(EmberTimePicker.roundMinute(0, 1), 0);
      expect(EmberTimePicker.roundMinute(33, 1), 33);
      expect(EmberTimePicker.roundMinute(59, 1), 59);
    });
  });

  testWidgets('renders hour and minute wheels in 24h mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EmberTimePicker(
            initialHour: 9,
            initialMinute: 15,
            use24Hour: true,
            onChanged: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 09 hour pad-2.
    expect(find.text('09'), findsOneWidget);
    // 15 minute (step=5, idx 3).
    expect(find.text('15'), findsOneWidget);
    // No AM/PM toggle in 24h mode.
    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
  });

  testWidgets('shows AM/PM toggle and 12-hour digits in 12h mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EmberTimePicker(
            initialHour: 14,
            initialMinute: 30,
            onChanged: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 14:30 → 2:30 PM. The minute display + AM/PM is visible.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('AM'), findsOneWidget);
    expect(find.text('PM'), findsOneWidget);
  });

  testWidgets('value-change callback fires on AM/PM toggle', (tester) async {
    int? capturedHour;
    int? capturedMinute;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EmberTimePicker(
            initialHour: 9, // AM
            initialMinute: 0,
            onChanged: (h, m) {
              capturedHour = h;
              capturedMinute = m;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Tap PM.
    await tester.tap(find.text('PM'));
    await tester.pumpAndSettle();
    expect(capturedHour, 21); // 9 + 12
    expect(capturedMinute, 0);
  });
}
