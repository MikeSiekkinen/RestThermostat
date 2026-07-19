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
import 'package:rest_thermostat/widgets/temperature_dial.dart';

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
    // Drain async — the FutureBuilder for onboarding config + Dio's mock
    // adapter both resolve via real-zone microtasks. We can't pumpAndSettle
    // because StatusRow's pulse animation repeats forever once Home mounts.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Device name renders above the dial; the dial widget itself is mounted
    // and shows the converted target temperature in its center label. The
    // fixture serves °F (`temperature_scale: "F"`), target 24.44°C → 76°F,
    // current 24.77°C → 77°F.
    expect(find.text('Upstairs'), findsOneWidget);
    expect(find.byType(TemperatureDial), findsOneWidget);
    expect(find.text('76°'), findsOneWidget);
    expect(find.text('Currently 77° · 60%'), findsOneWidget);
  });

  testWidgets('incomplete onboarding lands on Welcome screen', (tester) async {
    await tester.pumpWidget(_wrap(store: FakeOnboardingStore(), dio: Dio()));
    await tester.pumpAndSettle();

    expect(find.text('Get started'), findsOneWidget);
  });
}
