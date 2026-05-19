import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rest_thermostat/state/connection_status.dart';
import 'package:rest_thermostat/state/device_state_source.dart';
import 'package:rest_thermostat/state/devices_snapshot.dart';
import 'package:rest_thermostat/state/providers.dart';
import 'package:rest_thermostat/widgets/stale_state_pill.dart';

class _StubSource implements DeviceStateSource {
  final _snapshots = StreamController<DevicesSnapshot>.broadcast();
  final _statuses = StreamController<ConnectionStatus>.broadcast();
  int refreshCount = 0;

  void push(ConnectionStatus status) => _statuses.add(status);

  @override
  Stream<DevicesSnapshot> watch() => _snapshots.stream;
  @override
  Stream<ConnectionStatus> watchStatus() => _statuses.stream;
  @override
  void refresh() => refreshCount++;
  @override
  bool get isStale => false;
  @override
  Future<void> dispose() async {
    await _snapshots.close();
    await _statuses.close();
  }
}

Future<_StubSource> _pump(
  WidgetTester tester, {
  DateTime Function()? now,
}) async {
  final source = _StubSource();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [deviceStateSourceProvider.overrideWith((_) => source)],
      child: MaterialApp(
        home: Scaffold(body: StaleStatePill(now: now ?? DateTime.now)),
      ),
    ),
  );
  return source;
}

void main() {
  testWidgets('renders nothing while connection is fresh', (tester) async {
    final source = await _pump(tester);
    source.push(
      ConnectionStatus(
        isFresh: true,
        isReconnecting: false,
        isRateLimited: false,
        rateLimitedUntil: null,
        lastSuccessAt: DateTime.now(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Reconnecting…'), findsNothing);
    expect(find.text('Server busy — retrying'), findsNothing);
    expect(find.textContaining('Last updated'), findsNothing);
  });

  testWidgets('shows stale + relative time + retry button when stale', (
    tester,
  ) async {
    final fixedNow = DateTime.utc(2026, 5, 19, 12, 0, 0);
    final source = await _pump(tester, now: () => fixedNow);
    source.push(
      ConnectionStatus(
        isFresh: false,
        isReconnecting: false,
        isRateLimited: false,
        rateLimitedUntil: null,
        lastSuccessAt: fixedNow.subtract(const Duration(minutes: 3)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Last updated 3 min ago'), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);
  });

  testWidgets('tapping RETRY calls source.refresh', (tester) async {
    final source = await _pump(tester);
    source.push(
      ConnectionStatus(
        isFresh: false,
        isReconnecting: false,
        isRateLimited: false,
        rateLimitedUntil: null,
        lastSuccessAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('RETRY'));
    await tester.pump();
    expect(source.refreshCount, 1);
  });

  testWidgets('shows "Reconnecting…" with spinner during active retry', (
    tester,
  ) async {
    final source = await _pump(tester);
    source.push(
      ConnectionStatus(
        isFresh: false,
        isReconnecting: true,
        isRateLimited: false,
        rateLimitedUntil: null,
        lastSuccessAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows "Server busy — retrying" with spinner when rate-limited', (
    tester,
  ) async {
    final source = await _pump(tester);
    source.push(
      ConnectionStatus(
        isFresh: false,
        isReconnecting: false,
        isRateLimited: true,
        rateLimitedUntil: DateTime.now().add(const Duration(seconds: 30)),
        lastSuccessAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Server busy — retrying'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('AnimatedSwitcher transitions on state changes', (tester) async {
    final fixedNow = DateTime.utc(2026, 5, 19, 12, 0, 0);
    final source = await _pump(tester, now: () => fixedNow);

    // Start stale.
    source.push(
      ConnectionStatus(
        isFresh: false,
        isReconnecting: false,
        isRateLimited: false,
        rateLimitedUntil: null,
        lastSuccessAt: fixedNow.subtract(const Duration(minutes: 3)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Last updated 3 min ago'), findsOneWidget);

    // Transition to reconnecting; both keys live during the 200ms switch.
    source.push(
      ConnectionStatus(
        isFresh: false,
        isReconnecting: true,
        isRateLimited: false,
        rateLimitedUntil: null,
        lastSuccessAt: fixedNow.subtract(const Duration(minutes: 3)),
      ),
    );
    await tester.pump();
    // Mid-transition both are still mounted via the fade.
    await tester.pump(const Duration(milliseconds: 100));
    // After the full 200ms only "Reconnecting…" remains.
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.text('Last updated 3 min ago'), findsNothing);
  });

  testWidgets('renders "just now" for sub-minute elapsed', (tester) async {
    final fixedNow = DateTime.utc(2026, 5, 19, 12, 0, 0);
    final source = await _pump(tester, now: () => fixedNow);
    source.push(
      ConnectionStatus(
        isFresh: false,
        isReconnecting: false,
        isRateLimited: false,
        rateLimitedUntil: null,
        lastSuccessAt: fixedNow.subtract(const Duration(seconds: 30)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Last updated just now'), findsOneWidget);
  });

  testWidgets('renders hour bucket for >1h elapsed', (tester) async {
    final fixedNow = DateTime.utc(2026, 5, 19, 12, 0, 0);
    final source = await _pump(tester, now: () => fixedNow);
    source.push(
      ConnectionStatus(
        isFresh: false,
        isReconnecting: false,
        isRateLimited: false,
        rateLimitedUntil: null,
        lastSuccessAt: fixedNow.subtract(const Duration(hours: 3)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Last updated 3 hours ago'), findsOneWidget);
  });
}
