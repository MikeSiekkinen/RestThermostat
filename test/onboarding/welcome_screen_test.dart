import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rest_thermostat/onboarding/welcome_screen.dart';

void main() {
  testWidgets('renders title, NLE docs URL, and Get started button', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: WelcomeScreen(onStart: () {})));

    expect(find.text('Rest Thermostat'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.textContaining('docs.nolongerevil.com'), findsOneWidget);
  });

  testWidgets('Get started triggers onStart', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(home: WelcomeScreen(onStart: () => tapped = true)),
    );

    await tester.tap(find.text('Get started'));
    expect(tapped, isTrue);
  });
}
