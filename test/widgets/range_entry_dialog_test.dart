import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/widgets/range_entry_dialog.dart';

/// Open [RangeEntryDialog] and return a one-element holder that receives the
/// popped result once the dialog closes (empty until then).
Future<List<RangeEntryResult?>> _openDialog(
  WidgetTester tester, {
  required double lowC,
  required double highC,
  required String scale,
}) async {
  final holder = <RangeEntryResult?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              holder.add(
                await showDialog<RangeEntryResult>(
                  context: context,
                  builder: (_) => RangeEntryDialog(
                    lowC: lowC,
                    highC: highC,
                    scale: scale,
                    heatAccent: Colors.orange,
                    coolAccent: Colors.blue,
                    numeralStyle: null,
                    title: 'Set range',
                    heatLabel: 'Heat',
                    coolLabel: 'Cool',
                    confirmLabel: 'Set',
                    cancelLabel: 'Cancel',
                    deadbandError: 'Heat must be at least 3°F below cool.',
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return holder;
}

void main() {
  const heatField = ValueKey('range-entry-heat-field');
  const coolField = ValueKey('range-entry-cool-field');
  const confirm = ValueKey('range-entry-confirm');

  testWidgets('prefills both fields from the current bounds (°C)', (
    tester,
  ) async {
    await _openDialog(tester, lowC: 18.0, highC: 24.0, scale: 'C');

    expect(find.widgetWithText(TextField, '18'), findsOneWidget);
    expect(find.widgetWithText(TextField, '24'), findsOneWidget);
  });

  testWidgets('°F entry round-trips back to Celsius on confirm', (
    tester,
  ) async {
    final holder = await _openDialog(
      tester,
      lowC: 20.0,
      highC: 24.0,
      scale: 'F',
    );

    await tester.enterText(find.byKey(heatField), '68'); // 20°C
    await tester.enterText(find.byKey(coolField), '76'); // ~24.4°C
    await tester.pump();
    await tester.tap(find.byKey(confirm));
    await tester.pumpAndSettle();

    expect(holder, hasLength(1));
    final result = holder.single;
    expect(result, isNotNull);
    expect(result!.lowC, closeTo(20.0, 0.01));
    expect(result.highC, closeTo(24.44, 0.05));
  });

  testWidgets('Set is disabled while the deadband is violated', (tester) async {
    await _openDialog(tester, lowC: 20.0, highC: 24.0, scale: 'C');

    // 23°C / 24°C is a 1°C gap — below the 1.5°C deadband.
    await tester.enterText(find.byKey(heatField), '23');
    await tester.pump();

    expect(tester.widget<TextButton>(find.byKey(confirm)).onPressed, isNull);
    expect(find.text('Heat must be at least 3°F below cool.'), findsOneWidget);
  });

  testWidgets('Cancel returns null, leaving the caller unchanged', (
    tester,
  ) async {
    final holder = await _openDialog(
      tester,
      lowC: 18.0,
      highC: 24.0,
      scale: 'C',
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(holder, hasLength(1));
    expect(holder.single, isNull);
  });
}
