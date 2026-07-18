import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
import 'package:rest_thermostat/widgets/ember_time_fields.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

const _hourField = ValueKey('time-hour-field');
const _minuteField = ValueKey('time-minute-field');
const _amPill = ValueKey('time-am-pill');
const _pmPill = ValueKey('time-pm-pill');

void main() {
  testWidgets('24-hour mode renders no AM/PM pills and accepts 0–23', (
    tester,
  ) async {
    final calls = <(int?, int?)>[];
    await tester.pumpWidget(
      _wrap(
        EmberTimeFields(
          initialHour: 7,
          initialMinute: 0,
          use24Hour: true,
          onChanged: (h, m) => calls.add((h, m)),
        ),
      ),
    );

    expect(find.byKey(_amPill), findsNothing);
    expect(find.byKey(_pmPill), findsNothing);

    await tester.enterText(find.byKey(_hourField), '0');
    await tester.pump();
    expect(calls.last, (0, 0));

    await tester.enterText(find.byKey(_hourField), '23');
    await tester.pump();
    expect(calls.last, (23, 0));
  });

  testWidgets('24-hour mode rejects 24 with an inline error and null hour', (
    tester,
  ) async {
    final calls = <(int?, int?)>[];
    await tester.pumpWidget(
      _wrap(
        EmberTimeFields(
          initialHour: 7,
          initialMinute: 0,
          use24Hour: true,
          onChanged: (h, m) => calls.add((h, m)),
        ),
      ),
    );

    await tester.enterText(find.byKey(_hourField), '24');
    await tester.pump();
    expect(calls.last, (null, 0));
    expect(find.text('Enter an hour from 0–23'), findsOneWidget);
  });

  testWidgets('12-hour mode shows AM/PM and maps 12 AM → 0, 12 PM → 12', (
    tester,
  ) async {
    final calls = <(int?, int?)>[];
    await tester.pumpWidget(
      _wrap(
        EmberTimeFields(
          initialHour: 7,
          initialMinute: 0,
          onChanged: (h, m) => calls.add((h, m)),
        ),
      ),
    );

    expect(find.byKey(_amPill), findsOneWidget);
    expect(find.byKey(_pmPill), findsOneWidget);

    // 7:00 seed is AM, so entering 12 yields midnight.
    await tester.enterText(find.byKey(_hourField), '12');
    await tester.pump();
    expect(calls.last, (0, 0));

    await tester.tap(find.byKey(_pmPill));
    await tester.pump();
    expect(calls.last, (12, 0));
  });

  testWidgets('12-hour mode maps an afternoon time: 7:30 PM → 19:30', (
    tester,
  ) async {
    final calls = <(int?, int?)>[];
    await tester.pumpWidget(
      _wrap(
        EmberTimeFields(
          initialHour: 7,
          initialMinute: 0,
          onChanged: (h, m) => calls.add((h, m)),
        ),
      ),
    );

    await tester.enterText(find.byKey(_minuteField), '30');
    await tester.tap(find.byKey(_pmPill));
    await tester.pump();
    expect(calls.last, (19, 30));
  });

  testWidgets('12-hour mode rejects 0 with an inline error', (tester) async {
    final calls = <(int?, int?)>[];
    await tester.pumpWidget(
      _wrap(
        EmberTimeFields(
          initialHour: 7,
          initialMinute: 0,
          onChanged: (h, m) => calls.add((h, m)),
        ),
      ),
    );

    await tester.enterText(find.byKey(_hourField), '0');
    await tester.pump();
    expect(calls.last, (null, 0));
    expect(find.text('Enter an hour from 1–12'), findsOneWidget);
  });

  testWidgets('minute over 59 or empty reports null with an inline error', (
    tester,
  ) async {
    final calls = <(int?, int?)>[];
    await tester.pumpWidget(
      _wrap(
        EmberTimeFields(
          initialHour: 7,
          initialMinute: 0,
          use24Hour: true,
          onChanged: (h, m) => calls.add((h, m)),
        ),
      ),
    );

    await tester.enterText(find.byKey(_minuteField), '75');
    await tester.pump();
    expect(calls.last, (7, null));
    expect(find.text('Enter minutes from 0–59'), findsOneWidget);

    await tester.enterText(find.byKey(_minuteField), '');
    await tester.pump();
    expect(calls.last, (7, null));
    expect(find.text('Enter minutes from 0–59'), findsOneWidget);

    // Leading zeros are accepted.
    await tester.enterText(find.byKey(_minuteField), '05');
    await tester.pump();
    expect(calls.last, (7, 5));
    expect(find.text('Enter minutes from 0–59'), findsNothing);
  });

  testWidgets('prefills 19:30 as 7/30 PM in 12-hour mode', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmberTimeFields(
          initialHour: 19,
          initialMinute: 30,
          onChanged: (h, m) {},
        ),
      ),
    );

    expect(
      tester.widget<TextField>(find.byKey(_hourField)).controller!.text,
      '7',
    );
    expect(
      tester.widget<TextField>(find.byKey(_minuteField)).controller!.text,
      '30',
    );
  });

  testWidgets('prefills 19:30 as 19/30 in 24-hour mode', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmberTimeFields(
          initialHour: 19,
          initialMinute: 30,
          use24Hour: true,
          onChanged: (h, m) {},
        ),
      ),
    );

    expect(
      tester.widget<TextField>(find.byKey(_hourField)).controller!.text,
      '19',
    );
    expect(
      tester.widget<TextField>(find.byKey(_minuteField)).controller!.text,
      '30',
    );
  });

  testWidgets('prefills midnight as 12 AM in 12-hour mode', (tester) async {
    final calls = <(int?, int?)>[];
    await tester.pumpWidget(
      _wrap(
        EmberTimeFields(
          initialHour: 0,
          initialMinute: 0,
          onChanged: (h, m) => calls.add((h, m)),
        ),
      ),
    );

    expect(
      tester.widget<TextField>(find.byKey(_hourField)).controller!.text,
      '12',
    );
    // Flipping to PM from the midnight seed lands on noon — proves the seed
    // was parsed as 12 AM rather than an invalid hour.
    await tester.tap(find.byKey(_pmPill));
    await tester.pump();
    expect(calls.last, (12, 0));
  });
}
