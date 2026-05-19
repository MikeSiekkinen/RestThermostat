import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:rest_thermostat/models/auth_config.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/models/schedule.dart';
import 'package:rest_thermostat/screens/schedule/edit_event_screen.dart';
import 'package:rest_thermostat/services/nle_api_client.dart';
import 'package:rest_thermostat/state/providers.dart';

class _Harness {
  final Widget widget;
  final DioAdapter adapter;
  final ValueNotifier<Schedule?> result;

  _Harness({required this.widget, required this.adapter, required this.result});
}

class _SeedActiveServer extends ActiveServerNotifier {
  final ActiveServer? seed;
  _SeedActiveServer(this.seed);
  @override
  ActiveServer? build() => seed;
}

Schedule _emptyWeek() => const Schedule(
  events: {0: [], 1: [], 2: [], 3: [], 4: [], 5: [], 6: []},
  mode: 'HEAT',
);

const Capabilities _bothCaps = Capabilities(
  canHeat: true,
  canCool: true,
  hasFan: false,
  hasEmerHeat: false,
  hasHumidifier: false,
  hasDehumidifier: false,
);

const Capabilities _heatOnlyCaps = Capabilities(
  canHeat: true,
  canCool: false,
  hasFan: false,
  hasEmerHeat: false,
  hasHumidifier: false,
  hasDehumidifier: false,
);

