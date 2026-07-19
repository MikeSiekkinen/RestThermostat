import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rest_thermostat/onboarding/welcome_screen.dart';

void main() {
  testWidgets('renders title, NLE docs URL, and Get started button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WelcomeScreen(onStart: () {}),
      ),
    );

    expect(find.text('Rest Thermostat'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.textContaining('docs.nolongerevil.com'), findsOneWidget);
  });

  testWidgets('Get started triggers onStart', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WelcomeScreen(onStart: () => tapped = true),
      ),
    );

    await tester.tap(find.text('Get started'));
    expect(tapped, isTrue);
  });

  testWidgets('Restore button is hidden without an onRestore callback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WelcomeScreen(onStart: () {}),
      ),
    );

    expect(find.text('Restore from backup'), findsNothing);
  });

  testWidgets('Restore button shows and triggers onRestore when provided', (
    tester,
  ) async {
    var restored = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WelcomeScreen(onStart: () {}, onRestore: () => restored = true),
      ),
    );

    expect(find.text('Restore from backup'), findsOneWidget);
    await tester.tap(find.text('Restore from backup'));
    expect(restored, isTrue);
  });
}
