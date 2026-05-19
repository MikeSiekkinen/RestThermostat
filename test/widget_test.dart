import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:rest_thermostat/main.dart';
import 'package:rest_thermostat/services/nle_api_client.dart';
import 'package:rest_thermostat/state/providers.dart';

import 'onboarding/fake_onboarding_store.dart';
import 'state/fake_state_cache.dart';

Widget _wrap({required FakeOnboardingStore store, required Dio dio}) {
  return ProviderScope(
    overrides: [
      stateCacheProvider.overrideWithValue(FakeStateCache()),
      clientFactoryProvider.overrideWithValue((_, _) => NleApiClient(dio: dio)),
    ],
    child: RestThermostatApp(store: store),
  );
}

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

    await tester.pumpWidget(_wrap(store: store, dio: dio));
    await tester.pumpAndSettle();
    // Dio's mock adapter resolves the response via real-zone microtasks;
    // pumpAndSettle alone doesn't drain them in widget tests.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('Upstairs'), findsOneWidget);
    expect(find.text('Mode: cool'), findsOneWidget);
  });

  testWidgets('incomplete onboarding lands on Welcome screen', (tester) async {
    await tester.pumpWidget(_wrap(store: FakeOnboardingStore(), dio: Dio()));
    await tester.pumpAndSettle();

    expect(find.text('Get started'), findsOneWidget);
  });
}
