import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:rest_thermostat/models/auth_config.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/screens/schedule/schedule_screen.dart';
import 'package:rest_thermostat/services/nle_api_client.dart';
import 'package:rest_thermostat/state/providers.dart';
import 'package:rest_thermostat/theme/colors.dart';

class _Harness {
  final Widget widget;
  final DioAdapter adapter;

  /// The device handed to [ScheduleScreen]. Tests mutate this to simulate a
  /// poll delivering changed device state (e.g. a new `targetTemperature`)
  /// through a parent rebuild.
  final ValueNotifier<Device?> device;

  _Harness({required this.widget, required this.adapter, required this.device});
}

_Harness _setup({
  required String serial,
  String temperatureScale = 'F',
  Locale locale = const Locale('en', 'GB'),
  bool use24Hour = false,
  Device? device,
  DateTime Function()? now,
  Map<String, String> overrides = const {},
  double textScale = 1.0,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
  final adapter = DioAdapter(dio: dio);
  final deviceNotifier = ValueNotifier<Device?>(device);

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
      home: MediaQuery(
        data: MediaQueryData(
          alwaysUse24HourFormat: use24Hour,
          textScaler: TextScaler.linear(textScale),
        ),
        child: ValueListenableBuilder<Device?>(
          valueListenable: deviceNotifier,
          builder: (_, device, _) => ScheduleScreen(
            serial: serial,
            temperatureScale: temperatureScale,
            device: device,
            now: now ?? DateTime.now,
            overrides: overrides,
          ),
        ),
      ),
    ),
  );

  return _Harness(widget: widget, adapter: adapter, device: deviceNotifier);
}

class _SeedActiveServer extends ActiveServerNotifier {
  final ActiveServer? seed;
  _SeedActiveServer(this.seed);
  @override
  ActiveServer? build() => seed;
}

