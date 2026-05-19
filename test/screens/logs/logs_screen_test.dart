import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rest_thermostat/screens/logs/logs_screen.dart';
import 'package:rest_thermostat/services/app_logger.dart';

Widget _harness(AppLogger logger) {
  return ProviderScope(
    overrides: [appLoggerProvider.overrideWithValue(logger)],
    child: const MaterialApp(home: LogsScreen()),
  );
}

void main() {
  testWidgets('shows placeholder when buffer is empty', (tester) async {
    final logger = AppLogger(capacity: 10);
    await tester.pumpWidget(_harness(logger));
    expect(find.text('No log entries yet.'), findsOneWidget);
  });

  testWidgets('renders each log entry message with its level label', (
    tester,
  ) async {
    final logger = AppLogger(capacity: 10);
    logger.info('GET /api/devices → 200 (12ms)');
    logger.warn('something fishy');
    logger.error('boom: connection-error');

    await tester.pumpWidget(_harness(logger));
    await tester.pumpAndSettle();

    expect(find.text('GET /api/devices → 200 (12ms)'), findsOneWidget);
    expect(find.text('something fishy'), findsOneWidget);
    expect(find.text('boom: connection-error'), findsOneWidget);
    expect(find.text('INFO'), findsOneWidget);
    expect(find.text('WARN'), findsOneWidget);
    expect(find.text('ERROR'), findsOneWidget);
  });

  testWidgets('Copy button writes formatted text to the clipboard', (
    tester,
  ) async {
    String? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>;
            captured = args['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final logger = AppLogger(
      capacity: 10,
      clock: () => DateTime.utc(2026, 5, 18, 14, 30, 45),
    );
    logger.info('GET /api/devices → 200 (12ms)');
    logger.error('GET /api/devices → 500 bad-response (8ms)');

    await tester.pumpWidget(_harness(logger));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copy to clipboard'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured, contains('INFO'));
    expect(captured, contains('GET /api/devices → 200 (12ms)'));
    expect(captured, contains('ERROR'));
    expect(captured, contains('GET /api/devices → 500 bad-response (8ms)'));
    expect(find.text('Logs copied to clipboard.'), findsOneWidget);
  });

  testWidgets('Clear action confirms then empties the buffer', (tester) async {
    final logger = AppLogger(capacity: 10);
    logger.info('something');
    logger.warn('else');

    await tester.pumpWidget(_harness(logger));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Clear logs?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(logger.entries, isEmpty);
    expect(find.text('No log entries yet.'), findsOneWidget);
  });

  testWidgets('Clear action Cancel preserves the buffer', (tester) async {
    final logger = AppLogger(capacity: 10);
    logger.info('keep me');

    await tester.pumpWidget(_harness(logger));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(logger.entries, hasLength(1));
    expect(find.text('keep me'), findsOneWidget);
  });
}
