import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:rest_thermostat/main.dart';
import 'package:rest_thermostat/services/nle_api_client.dart';

import 'onboarding/fake_onboarding_store.dart';

void main() {
  testWidgets('completed onboarding renders Home with device data', (
    tester,
  ) async {
    final store = FakeOnboardingStore()
      ..serverUrl = 'http://test.local:8082'
      ..activeSerial = '02AA01AC041403JM'
      ..complete = true;

    final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
    final adapter = DioAdapter(dio: dio);
    final body = jsonDecode(
      File('test/fixtures/devices_one.json').readAsStringSync(),
    );
    adapter.onGet('/api/devices', (server) => server.reply(200, body));

    await tester.pumpWidget(
      RestThermostatApp(
        store: store,
        clientFactory: (_, _) => NleApiClient(dio: dio),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Upstairs'), findsOneWidget);
    expect(find.text('Mode: cool'), findsOneWidget);
  });

  testWidgets('incomplete onboarding lands on Welcome screen', (tester) async {
    await tester.pumpWidget(
      RestThermostatApp(
        store: FakeOnboardingStore(),
        clientFactory: (_, _) => NleApiClient(dio: Dio()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('Home shows error text on network failure', (tester) async {
    final store = FakeOnboardingStore()
      ..serverUrl = 'http://test.local:8082'
      ..activeSerial = 'serial'
      ..complete = true;

    final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
    final adapter = DioAdapter(dio: dio);
    adapter.onGet(
      '/api/devices',
      (server) => server.reply(500, {'error': 'boom'}),
    );

    await tester.pumpWidget(
      RestThermostatApp(
        store: store,
        clientFactory: (_, _) => NleApiClient(dio: dio),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Error:'), findsOneWidget);
  });
}