_Harness _setup({
  required Schedule schedule,
  ScheduleEvent? existingEvent,
  int defaultDayIndex = 0,
  Capabilities capabilities = _bothCaps,
  String temperatureScale = 'C',
  Locale locale = const Locale('en', 'GB'),
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
  final adapter = DioAdapter(dio: dio);
  final result = ValueNotifier<Schedule?>(null);

  // Capture the optimistic-pop return value so tests can assert on the local
  // schedule update without depending on the network roundtrip completing.
  final widget = ProviderScope(
    overrides: [
      clientFactoryProvider.overrideWithValue(
        (url, auth) => NleApiClient(dio: dio),
      ),
      activeServerProvider.overrideWith(
        () => _SeedActiveServer((
          url: 'http://test.local:8082',
          auth: const AuthNone(),
        )),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en', 'GB'), Locale('en', 'US')],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open-edit-event'),
              onPressed: () async {
                final r = await Navigator.of(context).push<Schedule?>(
                  MaterialPageRoute(
                    builder: (_) => EditEventScreen(
                      serial: 'abc',
                      capabilities: capabilities,
                      temperatureScale: temperatureScale,
                      currentSchedule: schedule,
                      defaultDayIndex: defaultDayIndex,
                      existingEvent: existingEvent,
                    ),
                  ),
                );
                result.value = r;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  return _Harness(widget: widget, adapter: adapter, result: result);
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-edit-event')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('new mode shows repeat-days circles, edit mode hides them', (
    tester,
  ) async {
    // New mode.
    final newH = _setup(schedule: _emptyWeek(), defaultDayIndex: 0);
    await tester.pumpWidget(newH.widget);
    await _openEditor(tester);

    expect(find.byKey(const ValueKey('repeat-day-0')), findsOneWidget);
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-event-button')), findsNothing);

    // Dispose this tree before mounting the next.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    // Edit mode.
    const existing = ScheduleEvent(
      dayIndex: 1,
      hour: 7,
      minute: 0,
      type: 'HEAT',
      targetTemp: 20.0,
    );
    final schedule = _emptyWeek().addEvent(existing);
    final editH = _setup(
      schedule: schedule,
      existingEvent: existing,
      defaultDayIndex: 1,
    );
    await tester.pumpWidget(editH.widget);
    await _openEditor(tester);

    expect(find.text('Repeat'), findsNothing);
    expect(find.byKey(const ValueKey('repeat-day-0')), findsNothing);
    expect(find.byKey(const ValueKey('delete-event-button')), findsOneWidget);
  });

  testWidgets('mode selector shows only HEAT for heat-only capabilities', (
    tester,
  ) async {
    final h = _setup(schedule: _emptyWeek(), capabilities: _heatOnlyCaps);
    await tester.pumpWidget(h.widget);
    await _openEditor(tester);

    expect(find.byKey(const ValueKey('mode-pill-HEAT')), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-pill-COOL')), findsNothing);
    expect(find.byKey(const ValueKey('mode-pill-RANGE')), findsNothing);
  });

  testWidgets('mode selector shows HEAT/COOL/RANGE when both caps present', (
    tester,
  ) async {
    final h = _setup(schedule: _emptyWeek());
    await tester.pumpWidget(h.widget);
    await _openEditor(tester);

    expect(find.byKey(const ValueKey('mode-pill-HEAT')), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-pill-COOL')), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-pill-RANGE')), findsOneWidget);
  });

  testWidgets('selecting RANGE reveals dual temperature pickers', (
    tester,
  ) async {
    final h = _setup(schedule: _emptyWeek());
    await tester.pumpWidget(h.widget);
    await _openEditor(tester);

    await tester.tap(find.byKey(const ValueKey('mode-pill-RANGE')));
    await tester.pumpAndSettle();

    // Both labels visible side-by-side.
    expect(find.text('HEAT'), findsWidgets);
    expect(find.text('COOL'), findsWidgets);
    // Two temp-up buttons present (one per stepper).
    expect(find.byKey(const ValueKey('temp-up-HEAT')), findsOneWidget);
    expect(find.byKey(const ValueKey('temp-up-COOL')), findsOneWidget);
  });

  testWidgets('Cancel returns null without mutating the schedule', (
    tester,
  ) async {
    final h = _setup(schedule: _emptyWeek());
    await tester.pumpWidget(h.widget);
    await _openEditor(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.result.value, isNull);
  });

  testWidgets(
    'new event with multiple repeat days clones into each selected day',
    (tester) async {
      final h = _setup(schedule: _emptyWeek(), defaultDayIndex: 0);
      // Stub the POST so the optimistic save's network call succeeds.
      h.adapter.onPost(
        '/command',
        (s) => s.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      // Add Tuesday (1) and Wednesday (2) to the default Monday (0).
      await tester.tap(find.byKey(const ValueKey('repeat-day-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('repeat-day-2')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = h.result.value;
      expect(saved, isNotNull);
      expect(saved!.eventsForDay(0), hasLength(1));
      expect(saved.eventsForDay(1), hasLength(1));
      expect(saved.eventsForDay(2), hasLength(1));
      // Other days untouched.
      expect(saved.eventsForDay(3), isEmpty);
    },
  );

  testWidgets('edit mode replaces the existing event in just its day', (
    tester,
  ) async {
    const existing = ScheduleEvent(
      dayIndex: 1,
      hour: 7,
      minute: 0,
      type: 'HEAT',
      targetTemp: 20.0,
    );
    final schedule = _emptyWeek()
        .addEvent(existing)
        .addEvent(
          const ScheduleEvent(
            dayIndex: 1,
            hour: 22,
            minute: 0,
            type: 'HEAT',
            targetTemp: 17.0,
          ),
        );
    final h = _setup(
      schedule: schedule,
      existingEvent: existing,
      defaultDayIndex: 1,
    );
    h.adapter.onPost(
      '/command',
      (s) => s.reply(200, {'ok': true}),
      data: Matchers.any,
    );

    await tester.pumpWidget(h.widget);
    await _openEditor(tester);

    // Bump the target temp once.
    await tester.tap(find.byKey(const ValueKey('temp-up-HEAT')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = h.result.value!;
    final mondayEvents = saved.eventsForDay(1);
    expect(mondayEvents, hasLength(2));
    final updated = mondayEvents.firstWhere((e) => e.hour == 7);
    expect(updated.targetTemp, greaterThan(20.0));
    // No event leaked into other days.
    expect(saved.eventsForDay(0), isEmpty);
  });

  testWidgets(
    'successful save fires HapticFeedback.mediumImpact per DESIGN §11.5',
    (tester) async {
      final haptics = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments as String);
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final h = _setup(schedule: _emptyWeek(), defaultDayIndex: 0);
      h.adapter.onPost(
        '/command',
        (s) => s.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        haptics,
        contains('HapticFeedbackType.mediumImpact'),
        reason:
            'schedule save success should fire medium-impact haptic per §11.5',
      );
    },
  );

  testWidgets('save failure does NOT fire the success haptic', (tester) async {
    final haptics = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final h = _setup(schedule: _emptyWeek(), defaultDayIndex: 0);
    h.adapter.onPost(
      '/command',
      (s) => s.reply(500, {'error': 'server down'}),
      data: Matchers.any,
    );

    await tester.pumpWidget(h.widget);
    await _openEditor(tester);

    await tester.tap(find.text('Save'));
    // sendCommand retries with a 2s delay on 5xx — wait it out, then settle.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(haptics, isEmpty);
  });

  testWidgets('delete confirms with a dialog and then removes the event', (
    tester,
  ) async {
    const existing = ScheduleEvent(
      dayIndex: 2,
      hour: 7,
      minute: 0,
      type: 'HEAT',
      targetTemp: 20.0,
    );
    final schedule = _emptyWeek().addEvent(existing);
    final h = _setup(
      schedule: schedule,
      existingEvent: existing,
      defaultDayIndex: 2,
    );
    h.adapter.onPost(
      '/command',
      (s) => s.reply(200, {'ok': true}),
      data: Matchers.any,
    );

    await tester.pumpWidget(h.widget);
    await _openEditor(tester);

    await tester.tap(find.byKey(const ValueKey('delete-event-button')));
    await tester.pumpAndSettle();

    // Confirmation dialog visible.
    expect(find.text('Delete event?'), findsOneWidget);

    // Cancel from the dialog returns to the editor without deletion.
    // Note: the AppBar also has a "Cancel" TextButton, so disambiguate by
    // finding the one inside the AlertDialog.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete event?'), findsNothing);
    expect(h.result.value, isNull);

    // Now try again and confirm.
    await tester.tap(find.byKey(const ValueKey('delete-event-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Delete'),
      ),
    );
    await tester.pumpAndSettle();

    final saved = h.result.value!;
    expect(saved.eventsForDay(2), isEmpty);
  });
}
