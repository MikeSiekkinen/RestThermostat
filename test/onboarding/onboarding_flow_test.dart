import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:rest_thermostat/models/auth_config.dart';
import 'package:rest_thermostat/onboarding/onboarding_flow.dart';
import 'package:rest_thermostat/services/nle_api_client.dart';
import 'package:rest_thermostat/services/onboarding_store.dart';

import 'fake_onboarding_store.dart';

({Dio dio, DioAdapter adapter, NleClientFactory factory}) _mockNetwork() {
  final dio = Dio(BaseOptions(baseUrl: 'http://placeholder'));
  final adapter = DioAdapter(dio: dio);
  NleApiClient factory(String url, AuthConfig auth) => NleApiClient(dio: dio);
  return (dio: dio, adapter: adapter, factory: factory);
}

Map<String, dynamic> _twoDeviceResponse() {
  final base =
      jsonDecode(File('test/fixtures/devices_one.json').readAsStringSync())
          as Map<String, dynamic>;
  final devices = base['devices'] as List<dynamic>;
  final extra = Map<String, dynamic>.from(devices.first as Map<String, dynamic>)
    ..['serial'] = 'OTHER_SERIAL'
    ..['name'] = 'Downstairs';
  return {
    'devices': [devices.first, extra],
    'total': 2,
  };
}

Widget _host({
  required OnboardingStore store,
  required OnboardingConfig initial,
  required NleClientFactory factory,
  required VoidCallback onComplete,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: OnboardingFlow(
      store: store,
      initial: initial,
      clientFactory: factory,
      onComplete: onComplete,
    ),
  );
}

void main() {
  testWidgets('welcome → server setup → 1-device path completes onboarding', (
    tester,
  ) async {
    final store = FakeOnboardingStore();
    final net = _mockNetwork();
    final body = jsonDecode(
      File('test/fixtures/devices_one.json').readAsStringSync(),
    );
    net.adapter.onGet('/api/devices', (server) => server.reply(200, body));
    var completedCalls = 0;

    await tester.pumpWidget(
      _host(
        store: store,
        initial: const OnboardingConfig(
          serverUrl: null,
          auth: AuthNone(),
          activeSerial: null,
          isComplete: false,
        ),
        factory: net.factory,
        onComplete: () => completedCalls++,
      ),
    );

    // Welcome → Server Setup
    expect(find.text('Get started'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'nest.home');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(completedCalls, 1);
    expect(store.serverUrl, 'http://nest.home:8082');
    expect(store.activeSerial, '02AA01AC041403JM');
    expect(store.complete, isTrue);
  });

  testWidgets('2-device response routes to picker and persists choice', (
    tester,
  ) async {
    final store = FakeOnboardingStore();
    final net = _mockNetwork();
    net.adapter.onGet(
      '/api/devices',
      (server) => server.reply(200, _twoDeviceResponse()),
    );
    var completed = false;

    await tester.pumpWidget(
      _host(
        store: store,
        initial: const OnboardingConfig(
          serverUrl: null,
          auth: AuthNone(),
          activeSerial: null,
          isComplete: false,
        ),
        factory: net.factory,
        onComplete: () => completed = true,
      ),
    );

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'nest.home');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a thermostat'), findsOneWidget);
    expect(completed, isFalse);

    await tester.tap(find.text('Downstairs'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(store.activeSerial, 'OTHER_SERIAL');
    expect(store.complete, isTrue);
  });

  testWidgets('0-device response shows blocking screen, back returns', (
    tester,
  ) async {
    final store = FakeOnboardingStore();
    final net = _mockNetwork();
    net.adapter.onGet(
      '/api/devices',
      (server) => server.reply(200, {'devices': <dynamic>[], 'total': 0}),
    );

    await tester.pumpWidget(
      _host(
        store: store,
        initial: const OnboardingConfig(
          serverUrl: null,
          auth: AuthNone(),
          activeSerial: null,
          isComplete: false,
        ),
        factory: net.factory,
        onComplete: () {},
      ),
    );

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'nest.home');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('No thermostats registered.'), findsOneWidget);
    expect(store.complete, isFalse);

    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(find.text('Server Setup'), findsOneWidget);
  });

  testWidgets('401 shows authentication-failed inline error', (tester) async {
    final store = FakeOnboardingStore();
    final net = _mockNetwork();
    net.adapter.onGet(
      '/api/devices',
      (server) => server.reply(401, {'error': 'unauthorized'}),
    );

    await tester.pumpWidget(
      _host(
        store: store,
        initial: const OnboardingConfig(
          serverUrl: null,
          auth: AuthNone(),
          activeSerial: null,
          isComplete: false,
        ),
        factory: net.factory,
        onComplete: () {},
      ),
    );

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'nest.home');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Authentication failed.'), findsOneWidget);
    expect(store.complete, isFalse);
  });

  testWidgets('resumes at Server Setup when a serverUrl is already persisted', (
    tester,
  ) async {
    final store = FakeOnboardingStore()
      ..serverUrl = 'http://saved.local:8082'
      ..auth = const AuthBearer(token: 'saved-token');

    await tester.pumpWidget(
      _host(
        store: store,
        initial: const OnboardingConfig(
          serverUrl: 'http://saved.local:8082',
          auth: AuthBearer(token: 'saved-token'),
          activeSerial: null,
          isComplete: false,
        ),
        factory: (_, _) => NleApiClient(dio: Dio()),
        onComplete: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Server Setup'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
    // URL pre-fill visible
    expect(
      find.widgetWithText(TextFormField, 'http://saved.local:8082'),
      findsOneWidget,
    );
  });
}
