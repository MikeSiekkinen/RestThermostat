import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:rest_thermostat/main.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/services/nle_api_client.dart';
import 'package:rest_thermostat/state/providers.dart';
import 'package:rest_thermostat/widgets/device_picker_sheet.dart';
import 'package:rest_thermostat/widgets/ember_background.dart';

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

    // With 2+ devices every tab wraps its body in a device-swipe PageView
    // (Home, Schedule, Details — Issue #125), but only the active tab's is
    // onstage in the shell's IndexedStack, so the (skip-offstage) finder sees
    // exactly one: Home's.
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

    // Swipe left on the Home PageView (first in tree order) → advance to
    // device index 1.
    await tester.fling(
      find.byType(PageView).first,
      const Offset(-400, 0),
      1200,
    );
    await _pumpUntilStable(tester);

    expect(store.activeSerial, '02BB02BD041404KL');
  });

  testWidgets(
    'EmberBackground mode swaps when the active device changes via swipe',
    (tester) async {
      // First device is cool; second device is heat. The home background
      // wraps the whole MainShell — after the swipe, its `mode` should
      // reflect the new active device. The 300ms `easeInOutCubic`
      // AnimatedContainer inside EmberBackground handles the visual
      // crossfade automatically; this test just confirms the wiring.
      final store = FakeOnboardingStore()
        ..serverUrl = 'http://test.local:8082'
        ..activeSerial = '02AA01AC041403JM'
        ..complete = true;

      final firstAsCool = _oneDeviceBody();
      (firstAsCool['devices'] as List).first['mode'] = 'cool';
      final body = _twoDeviceBody(secondMode: 'heat');
      (body['devices'] as List)[0] = (firstAsCool['devices'] as List).first;

      final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
      DioAdapter(dio: dio).onGet('/api/devices', (s) => s.reply(200, body));

      await tester.pumpWidget(_wrap(store: store, dio: dio));
      await _pumpUntilStable(tester);

      // Find the home-level EmberBackground (the bootstrap loading splash
      // also uses one, but it's gone by now). When ambiguous we pick the
      // last match — that's the home wrapper.
      EmberBackground topLevel() =>
          tester.widgetList<EmberBackground>(find.byType(EmberBackground)).last;

      expect(topLevel().mode, DeviceMode.cool);

      // Swipe to advance to the heat-mode device (Home PageView is first).
      await tester.fling(
        find.byType(PageView).first,
        const Offset(-400, 0),
        1200,
      );
      await _pumpUntilStable(tester);

      expect(topLevel().mode, DeviceMode.heat);
    },
  );

  testWidgets('swiping the Schedule tab advances the active-device provider', (
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

    // Switch to the Schedule tab, then swipe between devices there (Issue
    // #125) rather than having to return to Home first. Only the active tab's
    // PageView is onstage, so the (skip-offstage) finder resolves to
    // Schedule's.
    await tester.tap(find.text('SCHEDULE'));
    await _pumpUntilStable(tester);

    // The Schedule header renders the active device's name (Issue #100),
    // independent of the schedule fetch — so it doubles as a "which device is
    // visible" probe. Device 0 first.
    expect(find.text('Upstairs'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await _pumpUntilStable(tester);

    // Both the shared state AND the visible page advanced to device 1.
    expect(store.activeSerial, '02BB02BD041404KL');
    expect(find.text('Downstairs'), findsOneWidget);
  });

  testWidgets('swiping the Details tab advances the active-device provider', (
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

    await tester.tap(find.text('DETAILS'));
    await _pumpUntilStable(tester);

    // The Details "CURRENT" header renders the active device's name (as
    // "{name} · {mode}") — a "which device is visible" probe. Device 0 first.
    expect(find.textContaining('Upstairs'), findsOneWidget);

    // Only the active (Details) tab's PageView is onstage.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await _pumpUntilStable(tester);

    // Both the shared state AND the visible page advanced to device 1.
    expect(store.activeSerial, '02BB02BD041404KL');
    expect(find.textContaining('Downstairs'), findsOneWidget);
  });

  testWidgets('tapping the Schedule header name opens the picker and selecting '
      'a device advances the active-device provider (Issue #127)', (
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

    await tester.tap(find.text('SCHEDULE'));
    await _pumpUntilStable(tester);

    // Non-gesture path: tap the header device name (not a swipe) to open the
    // same picker Home uses. Device 0 (Upstairs) is active first.
    expect(find.text('Upstairs'), findsOneWidget);
    await tester.tap(find.text('Upstairs').first);
    await _pumpUntilStable(tester);

    expect(find.byType(DevicePickerSheet), findsOneWidget);

    await tester.tap(find.text('Downstairs'));
    await _pumpUntilStable(tester);

    // Sheet dismisses; shared state + the visible page both advanced.
    expect(find.byType(DevicePickerSheet), findsNothing);
    expect(store.activeSerial, '02BB02BD041404KL');
    expect(find.text('Downstairs'), findsOneWidget);
  });

  testWidgets('tapping the Details CURRENT header opens the picker and '
      'selecting a device advances the active-device provider (Issue #127)', (
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

    await tester.tap(find.text('DETAILS'));
    await _pumpUntilStable(tester);

    // The "CURRENT" header renders "{name} · {mode}"; tapping it (non-gesture)
    // opens the picker. Device 0 (Upstairs) active first.
    expect(find.textContaining('Upstairs'), findsOneWidget);
    await tester.tap(find.textContaining('Upstairs').first);
    await _pumpUntilStable(tester);

    expect(find.byType(DevicePickerSheet), findsOneWidget);

    await tester.tap(find.text('Downstairs'));
    await _pumpUntilStable(tester);

    expect(find.byType(DevicePickerSheet), findsNothing);
    expect(store.activeSerial, '02BB02BD041404KL');
    expect(find.textContaining('Downstairs'), findsOneWidget);
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