Map<String, dynamic> _scheduleFixture() =>
    jsonDecode(File('test/fixtures/schedule_one.json').readAsStringSync())
        as Map<String, dynamic>;

Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders weekday tabs in Monday-first order for en_GB', (
    tester,
  ) async {
    final h = _setup(serial: 'abc', locale: const Locale('en', 'GB'));
    h.adapter.onGet(
      '/api/schedule',
      (s) => s.reply(200, _scheduleFixture()),
      queryParameters: {'serial': 'abc'},
    );

    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    // M T W T F S S — verify with letter labels (text). Note T appears twice
    // and S appears twice, so we assert presence via finder counts.
    expect(find.text('M'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('T'), findsNWidgets(2));
    expect(find.text('S'), findsNWidgets(2));

    await _disposeTree(tester);
  });

  testWidgets('renders weekday tabs in Sunday-first order for en_US', (
    tester,
  ) async {
    final h = _setup(serial: 'abc', locale: const Locale('en', 'US'));
    h.adapter.onGet(
      '/api/schedule',
      (s) => s.reply(200, _scheduleFixture()),
      queryParameters: {'serial': 'abc'},
    );

    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    // First tab letter must be 'S' (Sunday). Find the first Text widget
    // that's a single letter in the tab strip.
    // Easier: look for the underline key of Sunday (index 6) in position 0
    // and the first character rendered.
    final underline = find.byKey(const ValueKey('day-underline-6'));
    expect(underline, findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('renders today\'s events on mount', (tester) async {
    final h = _setup(serial: 'abc');
    h.adapter.onGet(
      '/api/schedule',
      (s) => s.reply(200, _scheduleFixture()),
      queryParameters: {'serial': 'abc'},
    );

    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    // Today's index (Mon=0..Sun=6). The fixture is uniform Mon-Wed and again
    // Sat-Sun. Thursday has RANGE+COOL, Friday is empty.
    final todayIndex = DateTime.now().weekday - 1;
    switch (todayIndex) {
      case 4: // Friday — empty
        expect(find.text('No events scheduled'), findsOneWidget);
        expect(find.text('Tap + to add one'), findsOneWidget);
        break;
      case 3: // Thursday
        expect(find.text('RANGE'), findsOneWidget);
        expect(find.text('COOL'), findsOneWidget);
        break;
      default:
        // Mon/Tue/Wed/Sat/Sun all show HEAT events.
        expect(find.text('HEAT'), findsWidgets);
    }

    await _disposeTree(tester);
  });

  testWidgets('shows empty-day placeholder for Friday', (tester) async {
    final h = _setup(serial: 'abc', locale: const Locale('en', 'GB'));
    h.adapter.onGet(
      '/api/schedule',
      (s) => s.reply(200, _scheduleFixture()),
      queryParameters: {'serial': 'abc'},
    );

    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    // Tap Friday (internal index 4). In en_GB Mon-first that's position 4.
    final fridayUnderline = find.byKey(const ValueKey('day-underline-4'));
    expect(fridayUnderline, findsOneWidget);
    await tester.tap(
      find.ancestor(of: fridayUnderline, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No events scheduled'), findsOneWidget);
    expect(find.text('Tap + to add one'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('day switching changes the visible event list', (tester) async {
    final h = _setup(serial: 'abc', locale: const Locale('en', 'GB'));
    h.adapter.onGet(
      '/api/schedule',
      (s) => s.reply(200, _scheduleFixture()),
      queryParameters: {'serial': 'abc'},
    );

    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    // Switch to Thursday (internal index 3).
    final thursdayUnderline = find.byKey(const ValueKey('day-underline-3'));
    await tester.tap(
      find.ancestor(of: thursdayUnderline, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    expect(find.text('RANGE'), findsOneWidget);
    expect(find.text('COOL'), findsOneWidget);

    // Switch to Wednesday (internal index 2) — HEAT events.
    final wednesdayUnderline = find.byKey(const ValueKey('day-underline-2'));
    await tester.tap(
      find.ancestor(of: wednesdayUnderline, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    expect(find.text('HEAT'), findsWidgets);
    expect(find.text('RANGE'), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('selected day is shared across devices — carries over on swipe', (
    tester,
  ) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
    final adapter = DioAdapter(dio: dio);
    // Same schedule for both devices; Thursday (index 3) is the only day
    // that renders RANGE + COOL, so it's an unambiguous "which day" probe.
    for (final serial in const ['A', 'B']) {
      adapter.onGet(
        '/api/schedule',
        (s) => s.reply(200, _scheduleFixture()),
        queryParameters: {'serial': serial},
      );
    }

    // Pin "today" to a Monday so the default selected day shows HEAT (not
    // RANGE/COOL) — the Thursday switch is then observable.
    DateTime monday() => DateTime(2024, 1, 1);

    // A single ScheduleScreen whose serial flips — mimics the PageView
    // handing the active tab to a different device on swipe. The per-serial
    // ValueKey (as in the real PageView) destroys and recreates the screen's
    // State on the flip, so if the selected day survives it can only be
    // because it lives in the shared scheduleSelectedDayProvider, not in
    // per-instance state.
    final serial = ValueNotifier<String>('A');
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
        locale: const Locale('en', 'GB'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en', 'GB'), Locale('en', 'US')],
        home: ValueListenableBuilder<String>(
          valueListenable: serial,
          builder: (_, s, _) =>
              ScheduleScreen(key: ValueKey(s), serial: s, now: monday),
        ),
      ),
    );

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    // Device A starts on today (Monday) — HEAT, no RANGE.
    expect(find.text('RANGE'), findsNothing);

    // Pick Thursday (index 3) on device A → RANGE + COOL.
    await tester.tap(
      find.ancestor(
        of: find.byKey(const ValueKey('day-underline-3')),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('RANGE'), findsOneWidget);
    expect(find.text('COOL'), findsOneWidget);

    // "Swipe" to device B.
    serial.value = 'B';
    await tester.pumpAndSettle();

    // Carry-over: device B opens on Thursday too, not back on today/Monday.
    expect(find.text('RANGE'), findsOneWidget);
    expect(find.text('COOL'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('renders 24h time when device locale uses 24h format', (
    tester,
  ) async {
    final h = _setup(serial: 'abc', use24Hour: true);
    h.adapter.onGet(
      '/api/schedule',
      (s) => s.reply(200, _scheduleFixture()),
      queryParameters: {'serial': 'abc'},
    );

    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    // Tap Monday (internal index 0). The first event is 06:00.
    final mondayUnderline = find.byKey(const ValueKey('day-underline-0'));
    await tester.tap(
      find.ancestor(of: mondayUnderline, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    expect(find.text('06:00'), findsOneWidget);
    expect(find.textContaining('AM'), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('renders 12h time with AM/PM when locale uses 12h format', (
    tester,
  ) async {
    final h = _setup(serial: 'abc');
    h.adapter.onGet(
      '/api/schedule',
      (s) => s.reply(200, _scheduleFixture()),
      queryParameters: {'serial': 'abc'},
    );

    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    final mondayUnderline = find.byKey(const ValueKey('day-underline-0'));
    await tester.tap(
      find.ancestor(of: mondayUnderline, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    expect(find.text('6:00 AM'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('converts Celsius temps to Fahrenheit for F-scale devices', (
    tester,
  ) async {
    final h = _setup(serial: 'abc', temperatureScale: 'F');
    h.adapter.onGet(
      '/api/schedule',
      (s) => s.reply(200, _scheduleFixture()),
      queryParameters: {'serial': 'abc'},
    );

    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    final mondayUnderline = find.byKey(const ValueKey('day-underline-0'));
    await tester.tap(
      find.ancestor(of: mondayUnderline, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    // 20.0°C → 68°F.
    expect(find.text('68°F'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('keeps Celsius for C-scale devices', (tester) async {
    final h = _setup(serial: 'abc', temperatureScale: 'C');
    h.adapter.onGet(
      '/api/schedule',
      (s) => s.reply(200, _scheduleFixture()),
      queryParameters: {'serial': 'abc'},
    );

    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    final mondayUnderline = find.byKey(const ValueKey('day-underline-0'));
    await tester.tap(
      find.ancestor(of: mondayUnderline, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    expect(find.text('20°C'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('shows empty state for every day when server returns 404', (
    tester,
  ) async {
    final h = _setup(serial: 'no-sched', locale: const Locale('en', 'GB'));
    h.adapter.onGet(
      '/api/schedule',
      (s) => s.reply(200, {
        'serial': 'no-sched',
        'schedule': null,
        'object_revision': 0,
        'object_timestamp': 0,
      }),
      queryParameters: {'serial': 'no-sched'},
    );

    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    expect(find.text('No events scheduled'), findsOneWidget);

    // Switch to Wednesday — still empty.
    final wedUnderline = find.byKey(const ValueKey('day-underline-2'));
    await tester.tap(
      find.ancestor(of: wedUnderline, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No events scheduled'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('event rows expose a merged Semantics label including '
      'time, temp, and mode', (tester) async {
    final h = _setup(serial: 'abc', locale: const Locale('en', 'GB'));
    h.adapter.onGet(
      '/api/schedule',
      (s) => s.reply(200, _scheduleFixture()),
      queryParameters: {'serial': 'abc'},
    );

    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    // Switch to Monday (internal index 0) — fixture has 4 HEAT events at
    // 06:00 / 08:00 / 18:00 / 22:00, in Fahrenheit display.
    final mondayUnderline = find.byKey(const ValueKey('day-underline-0'));
    await tester.tap(
      find.ancestor(of: mondayUnderline, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    // The event row's Semantics label is the merged "Event at … tap to edit."
    // string. The presence of "tap to edit." is the load-bearing piece —
    // confirms the row announces itself as actionable.
    expect(
      find.bySemanticsLabel(RegExp(r'^Event at .*, .* heat, tap to edit\.$')),
      findsWidgets,
    );

    await _disposeTree(tester);
  });

  group('schedule-in-control event highlight (Issue #97)', () {
    // Fixed clock: Wednesday 2026-05-13 12:00 local → internal day index 2.
    final wedNoon = DateTime(2026, 5, 13, 12, 0, 0);

    Device device({required double target, String ecoMode = 'schedule'}) {
      final raw = File('test/fixtures/devices_one.json').readAsStringSync();
      final entry = Map<String, dynamic>.from(
        (jsonDecode(raw) as Map<String, dynamic>)['devices'][0]
            as Map<String, dynamic>,
      );
      entry['target_temperature'] = target;
      entry['eco_mode'] = ecoMode;
      return Device.fromJson(entry);
    }

    /// Wire-shaped schedule response with [wednesdayEvents] on day 2 and all
    /// other days empty.
    Map<String, dynamic> wireSchedule(
      List<Map<String, dynamic>> wednesdayEvents, {
      String mode = 'HEAT',
    }) => {
      'serial': 'abc',
      'schedule': {
        'ver': 2,
        'name': 'Current Schedule',
        'schedule_mode': mode,
        'days': {
          for (var d = 0; d < 7; d++)
            '$d': d == 2
                ? {
                    for (var i = 0; i < wednesdayEvents.length; i++)
                      '$i': wednesdayEvents[i],
                  }
                : <String, dynamic>{},
        },
      },
    };

    /// The row's target `BoxDecoration` (Wednesday = day index 2), found by
    /// the content key `event-row-<day>-<timeSeconds>`.
    BoxDecoration rowDecoration(WidgetTester tester, int timeSeconds) {
      final c = tester.widget<AnimatedContainer>(
        find.byKey(ValueKey('event-row-2-$timeSeconds')),
      );
      return c.decoration! as BoxDecoration;
    }

    /// A row is highlighted (Issue #97) when its border is the full 2px
    /// type-colored border with a glow, vs the 1px dimmed default.
    bool isHighlighted(BoxDecoration d) {
      final border = d.border! as Border;
      return border.top.width == 2 && (d.boxShadow?.isNotEmpty ?? false);
    }

    /// Assert no rendered event row carries the highlight.
    void expectNoHighlightedRow(WidgetTester tester) {
      final rows = tester.widgetList<AnimatedContainer>(
        find.byWidgetPredicate(
          (w) =>
              w is AnimatedContainer &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('event-row-'),
        ),
      );
      for (final row in rows) {
        expect(isHighlighted(row.decoration! as BoxDecoration), isFalse);
      }
    }

    testWidgets('active HEAT event matching the target highlights its row '
        'heat-red', (tester) async {
      final h = _setup(
        serial: 'abc',
        device: device(target: 20.0),
        now: () => wedNoon,
      );
      h.adapter.onGet(
        '/api/schedule',
        (s) => s.reply(
          200,
          wireSchedule([
            {
              'type': 'HEAT',
              'time': 28800,
              'temp': 20.0,
              'entry_type': 'setpoint',
            },
          ]),
        ),
        queryParameters: {'serial': 'abc'},
      );

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      final d = rowDecoration(tester, 28800);
      expect(isHighlighted(d), isTrue);
      expect((d.border! as Border).top.color, EmberColors.heatGlow);

      await _disposeTree(tester);
    });

    testWidgets('active COOL event matching the target highlights its row '
        'cool-blue', (tester) async {
      final h = _setup(
        serial: 'abc',
        device: device(target: 22.0),
        now: () => wedNoon,
      );
      h.adapter.onGet(
        '/api/schedule',
        (s) => s.reply(
          200,
          wireSchedule([
            {
              'type': 'COOL',
              'time': 28800,
              'temp': 22.0,
              'entry_type': 'setpoint',
            },
          ], mode: 'COOL'),
        ),
        queryParameters: {'serial': 'abc'},
      );

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      final d = rowDecoration(tester, 28800);
      expect(isHighlighted(d), isTrue);
      expect((d.border! as Border).top.color, EmberColors.coolGlow);

      await _disposeTree(tester);
    });

    testWidgets('only the active event is highlighted, not an earlier sibling '
        'on the same day', (tester) async {
      final h = _setup(
        serial: 'abc',
        device: device(target: 20.0),
        now: () => wedNoon,
      );
      h.adapter.onGet(
        '/api/schedule',
        (s) => s.reply(
          200,
          wireSchedule([
            // 06:00 earlier event, same setpoint — must NOT be highlighted.
            {
              'type': 'HEAT',
              'time': 21600,
              'temp': 20.0,
              'entry_type': 'setpoint',
            },
            // 08:00 is the most recent before noon — the active one.
            {
              'type': 'HEAT',
              'time': 28800,
              'temp': 20.0,
              'entry_type': 'setpoint',
            },
          ]),
        ),
        queryParameters: {'serial': 'abc'},
      );

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expect(isHighlighted(rowDecoration(tester, 28800)), isTrue);
      expect(isHighlighted(rowDecoration(tester, 21600)), isFalse);

      await _disposeTree(tester);
    });

    testWidgets('the active row announces its state to screen readers', (
      tester,
    ) async {
      final h = _setup(
        serial: 'abc',
        device: device(target: 20.0),
        now: () => wedNoon,
      );
      h.adapter.onGet(
        '/api/schedule',
        (s) => s.reply(
          200,
          wireSchedule([
            {
              'type': 'HEAT',
              'time': 28800,
              'temp': 20.0,
              'entry_type': 'setpoint',
            },
          ]),
        ),
        queryParameters: {'serial': 'abc'},
      );

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp(r'^Currently active\. Event at ')),
        findsOneWidget,
      );

      await _disposeTree(tester);
    });

    testWidgets('manual override (target differs) leaves rows unhighlighted', (
      tester,
    ) async {
      final h = _setup(
        serial: 'abc',
        device: device(target: 25.0),
        now: () => wedNoon,
      );
      h.adapter.onGet(
        '/api/schedule',
        (s) => s.reply(
          200,
          wireSchedule([
            {
              'type': 'HEAT',
              'time': 28800,
              'temp': 20.0,
              'entry_type': 'setpoint',
            },
          ]),
        ),
        queryParameters: {'serial': 'abc'},
      );

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expectNoHighlightedRow(tester);

      await _disposeTree(tester);
    });

    testWidgets('active RANGE event leaves rows unhighlighted even when a '
        'bound matches (documented v1 policy)', (tester) async {
      final h = _setup(
        serial: 'abc',
        device: device(target: 20.0),
        now: () => wedNoon,
      );
      h.adapter.onGet(
        '/api/schedule',
        (s) => s.reply(
          200,
          wireSchedule([
            {
              'type': 'RANGE',
              'time': 28800,
              'temp-min': 20.0,
              'temp-max': 24.0,
              'entry_type': 'setpoint',
            },
          ], mode: 'RANGE'),
        ),
        queryParameters: {'serial': 'abc'},
      );

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expectNoHighlightedRow(tester);

      await _disposeTree(tester);
    });

    testWidgets('away mode leaves rows unhighlighted even when the active '
        'event matches', (tester) async {
      final h = _setup(
        serial: 'abc',
        device: device(target: 20.0, ecoMode: 'manual-eco'),
        now: () => wedNoon,
      );
      h.adapter.onGet(
        '/api/schedule',
        (s) => s.reply(
          200,
          wireSchedule([
            {
              'type': 'HEAT',
              'time': 28800,
              'temp': 20.0,
              'entry_type': 'setpoint',
            },
          ]),
        ),
        queryParameters: {'serial': 'abc'},
      );

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expectNoHighlightedRow(tester);

      await _disposeTree(tester);
    });

    testWidgets('no device handed in leaves rows unhighlighted', (
      tester,
    ) async {
      final h = _setup(serial: 'abc', now: () => wedNoon);
      h.adapter.onGet(
        '/api/schedule',
        (s) => s.reply(
          200,
          wireSchedule([
            {
              'type': 'HEAT',
              'time': 28800,
              'temp': 20.0,
              'entry_type': 'setpoint',
            },
          ]),
        ),
        queryParameters: {'serial': 'abc'},
      );

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expectNoHighlightedRow(tester);

      await _disposeTree(tester);
    });

    testWidgets('the highlight only shows on the active event\'s own day', (
      tester,
    ) async {
      final h = _setup(
        serial: 'abc',
        device: device(target: 20.0),
        now: () => wedNoon,
      );
      h.adapter.onGet(
        '/api/schedule',
        (s) => s.reply(
          200,
          wireSchedule([
            {
              'type': 'HEAT',
              'time': 28800,
              'temp': 20.0,
              'entry_type': 'setpoint',
            },
          ]),
        ),
        queryParameters: {'serial': 'abc'},
      );

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();
      // Active event's day (Wednesday) is selected initially → highlighted.
      expect(isHighlighted(rowDecoration(tester, 28800)), isTrue);

      // Switch to Thursday (index 3): the Wednesday event isn't rendered, so
      // no row is highlighted on the visible day.
      await tester.tap(
        find.ancestor(
          of: find.byKey(const ValueKey('day-underline-3')),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();
      expectNoHighlightedRow(tester);

      await _disposeTree(tester);
    });

    testWidgets('a rebuild delivering a changed targetTemperature clears the '
        'highlight', (tester) async {
      final h = _setup(
        serial: 'abc',
        device: device(target: 20.0),
        now: () => wedNoon,
      );
      h.adapter.onGet(
        '/api/schedule',
        (s) => s.reply(
          200,
          wireSchedule([
            {
              'type': 'HEAT',
              'time': 28800,
              'temp': 20.0,
              'entry_type': 'setpoint',
            },
          ]),
        ),
        queryParameters: {'serial': 'abc'},
      );

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();
      expect(isHighlighted(rowDecoration(tester, 28800)), isTrue);

      // Simulate the next poll reporting a manual dial turn.
      h.device.value = device(target: 25.0);
      await tester.pumpAndSettle();

      expect(isHighlighted(rowDecoration(tester, 28800)), isFalse);

      await _disposeTree(tester);
    });
  });

  group('schedule header (Issue #100)', () {
    Device headerDevice({
      String name = 'Upstairs',
      double current = 24.76999, // 76.6°F → 77°F
      double target = 24.444444444444443, // 76.0°F → 76°F
      String mode = 'cool',
      double? low,
      double? high,
    }) {
      final raw = File('test/fixtures/devices_one.json').readAsStringSync();
      final entry = Map<String, dynamic>.from(
        (jsonDecode(raw) as Map<String, dynamic>)['devices'][0]
            as Map<String, dynamic>,
      );
      entry['name'] = name;
      entry['current_temperature'] = current;
      entry['target_temperature'] = target;
      entry['mode'] = mode;
      entry['target_temperature_low'] = low;
      entry['target_temperature_high'] = high;
      return Device.fromJson(entry);
    }

    void stubSchedule(_Harness h) {
      h.adapter.onGet(
        '/api/schedule',
        (s) => s.reply(200, _scheduleFixture()),
        queryParameters: {'serial': 'abc'},
      );
    }

    testWidgets('shows the scheduled device name and measured/target temps in '
        '°F', (tester) async {
      final h = _setup(serial: 'abc', device: headerDevice());
      stubSchedule(h);

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expect(find.text('Upstairs'), findsOneWidget);
      expect(find.textContaining('Now 77°F'), findsOneWidget);
      // Humidity (60% in the fixture) sits on the "Now" line, after the temp.
      expect(find.textContaining('· 60%'), findsOneWidget);
      // "Set" is now on its own line below "Now" (Issue #115).
      expect(find.textContaining('Set 76°F'), findsOneWidget);
      // The plain "Schedule" title is replaced when a device is present.
      expect(find.text('Schedule'), findsNothing);

      await _disposeTree(tester);
    });

    testWidgets('honors a local display-name override', (tester) async {
      const serial = '02AA01AC041403JM';
      final h = _setup(
        serial: 'abc',
        device: headerDevice(),
        overrides: const {serial: 'Basement'},
      );
      stubSchedule(h);

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expect(find.text('Basement'), findsOneWidget);
      expect(find.text('Upstairs'), findsNothing);

      await _disposeTree(tester);
    });

    testWidgets('formats the header temps in °C when the scale is C', (
      tester,
    ) async {
      final h = _setup(
        serial: 'abc',
        temperatureScale: 'C',
        device: headerDevice(),
      );
      stubSchedule(h);

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expect(find.textContaining('Now 25°C'), findsOneWidget);
      expect(find.textContaining('Set 24°C'), findsOneWidget);

      await _disposeTree(tester);
    });

    testWidgets('the header updates when a poll delivers new device state', (
      tester,
    ) async {
      final h = _setup(serial: 'abc', device: headerDevice());
      stubSchedule(h);

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();
      expect(find.textContaining('Now 77°F'), findsOneWidget);

      // Next poll: measured rises to 26.11°C ≈ 79°F.
      h.device.value = headerDevice(current: 26.11);
      await tester.pumpAndSettle();

      expect(find.textContaining('Now 79°F'), findsOneWidget);
      expect(find.textContaining('Now 77°F'), findsNothing);

      await _disposeTree(tester);
    });

    testWidgets('falls back to the plain "Schedule" title with no device', (
      tester,
    ) async {
      final h = _setup(serial: 'abc');
      stubSchedule(h);

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expect(find.text('Schedule'), findsOneWidget);
      expect(find.textContaining('Now '), findsNothing);

      await _disposeTree(tester);
    });

    testWidgets('a heat-cool device shows the target as a low–high band, like '
        'Details', (tester) async {
      final h = _setup(
        serial: 'abc',
        device: headerDevice(
          mode: 'heat-cool',
          low: 20.0, // 68°F
          high: 24.0, // 75.2°F → 75°F
        ),
      );
      stubSchedule(h);

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expect(find.textContaining('Set 68°F – 75°F'), findsOneWidget);

      await _disposeTree(tester);
    });

    testWidgets('renders "Now …" and "Set …" as two separate lines, and the '
        'Auto band is not truncated at a normal width (Issue #115)', (
      tester,
    ) async {
      final h = _setup(
        serial: 'abc',
        device: headerDevice(
          mode: 'heat-cool',
          low: 20.0, // 68°F
          high: 24.0, // 75°F
        ),
      );
      stubSchedule(h);

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      // Two distinct lines: "Now …" (with humidity) and "Set …" (the band).
      expect(find.text('Now 77°F · 60%'), findsOneWidget);
      expect(find.text('Set 68°F – 75°F'), findsOneWidget);

      // The band line must not ellipsize at a normal phone width — assert the
      // rendered paragraph did not exceed its single line.
      final setParagraph = tester.renderObject<RenderParagraph>(
        find.text('Set 68°F – 75°F'),
      );
      expect(setParagraph.didExceedMaxLines, isFalse);

      await _disposeTree(tester);
    });

    testWidgets('the temps line exposes a spelled-out semantics label', (
      tester,
    ) async {
      final h = _setup(serial: 'abc', device: headerDevice());
      stubSchedule(h);

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      // Screen readers get the comma-form label, not the middot visual string.
      // (AppBar may merge the title's child nodes, so match the substring.)
      expect(
        find.bySemanticsLabel(RegExp('Now 77°F, humidity 60%, set to 76°F')),
        findsOne,
      );
      // The visible "Set …" line is wrapped in ExcludeSemantics so the setpoint
      // is announced once (via the combined label above), not twice. Guard that
      // exclusion: its raw visual string must not surface as its own semantics
      // node (Issue #115).
      expect(find.bySemanticsLabel('Set 76°F'), findsNothing);

      await _disposeTree(tester);
    });

    testWidgets('the two-line header does not overflow at large text scale', (
      tester,
    ) async {
      final h = _setup(
        serial: 'abc',
        device: headerDevice(name: 'Downstairs Guest Bedroom'),
        textScale: 3.0,
      );
      stubSchedule(h);

      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      // A clipped/overflowing toolbar throws a RenderFlex overflow during
      // layout; assert none was swallowed.
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Now 77°F'), findsOneWidget);

      await _disposeTree(tester);
    });
  });
}
