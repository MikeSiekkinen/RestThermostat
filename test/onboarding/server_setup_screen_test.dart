import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rest_thermostat/models/auth_config.dart';
import 'package:rest_thermostat/onboarding/connect_outcome.dart';
import 'package:rest_thermostat/onboarding/server_setup_screen.dart';

void main() {
  Widget host({
    required ConnectFn onConnect,
    String? initialUrl,
    AuthConfig initialAuth = const AuthNone(),
  }) {
    return MaterialApp(
      home: ServerSetupScreen(
        initialUrl: initialUrl,
        initialAuth: initialAuth,
        onConnect: onConnect,
      ),
    );
  }

  testWidgets('rejects empty URL with inline validation', (tester) async {
    await tester.pumpWidget(
      host(onConnect: (_, _) async => const ConnectSuccess()),
    );

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Server address is required.'), findsOneWidget);
  });

  testWidgets('rejects ftp scheme with inline validation', (tester) async {
    await tester.pumpWidget(
      host(onConnect: (_, _) async => const ConnectSuccess()),
    );

    await tester.enterText(find.byType(TextFormField).first, 'ftp://bad');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Scheme must be http or https'), findsOneWidget);
  });

  testWidgets('Advanced expander reveals Basic fields when selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(onConnect: (_, _) async => const ConnectSuccess()),
    );

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basic').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Username'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
  });

  testWidgets('Connect normalizes URL and passes AuthBasic to callback', (
    tester,
  ) async {
    String? capturedUrl;
    AuthConfig? capturedAuth;

    await tester.pumpWidget(
      host(
        onConnect: (url, auth) async {
          capturedUrl = url;
          capturedAuth = auth;
          return const ConnectSuccess();
        },
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'nest.home');
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basic').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'mike',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter2',
    );

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(capturedUrl, 'http://nest.home:8082');
    final basic = capturedAuth as AuthBasic;
    expect(basic.username, 'mike');
    expect(basic.password, 'hunter2');
  });

  testWidgets('inline error from callback is displayed', (tester) async {
    await tester.pumpWidget(
      host(
        onConnect: (_, _) async =>
            const ConnectInlineError('Authentication failed.'),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'nest.home');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Authentication failed.'), findsOneWidget);
  });
}
