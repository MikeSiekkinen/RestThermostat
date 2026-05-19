import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:rest_thermostat/main.dart';
import 'package:rest_thermostat/services/nle_api_client.dart';
import 'package:rest_thermostat/state/providers.dart';
import 'package:rest_thermostat/widgets/device_picker_sheet.dart';

import 'onboarding/fake_onboarding_store.dart';
import 'state/fake_state_cache.dart';

/// Drain async without `pumpAndSettle`, which would hang on the StatusRow
/// pulse animation.
Future<void> _pumpUntilStable(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _wrap({required FakeOnboardingStore store, required Dio dio}) {
  return ProviderScope(
    overrides: [
      stateCacheProvider.overrideWithValue(FakeStateCache()),
      clientFactoryProvider.overrideWithValue((_, _) => NleApiClient(dio: dio)),
    ],
    child: RestThermostatApp(store: store),
  );
}

Map<String, dynamic> _oneDeviceBody() =>
    jsonDecode(File('test/fixtures/devices_one.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> _twoDeviceBody({
  String secondMode = 'heat',
  String secondName = 'Downstairs',
  String secondSerial = '02BB02BD041404KL',
}) {
  final base = _oneDeviceBody();
  final first = Map<String, dynamic>.from(
    (base['devices'] as List).first as Map<String, dynamic>,
  );
  final second = Map<String, dynamic>.from(first)
    ..['serial'] = secondSerial
    ..['name'] = secondName
    ..['mode'] = secondMode;
  // Vary the current temperature so we can tell the pages apart.
  second['current_temperature'] = 18.0;
  return {
    'devices': [first, second],
    'total': 2,
  };
}

void main() {
  testWidgets('single-device case has no caret, no swipe wrap, no dots', (
    tester,
  ) async {
    final store = FakeOnboardingStore()
      ..serverUrl = 'http://test.local:8082'
      ..activeSerial = '02AA01AC041403JM'
      ..complete = true;

    final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
    final adapter = DioAdapter(dio: dio);
    adapter.onGet('/api/devices', (s) => s.reply(200, _oneDeviceBody()));

    await tester.pumpWidget(_wrap(store: store, dio: dio));
    await _pumpUntilStable(tester);

    expect(find.text('Upstairs'), findsOneWidget);
    // Caret only appears in the multi-device case.
    expect(find.byIcon(Icons.expand_more), findsNothing);
    // No PageView wrap for a single device.
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('two devices renders caret and opens picker sheet on tap', (
    tester,
  ) async {
    final store = FakeOnboardingStore()
      ..serverUrl = 'http://test.local:8082'
      ..activeSerial = '02AA01AC041403JM'
      ..complete = true;

    final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
    final adapter = DioAdapter(dio: dio);
    adapter.onGet('/api/devices', (s) => s.reply(200, _twoDeviceBody()));

    await tester.pumpWidget(_wrap(store: store, dio: dio));
    await _pumpUntilStable(tester);

    // PageView wraps Home when there are 2+ devices.
    expect(find.byType(PageView), findsOneWidget);
    // Caret renders next to the device name.
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    // Tap the active device name to open the picker.
    await tester.tap(find.text('Upstairs').first);
    await _pumpUntilStable(tester);

    expect(find.byType(DevicePickerSheet), findsOneWidget);
    // Both devices listed in the sheet (the row in the sheet uses the same
    // display-name helper as the home header, so "Downstairs" appears once).
    expect(find.text('Downstairs'), findsOneWidget);

    // Tap the other device row → sheet dismisses, provider should advance.
    await tester.tap(find.text('Downstairs'));
    await _pumpUntilStable(tester);

    expect(find.byType(DevicePickerSheet), findsNothing);
    expect(store.activeSerial, '02BB02BD041404KL');
  });

  testWidgets('PageView swipe advances the active-device provider', (
    tester,
  ) async {
    final store = FakeOnboardingStore()
      ..serverUrl = 'http://test.local:8082'
      ..activeSerial = '02AA01AC041403JM'
      ..complete = true;

    final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
    final adapter = DioAdapter(dio: dio);
    adapter.onGet('/api/devices', (s) => s.reply(200, _twoDeviceBody()));

    await tester.pumpWidget(_wrap(store: store, dio: dio));
    await _pumpUntilStable(tester);

    // Swipe left on the PageView → advance to device index 1.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await _pumpUntilStable(tester);

    expect(store.activeSerial, '02BB02BD041404KL');
  });

  testWidgets(
    'persisted serial not in latest snapshot falls back and snackbars once',
    (tester) async {
      final store = FakeOnboardingStore()
        ..serverUrl = 'http://test.local:8082'
        ..activeSerial = 'STALE_SERIAL_NOT_IN_SNAPSHOT'
        ..complete = true;

      final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
      final adapter = DioAdapter(dio: dio);
      adapter.onGet('/api/devices', (s) => s.reply(200, _oneDeviceBody()));

      await tester.pumpWidget(_wrap(store: store, dio: dio));
      await _pumpUntilStable(tester);

      // Fallback snackbar copy is rendered exactly once.
      expect(
        find.text(
          "Active device changed — it wasn't in the latest device list.",
        ),
        findsOneWidget,
      );
      // The single device renders as the new active one.
      expect(find.text('Upstairs'), findsOneWidget);
    },
  );
}
