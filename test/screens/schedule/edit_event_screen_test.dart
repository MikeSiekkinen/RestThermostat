import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
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
  final Dio dio;
  final DioAdapter adapter;
  final ValueNotifier<Schedule?> result;

  /// Every `/command` body POSTed during the test, in order — lets tests
  /// assert the set_schedule_mode / set_schedule orchestration on the raw
  /// wire payloads.
  final List<Map<String, dynamic>> requests;

  _Harness({
    required this.widget,
    required this.dio,
    required this.adapter,
    required this.result,
    required this.requests,
  });
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
  DeviceMode deviceMode = DeviceMode.heat,
  String? storedScheduleMode,
  Locale locale = const Locale('en', 'GB'),
  bool use24Hour = false,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
  final adapter = DioAdapter(dio: dio);
  final result = ValueNotifier<Schedule?>(null);
  final requests = <Map<String, dynamic>>[];
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final data = options.data;
        if (data is Map<String, dynamic>) requests.add(data);
        handler.next(options);
      },
    ),
  );

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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en', 'GB'), Locale('en', 'US')],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open-edit-event'),
              onPressed: () async {
                final r = await Navigator.of(context).push<Schedule?>(
                  MaterialPageRoute(
                    builder: (routeContext) => MediaQuery(
                      data: MediaQuery.of(
                        routeContext,
                      ).copyWith(alwaysUse24HourFormat: use24Hour),
                      child: EditEventScreen(
                        serial: 'abc',
                        capabilities: capabilities,
                        temperatureScale: temperatureScale,
                        currentSchedule: schedule,
                        defaultDayIndex: defaultDayIndex,
                        deviceMode: deviceMode,
                        storedScheduleMode: storedScheduleMode,
                        existingEvent: existingEvent,
                      ),
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

  return _Harness(
    widget: widget,
    dio: dio,
    adapter: adapter,
    result: result,
    requests: requests,
  );
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

  // Since Issue #93, the event-type pills are constrained to the single type
  // matching the derived schedule mode — the device ignores a schedule whose
  // events contradict its schedule_mode, so a heat-mode device only offers
  // HEAT events even when it could also cool.
  testWidgets('mode selector offers only the derived type (heat device)', (
    tester,
  ) async {
    final h = _setup(schedule: _emptyWeek(), deviceMode: DeviceMode.heat);
    await tester.pumpWidget(h.widget);
    await _openEditor(tester);

    expect(find.byKey(const ValueKey('mode-pill-HEAT')), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-pill-COOL')), findsNothing);
    expect(find.byKey(const ValueKey('mode-pill-RANGE')), findsNothing);
  });

  testWidgets('mode selector offers only COOL for a cool-mode device', (
    tester,
  ) async {
    final h = _setup(schedule: _emptyWeek(), deviceMode: DeviceMode.cool);
    await tester.pumpWidget(h.widget);
    await _openEditor(tester);

    expect(find.byKey(const ValueKey('mode-pill-COOL')), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-pill-HEAT')), findsNothing);
    expect(find.byKey(const ValueKey('mode-pill-RANGE')), findsNothing);
  });

  testWidgets('heat-cool device preselects RANGE with dual temperature '
      'pickers', (tester) async {
    final h = _setup(schedule: _emptyWeek(), deviceMode: DeviceMode.heatCool);
    await tester.pumpWidget(h.widget);
    await _openEditor(tester);

    expect(find.byKey(const ValueKey('mode-pill-RANGE')), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-pill-HEAT')), findsNothing);
    expect(find.byKey(const ValueKey('mode-pill-COOL')), findsNothing);
    // Dual pickers shown without any tap — RANGE is the only valid type.
    expect(find.byKey(const ValueKey('temp-up-HEAT')), findsOneWidget);
    expect(find.byKey(const ValueKey('temp-up-COOL')), findsOneWidget);
  });

  testWidgets('off device falls back to the stored schedule_mode for the '
      'pill set', (tester) async {
    final h = _setup(
      schedule: _emptyWeek(),
      deviceMode: DeviceMode.off,
      storedScheduleMode: 'COOL',
    );
    await tester.pumpWidget(h.widget);
    await _openEditor(tester);

    expect(find.byKey(const ValueKey('mode-pill-COOL')), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-pill-HEAT')), findsNothing);
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

  group('time text inputs (Issue #96)', () {
    const hourField = ValueKey('time-hour-field');
    const minuteField = ValueKey('time-minute-field');
    const amPill = ValueKey('time-am-pill');
    const pmPill = ValueKey('time-pm-pill');

    /// The `time` values of every event in [day] of the set_schedule wire
    /// payload — pins the 12h→24h conversion at the raw JSON layer.
    List<int> wireTimes(List<Map<String, dynamic>> requests, int day) {
      final write = requests.lastWhere((r) => r['command'] == 'set_schedule');
      final days = (write['value'] as Map<String, dynamic>)['days'] as Map;
      final dayMap = (days['$day'] ?? const {}) as Map;
      return [
        for (final e in dayMap.values) ((e as Map)['time'] as num).toInt(),
      ];
    }

    testWidgets('12 AM serializes to time 0 on the wire', (tester) async {
      final h = _setup(schedule: _emptyWeek(), storedScheduleMode: 'HEAT');
      h.adapter.onPost(
        '/command',
        (s) => s.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      // 12-hour mode (harness default); the 7:00 seed is AM already.
      await tester.enterText(find.byKey(hourField), '12');
      await tester.enterText(find.byKey(minuteField), '00');
      await tester.tap(find.byKey(amPill));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(wireTimes(h.requests, 0), [0]);
    });

    testWidgets('12 PM serializes to time 43200 on the wire', (tester) async {
      final h = _setup(schedule: _emptyWeek(), storedScheduleMode: 'HEAT');
      h.adapter.onPost(
        '/command',
        (s) => s.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      await tester.enterText(find.byKey(hourField), '12');
      await tester.enterText(find.byKey(minuteField), '00');
      await tester.tap(find.byKey(pmPill));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(wireTimes(h.requests, 0), [43200]);
    });

    testWidgets('7:30 PM serializes to time 70200 on the wire', (tester) async {
      final h = _setup(schedule: _emptyWeek(), storedScheduleMode: 'HEAT');
      h.adapter.onPost(
        '/command',
        (s) => s.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      await tester.enterText(find.byKey(hourField), '7');
      await tester.enterText(find.byKey(minuteField), '30');
      await tester.tap(find.byKey(pmPill));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(wireTimes(h.requests, 0), [70200]);
    });

    testWidgets('24-hour mode hides AM/PM and takes 19:30 directly', (
      tester,
    ) async {
      final h = _setup(
        schedule: _emptyWeek(),
        storedScheduleMode: 'HEAT',
        use24Hour: true,
      );
      h.adapter.onPost(
        '/command',
        (s) => s.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      expect(find.byKey(amPill), findsNothing);
      expect(find.byKey(pmPill), findsNothing);

      await tester.enterText(find.byKey(hourField), '19');
      await tester.enterText(find.byKey(minuteField), '30');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(wireTimes(h.requests, 0), [70200]);
    });

    testWidgets('invalid minute disables Save with an inline error', (
      tester,
    ) async {
      final h = _setup(schedule: _emptyWeek(), storedScheduleMode: 'HEAT');

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      await tester.enterText(find.byKey(minuteField), '75');
      await tester.pumpAndSettle();

      expect(find.text('Enter minutes from 0–59'), findsOneWidget);
      final save = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(save.onPressed, isNull);
      expect(h.requests, isEmpty);

      // Correcting the field re-enables Save.
      await tester.enterText(find.byKey(minuteField), '45');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('empty hour disables Save', (tester) async {
      final h = _setup(schedule: _emptyWeek(), storedScheduleMode: 'HEAT');

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      await tester.enterText(find.byKey(hourField), '');
      await tester.pumpAndSettle();

      expect(find.text('Enter an hour from 1–12'), findsOneWidget);
      final save = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(save.onPressed, isNull);
      expect(h.requests, isEmpty);
    });

    testWidgets('editing a 19:30 event prefills 7/30 in 12-hour mode and '
        'round-trips unchanged', (tester) async {
      const existing = ScheduleEvent(
        dayIndex: 1,
        hour: 19,
        minute: 30,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      final h = _setup(
        schedule: _emptyWeek().addEvent(existing),
        existingEvent: existing,
        defaultDayIndex: 1,
        storedScheduleMode: 'HEAT',
      );
      h.adapter.onPost(
        '/command',
        (s) => s.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      expect(
        tester.widget<TextField>(find.byKey(hourField)).controller!.text,
        '7',
      );
      expect(
        tester.widget<TextField>(find.byKey(minuteField)).controller!.text,
        '30',
      );

      // Saving untouched keeps 19:30 — proves the PM half survived prefill.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(wireTimes(h.requests, 1), [70200]);
    });

    testWidgets('tapping AM on a prefilled PM event re-derives the wire time', (
      tester,
    ) async {
      const existing = ScheduleEvent(
        dayIndex: 1,
        hour: 19,
        minute: 30,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      final h = _setup(
        schedule: _emptyWeek().addEvent(existing),
        existingEvent: existing,
        defaultDayIndex: 1,
        storedScheduleMode: 'HEAT',
      );
      h.adapter.onPost(
        '/command',
        (s) => s.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      // Flip the prefilled 7:30 PM to AM without touching the text fields;
      // expect 07:30 → 27000 on the wire.
      await tester.tap(find.byKey(amPill));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(wireTimes(h.requests, 1), [27000]);
    });

    testWidgets('editing a 19:30 event prefills 19/30 in 24-hour mode', (
      tester,
    ) async {
      const existing = ScheduleEvent(
        dayIndex: 1,
        hour: 19,
        minute: 30,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      final h = _setup(
        schedule: _emptyWeek().addEvent(existing),
        existingEvent: existing,
        defaultDayIndex: 1,
        storedScheduleMode: 'HEAT',
        use24Hour: true,
      );

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      expect(
        tester.widget<TextField>(find.byKey(hourField)).controller!.text,
        '19',
      );
      expect(
        tester.widget<TextField>(find.byKey(minuteField)).controller!.text,
        '30',
      );
    });
  });

  group('set_schedule_mode orchestration (Issue #93)', () {
    testWidgets(
      'derived mode differing from stored issues set_schedule_mode then '
      'set_schedule',
      (tester) async {
        final h = _setup(
          schedule: _emptyWeek(),
          deviceMode: DeviceMode.cool,
          storedScheduleMode: null, // shared bucket unset — must be synced
        );
        h.adapter.onPost(
          '/command',
          (s) => s.reply(200, {'ok': true}),
          data: Matchers.any,
        );

        await tester.pumpWidget(h.widget);
        await _openEditor(tester);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(h.requests, hasLength(2));
        expect(h.requests[0], {
          'serial': 'abc',
          'command': 'set_schedule_mode',
          'value': 'COOL',
        });
        expect(h.requests[1]['command'], 'set_schedule');
        final value = h.requests[1]['value'] as Map<String, dynamic>;
        expect(value['schedule_mode'], 'COOL');
      },
    );

    testWidgets('derived mode agreeing with stored issues only set_schedule', (
      tester,
    ) async {
      final h = _setup(
        schedule: _emptyWeek(),
        deviceMode: DeviceMode.cool,
        storedScheduleMode: 'COOL',
      );
      h.adapter.onPost(
        '/command',
        (s) => s.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(h.requests, hasLength(1));
      expect(h.requests.single['command'], 'set_schedule');
      final value = h.requests.single['value'] as Map<String, dynamic>;
      expect(value['schedule_mode'], 'COOL');
    });

    testWidgets(
      'stale events from a previous mode are coerced — the payload never '
      'contradicts its schedule_mode',
      (tester) async {
        // Schedule read from the server still holds a HEAT event, but the
        // device now runs in cool mode.
        const stale = ScheduleEvent(
          dayIndex: 3,
          hour: 6,
          minute: 0,
          type: 'HEAT',
          targetTemp: 20.0,
        );
        final h = _setup(
          schedule: _emptyWeek().addEvent(stale),
          deviceMode: DeviceMode.cool,
          storedScheduleMode: 'COOL',
          defaultDayIndex: 0,
        );
        h.adapter.onPost(
          '/command',
          (s) => s.reply(200, {'ok': true}),
          data: Matchers.any,
        );

        await tester.pumpWidget(h.widget);
        await _openEditor(tester);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final value = h.requests.single['value'] as Map<String, dynamic>;
        expect(value['schedule_mode'], 'COOL');
        final days = value['days'] as Map<String, dynamic>;
        final allEvents = [
          for (final day in days.values)
            ...(day as Map<String, dynamic>).values,
        ];
        expect(allEvents, isNotEmpty);
        for (final event in allEvents) {
          expect((event as Map<String, dynamic>)['type'], 'COOL');
          expect(event['entry_type'], 'setpoint');
        }
      },
    );

    testWidgets('editing an event whose type predates the mode switch '
        'prefills the allowed type', (tester) async {
      const stale = ScheduleEvent(
        dayIndex: 1,
        hour: 7,
        minute: 0,
        type: 'HEAT',
        targetTemp: 20.0,
      );
      final h = _setup(
        schedule: _emptyWeek().addEvent(stale),
        existingEvent: stale,
        defaultDayIndex: 1,
        deviceMode: DeviceMode.cool,
        storedScheduleMode: 'COOL',
      );

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      // Only the COOL pill exists and the stepper carries the temp over.
      expect(find.byKey(const ValueKey('mode-pill-COOL')), findsOneWidget);
      expect(find.byKey(const ValueKey('mode-pill-HEAT')), findsNothing);
      expect(find.byKey(const ValueKey('temp-up-COOL')), findsOneWidget);
    });

    testWidgets('set_schedule failure after a successful mode change rolls the '
        'shared-bucket mode back', (tester) async {
      // Mode differs (stored HEAT, device cool) so the save sends
      // set_schedule_mode COOL first. The set_schedule that follows is
      // forced to fail with a non-transient 400; without a rollback the
      // device would be stranded with bucket mode COOL against its stored
      // HEAT schedule — which the firmware answers by ignoring the whole
      // schedule.
      final h = _setup(
        schedule: _emptyWeek(),
        deviceMode: DeviceMode.cool,
        storedScheduleMode: 'HEAT',
      );
      h.adapter.onPost(
        '/command',
        (s) => s.reply(200, {'ok': true}),
        data: Matchers.any,
      );
      // Registered after the harness's capture interceptor, so the body is
      // recorded before the rejection fires.
      h.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.data;
            if (data is Map<String, dynamic> &&
                data['command'] == 'set_schedule') {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(requestOptions: options, statusCode: 400),
                ),
              );
              return;
            }
            handler.next(options);
          },
        ),
      );

      await tester.pumpWidget(h.widget);
      await _openEditor(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final commands = [for (final r in h.requests) r['command']];
      expect(commands, [
        'set_schedule_mode', // sync to the derived mode
        'set_schedule', // fails with 400 (no retry on 4xx)
        'set_schedule_mode', // best-effort rollback to the stored mode
      ]);
      expect(h.requests.first['value'], 'COOL');
      expect(h.requests.last['value'], 'HEAT');
    });
  });

  group('temperature keypad (Issue #111)', () {
    const tempValue = ValueKey('temp-value-HEAT');
    const entryField = ValueKey('temp-entry-field');
    const confirm = ValueKey('temp-entry-confirm');

    const heatEvent = ScheduleEvent(
      dayIndex: 1,
      hour: 7,
      minute: 0,
      type: 'HEAT',
      targetTemp: 20.0,
    );

    _Harness editHarness({String temperatureScale = 'C'}) => _setup(
      schedule: _emptyWeek().addEvent(heatEvent),
      existingEvent: heatEvent,
      defaultDayIndex: 1,
      temperatureScale: temperatureScale,
    );

    testWidgets('tapping Set commits the value without throwing', (
      tester,
    ) async {
      final h = editHarness();
      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      // Open the keypad, type a new value, confirm with Set.
      await tester.tap(find.byKey(tempValue));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(entryField), '22');
      await tester.tap(find.byKey(confirm));
      await tester.pumpAndSettle();

      // Regression: the dialog-local controller disposal used to race the route
      // teardown, throwing `_dependents.isEmpty` (framework.dart:6268).
      expect(tester.takeException(), isNull);
      // The stepper display reflects the entered value.
      expect(find.byKey(tempValue), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(tempValue), matching: find.text('22°C')),
        findsOneWidget,
      );
    });

    testWidgets('keyboard Done (onSubmitted) commits like Set', (tester) async {
      final h = editHarness();
      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      await tester.tap(find.byKey(tempValue));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(entryField), '25');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(of: find.byKey(tempValue), matching: find.text('25°C')),
        findsOneWidget,
      );
    });

    testWidgets('Cancel dismisses without committing', (tester) async {
      final h = editHarness();
      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      await tester.tap(find.byKey(tempValue));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(entryField), '28');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Unchanged from the seeded 20°C.
      expect(
        find.descendant(of: find.byKey(tempValue), matching: find.text('20°C')),
        findsOneWidget,
      );
    });

    testWidgets('°F input converts back to Celsius on commit', (tester) async {
      final h = editHarness(temperatureScale: 'F');
      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      // The 20°C seed displays as 68°F; enter 70°F.
      expect(
        find.descendant(of: find.byKey(tempValue), matching: find.text('68°F')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(tempValue));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(entryField), '70');
      await tester.tap(find.byKey(confirm));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 70°F round-trips through Celsius storage back to a 70°F display.
      expect(
        find.descendant(of: find.byKey(tempValue), matching: find.text('70°F')),
        findsOneWidget,
      );
    });

    testWidgets('out-of-range input clamps to the max setpoint', (
      tester,
    ) async {
      final h = editHarness();
      await tester.pumpWidget(h.widget);
      await _openEditor(tester);

      // Enter well above the 32°C ceiling; commit should clamp it.
      await tester.tap(find.byKey(tempValue));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(entryField), '99');
      await tester.tap(find.byKey(confirm));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(of: find.byKey(tempValue), matching: find.text('32°C')),
        findsOneWidget,
      );
    });
  });
}
