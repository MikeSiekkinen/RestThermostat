import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/widgets/fan_widget.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool hasFan,
  required bool fanTimerActive,
  int fanTimerTimeout = 0,
  DateTime Function()? now,
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: FanWidget(
            hasFan: hasFan,
            fanTimerActive: fanTimerActive,
            fanTimerTimeout: fanTimerTimeout,
            now: now ?? DateTime.now,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('FanWidget.remainingFor / formatCountdown helpers', () {
    test('remainingFor returns the difference as a positive Duration', () {
      final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
      final timeout = now.add(const Duration(seconds: 43));
      final timeoutSeconds = timeout.millisecondsSinceEpoch ~/ 1000;
      expect(
        FanWidget.remainingFor(timeoutSeconds, now),
        const Duration(seconds: 43),
      );
    });

    test('remainingFor clamps a past timeout to Duration.zero', () {
      final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
      final past = now.subtract(const Duration(seconds: 30));
      final pastSeconds = past.millisecondsSinceEpoch ~/ 1000;
      expect(FanWidget.remainingFor(pastSeconds, now), Duration.zero);
    });

    test('formatCountdown renders M:SS with zero-padded seconds', () {
      expect(FanWidget.formatCountdown(const Duration(seconds: 43)), '0:43');
      expect(
        FanWidget.formatCountdown(const Duration(minutes: 12, seconds: 5)),
        '12:05',
      );
      expect(FanWidget.formatCountdown(Duration.zero), '0:00');
    });
  });

  group('FanWidget rendering', () {
    testWidgets('auto state renders "FAN AUTO" label', (tester) async {
      await _pump(tester, hasFan: true, fanTimerActive: false);
      expect(find.text('FAN AUTO'), findsOneWidget);
    });

    testWidgets('on-with-timer state renders "FAN ON • M:SS" countdown', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
      final timeout = now.add(const Duration(seconds: 43));
      await _pump(
        tester,
        hasFan: true,
        fanTimerActive: true,
        fanTimerTimeout: timeout.millisecondsSinceEpoch ~/ 1000,
        now: () => now,
      );
      expect(find.text('FAN ON • 0:43'), findsOneWidget);
    });

    testWidgets(
      'on-with-timer state with multi-minute remaining renders M:SS',
      (tester) async {
        final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
        final timeout = now.add(const Duration(minutes: 2, seconds: 7));
        await _pump(
          tester,
          hasFan: true,
          fanTimerActive: true,
          fanTimerTimeout: timeout.millisecondsSinceEpoch ~/ 1000,
          now: () => now,
        );
        expect(find.text('FAN ON • 2:07'), findsOneWidget);
      },
    );

    testWidgets('hidden when hasFan is false (no rendered output)', (
      tester,
    ) async {
      await _pump(tester, hasFan: false, fanTimerActive: false);
      expect(find.text('FAN AUTO'), findsNothing);
      expect(find.textContaining('FAN ON'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 52.0 && w.height == 52.0,
        ),
        findsNothing,
      );
    });

    testWidgets('renders a 52dp canvas when hasFan=true', (tester) async {
      await _pump(tester, hasFan: true, fanTimerActive: false);
      expect(
        find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 52.0 && w.height == 52.0,
        ),
        findsOneWidget,
      );
    });
  });

  group('FanWidget animation lifecycle', () {
    testWidgets(
      'reduced-motion holds the canvas without animating (pumpAndSettle '
      'returns rather than hanging)',
      (tester) async {
        final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
        final timeout = now.add(const Duration(seconds: 43));
        await _pump(
          tester,
          hasFan: true,
          fanTimerActive: true,
          fanTimerTimeout: timeout.millisecondsSinceEpoch ~/ 1000,
          now: () => now,
          disableAnimations: true,
        );
        await tester.pumpAndSettle();
        expect(find.text('FAN ON • 0:43'), findsOneWidget);
      },
    );

    testWidgets('pauses cleanly on AppLifecycleState.paused', (tester) async {
      final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
      final timeout = now.add(const Duration(seconds: 43));
      await _pump(
        tester,
        hasFan: true,
        fanTimerActive: true,
        fanTimerTimeout: timeout.millisecondsSinceEpoch ~/ 1000,
        now: () => now,
      );

      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('FAN ON • 0:43'), findsOneWidget);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('FAN ON • 0:43'), findsOneWidget);
    });
  });
}
