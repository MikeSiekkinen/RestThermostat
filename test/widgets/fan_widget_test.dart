import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/widgets/fan_widget.dart';

Device _device({
  required bool hasFan,
  required bool fanTimerActive,
  int fanTimerTimeout = 0,
}) {
  final raw = File('test/fixtures/devices_one.json').readAsStringSync();
  final fixture = jsonDecode(raw) as Map<String, dynamic>;
  final entry = Map<String, dynamic>.from(
    (fixture['devices'] as List).first as Map<String, dynamic>,
  );
  entry['fan_timer_active'] = fanTimerActive;
  entry['fan_timer_timeout'] = fanTimerTimeout;
  final caps = Map<String, dynamic>.from(
    entry['capabilities'] as Map<String, dynamic>,
  );
  caps['has_fan'] = hasFan;
  entry['capabilities'] = caps;
  return Device.fromJson(entry);
}

Future<void> _pump(
  WidgetTester tester,
  Device device, {
  DateTime Function()? now,
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: FanWidget(device: device, now: now ?? DateTime.now),
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
      final device = _device(hasFan: true, fanTimerActive: false);
      await _pump(tester, device);
      expect(find.text('FAN AUTO'), findsOneWidget);
    });

    testWidgets('on-with-timer state renders "FAN ON • M:SS" countdown', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
      final timeout = now.add(const Duration(seconds: 43));
      final device = _device(
        hasFan: true,
        fanTimerActive: true,
        fanTimerTimeout: timeout.millisecondsSinceEpoch ~/ 1000,
      );
      await _pump(tester, device, now: () => now);
      expect(find.text('FAN ON • 0:43'), findsOneWidget);
    });

    testWidgets(
      'on-with-timer state with multi-minute remaining renders M:SS',
      (tester) async {
        final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
        final timeout = now.add(const Duration(minutes: 2, seconds: 7));
        final device = _device(
          hasFan: true,
          fanTimerActive: true,
          fanTimerTimeout: timeout.millisecondsSinceEpoch ~/ 1000,
        );
        await _pump(tester, device, now: () => now);
        expect(find.text('FAN ON • 2:07'), findsOneWidget);
      },
    );

    testWidgets(
      'hidden when capabilities.has_fan is false (no rendered output)',
      (tester) async {
        final device = _device(hasFan: false, fanTimerActive: false);
        await _pump(tester, device);
        // No label, no canvas placeholder — widget shrinks to nothing.
        expect(find.text('FAN AUTO'), findsNothing);
        expect(find.textContaining('FAN ON'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 52.0 && w.height == 52.0,
          ),
          findsNothing,
        );
      },
    );

    testWidgets('renders a 52dp canvas when has_fan=true', (tester) async {
      final device = _device(hasFan: true, fanTimerActive: false);
      await _pump(tester, device);
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
        final device = _device(
          hasFan: true,
          fanTimerActive: true,
          fanTimerTimeout: timeout.millisecondsSinceEpoch ~/ 1000,
        );
        await _pump(tester, device, now: () => now, disableAnimations: true);
        // If the controller were still repeating, pumpAndSettle would hang
        // forever; reduced motion stops it.
        await tester.pumpAndSettle();
        expect(find.text('FAN ON • 0:43'), findsOneWidget);
      },
    );

    testWidgets('pauses cleanly on AppLifecycleState.paused', (tester) async {
      final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
      final timeout = now.add(const Duration(seconds: 43));
      final device = _device(
        hasFan: true,
        fanTimerActive: true,
        fanTimerTimeout: timeout.millisecondsSinceEpoch ~/ 1000,
      );
      await _pump(tester, device, now: () => now);

      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      // Should settle quickly once paused — no infinite animation.
      await tester.pumpAndSettle();
      expect(find.text('FAN ON • 0:43'), findsOneWidget);

      // Resume — animation restarts; we don't pumpAndSettle (would deadlock).
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('FAN ON • 0:43'), findsOneWidget);
    });
  });
}
