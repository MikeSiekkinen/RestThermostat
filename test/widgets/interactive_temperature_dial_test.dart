import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:rest_thermostat/models/device.dart';
import 'package:rest_thermostat/services/nle_api_client.dart';
import 'package:rest_thermostat/state/connection_status.dart';
import 'package:rest_thermostat/state/device_state_source.dart';
import 'package:rest_thermostat/state/devices_snapshot.dart';
import 'package:rest_thermostat/state/providers.dart';
import 'package:rest_thermostat/widgets/interactive_temperature_dial.dart';

Device _device({
  DeviceMode mode = DeviceMode.heat,
  double target = 20.0,
  double? high,
  double? low,
}) {
  final raw = File('test/fixtures/devices_one.json').readAsStringSync();
  final fixture = jsonDecode(raw) as Map<String, dynamic>;
  final entry = Map<String, dynamic>.from(
    (fixture['devices'] as List).first as Map<String, dynamic>,
  );
  entry['mode'] = mode.toApi();
  entry['target_temperature'] = target;
  if (high != null) entry['target_temperature_high'] = high;
  if (low != null) entry['target_temperature_low'] = low;
  return Device.fromJson(entry);
}

class _StubSource implements DeviceStateSource {
  final _controller = StreamController<DevicesSnapshot>.broadcast();
  int refreshCount = 0;

  @override
  Stream<DevicesSnapshot> watch() => _controller.stream;

  @override
  void refresh() => refreshCount++;

  /// Push a reconciliation snapshot through the devices stream (Issue #116
  /// dual confirm-watch tests).
  void emit(DevicesSnapshot snapshot) => _controller.add(snapshot);

  @override
  bool get isStale => false;

  @override
  Stream<ConnectionStatus> watchStatus() => const Stream.empty();

  @override
  Future<void> dispose() async => _controller.close();
}

Future<({Dio dio, _StubSource source})> _pumpHost(
  WidgetTester tester, {
  required Device device,
  String displayUnit = 'C',
}) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
  final source = _StubSource();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nleApiClientProvider.overrideWithValue(NleApiClient(dio: dio)),
        deviceStateSourceProvider.overrideWithValue(source),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: InteractiveTemperatureDial(
                device: device,
                displayUnit: displayUnit,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (dio: dio, source: source);
}

/// Capture the `value` of every `set_temperature` POST on [dio].
List<Object?> _captureSetTemperature(Dio dio) {
  final captured = <Object?>[];
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final body = options.data as Map<String, dynamic>?;
        if (body != null && body['command'] == 'set_temperature') {
          captured.add(body['value']);
        }
        handler.next(options);
      },
    ),
  );
  DioAdapter(dio: dio).onPost(
    '/command',
    (server) => server.reply(200, {'ok': true}),
    data: Matchers.any,
  );
  return captured;
}

void main() {
  group('InteractiveTemperatureDial — single-setpoint modes', () {
    testWidgets('drag updates the displayed target (optimistic)', (
      tester,
    ) async {
      final result = await _pumpHost(tester, device: _device(target: 20.0));
      DioAdapter(dio: result.dio).onPost(
        '/command',
        (server) => server.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      expect(find.text('20°'), findsOneWidget);

      final center = tester.getCenter(find.byType(InteractiveTemperatureDial));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(80, -80));
      await tester.pump(const Duration(milliseconds: 50));
      // Optimistic value should have changed from 20°.
      expect(find.text('20°'), findsNothing);
      await gesture.up();
    });

    testWidgets(
      'pan-end POSTs set_temperature with a numeric celsius value, then '
      'refreshes the source',
      (tester) async {
        final result = await _pumpHost(tester, device: _device(target: 20.0));
        Object? capturedValue;
        result.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              final body = options.data as Map<String, dynamic>?;
              if (body != null && body['command'] == 'set_temperature') {
                capturedValue = body['value'];
              }
              handler.next(options);
            },
          ),
        );
        DioAdapter(dio: result.dio).onPost(
          '/command',
          (server) => server.reply(200, {'ok': true}),
          data: Matchers.any,
        );

        final center = tester.getCenter(
          find.byType(InteractiveTemperatureDial),
        );
        final gesture = await tester.startGesture(center);
        await gesture.moveBy(const Offset(80, -80));
        await gesture.up();
        // Allow the 250ms debounce + microtask drain.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        expect(
          capturedValue,
          isA<double>(),
          reason: 'set_temperature value should be a number for heat mode',
        );
        expect(
          result.source.refreshCount,
          1,
          reason: 'commit should kick a reconciliation refresh',
        );
      },
    );
  });

  group('InteractiveTemperatureDial — heat-cool dual band (Issue #116)', () {
    const heatField = ValueKey('range-entry-heat-field');
    const coolField = ValueKey('range-entry-cool-field');
    const rangeConfirm = ValueKey('range-entry-confirm');

    Device dual() =>
        _device(mode: DeviceMode.heatCool, target: 21.0, low: 18.0, high: 24.0);

    testWidgets('renders the stacked HEAT/COOL readout with both setpoints', (
      tester,
    ) async {
      await _pumpHost(tester, device: dual());

      expect(find.text('HEAT'), findsOneWidget);
      expect(find.text('COOL'), findsOneWidget);
      expect(find.text('18°'), findsOneWidget);
      expect(find.text('24°'), findsOneWidget);
    });

    testWidgets('a ring drag POSTs the explicit {low, high} pair with the '
        'deadband preserved (no nearest-bound heuristic)', (tester) async {
      final result = await _pumpHost(tester, device: dual());
      Object? capturedValue;
      result.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final body = options.data as Map<String, dynamic>?;
            if (body != null && body['command'] == 'set_temperature') {
              capturedValue = body['value'];
            }
            handler.next(options);
          },
        ),
      );
      DioAdapter(dio: result.dio).onPost(
        '/command',
        (server) => server.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      final center = tester.getCenter(find.byType(InteractiveTemperatureDial));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(80, -80));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(capturedValue, isA<Map<String, dynamic>>());
      final m = capturedValue! as Map<String, dynamic>;
      expect(m.keys, containsAll(['low', 'high']));
      final low = (m['low'] as num).toDouble();
      final high = (m['high'] as num).toDouble();
      // The explicit pair always honors the 1.5°C deadband.
      expect(high - low, greaterThanOrEqualTo(1.5 - 1e-9));
    });

    testWidgets('tapping the readout opens the dual-field range dialog', (
      tester,
    ) async {
      final result = await _pumpHost(tester, device: dual());
      _captureSetTemperature(result.dio);

      expect(find.byKey(heatField), findsNothing);
      await tester.tap(find.bySemanticsLabel(RegExp('Set temperature')));
      await tester.pumpAndSettle();

      expect(find.byKey(heatField), findsOneWidget);
      expect(find.byKey(coolField), findsOneWidget);
    });

    testWidgets('the range dialog disables Set with an inline error until the '
        'deadband is satisfied', (tester) async {
      final result = await _pumpHost(tester, device: dual());
      final captured = _captureSetTemperature(result.dio);

      await tester.tap(find.bySemanticsLabel(RegExp('Set temperature')));
      await tester.pumpAndSettle();

      // Shrink the gap below the deadband: heat 18°C, cool 19°C (1°C < 1.5°C).
      await tester.enterText(find.byKey(coolField), '19');
      await tester.pump();

      expect(
        tester.widget<TextButton>(find.byKey(rangeConfirm)).onPressed,
        isNull,
        reason: 'Set is disabled while the deadband is violated',
      );
      expect(find.textContaining('at least'), findsOneWidget);

      // Widen the gap back out: cool 24°C → Set re-enables, error clears.
      await tester.enterText(find.byKey(coolField), '24');
      await tester.pump();

      expect(
        tester.widget<TextButton>(find.byKey(rangeConfirm)).onPressed,
        isNotNull,
      );
      expect(find.textContaining('at least'), findsNothing);

      await tester.tap(find.byKey(rangeConfirm));
      await tester.pumpAndSettle();

      // Both bounds commit together as an explicit pair.
      expect(captured, hasLength(1));
      final m = captured.single! as Map<String, dynamic>;
      expect((m['low'] as num).toDouble(), closeTo(18.0, 0.01));
      expect((m['high'] as num).toDouble(), closeTo(24.0, 0.01));
    });

    testWidgets('confirm-watch clears the optimistic band when both bounds '
        'reconcile against the snapshot', (tester) async {
      final result = await _pumpHost(tester, device: dual());
      _captureSetTemperature(result.dio);

      // Commit a new band via the dialog: heat 20°C, cool 26°C.
      await tester.tap(find.bySemanticsLabel(RegExp('Set temperature')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(heatField), '20');
      await tester.enterText(find.byKey(coolField), '26');
      await tester.tap(find.byKey(rangeConfirm));
      await tester.pumpAndSettle();

      // Optimistic band is showing the typed values.
      expect(find.text('20°'), findsOneWidget);
      expect(find.text('26°'), findsOneWidget);

      // A snapshot delivering the reconciled bounds releases the override; the
      // readout returns to the (static) device prop, proving it cleared.
      result.source.emit(
        DevicesSnapshot(
          devices: [
            _device(
              mode: DeviceMode.heatCool,
              target: 21.0,
              low: 20.0,
              high: 26.0,
            ),
          ],
          fetchedAt: DateTime.now(),
          fromCache: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('18°'), findsOneWidget); // back to the device prop
      expect(find.text('20°'), findsNothing); // optimistic override released
    });

    testWidgets('a failed range POST reverts both optimistic bounds', (
      tester,
    ) async {
      final result = await _pumpHost(tester, device: dual());
      // A 400 is non-transient, so the write fails fast (no 2s retry delay).
      DioAdapter(dio: result.dio).onPost(
        '/command',
        (server) => server.reply(400, {'error': 'nope'}),
        data: Matchers.any,
      );

      await tester.tap(find.bySemanticsLabel(RegExp('Set temperature')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(heatField), '20');
      await tester.enterText(find.byKey(coolField), '26');
      await tester.tap(find.byKey(rangeConfirm));
      await tester.pumpAndSettle();

      // Failure reverts to the original band; a retry snackbar is shown.
      expect(find.text('18°'), findsOneWidget);
      expect(find.text('24°'), findsOneWidget);
      expect(find.text('20°'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('InteractiveTemperatureDial — keyboard entry (Issue #113)', () {
    const field = ValueKey('temp-entry-field');
    const confirm = ValueKey('temp-entry-confirm');

    testWidgets('tapping the target readout opens the keyboard dialog', (
      tester,
    ) async {
      final result = await _pumpHost(tester, device: _device(target: 20.0));
      _captureSetTemperature(result.dio);

      expect(find.byKey(field), findsNothing);
      // The large '20°' target readout (current-temp line shows 25°).
      await tester.tap(find.text('20°'));
      await tester.pumpAndSettle();

      expect(find.byKey(field), findsOneWidget);
    });

    testWidgets('Set commits the typed value via set_temperature (°C)', (
      tester,
    ) async {
      final result = await _pumpHost(tester, device: _device(target: 20.0));
      final captured = _captureSetTemperature(result.dio);

      await tester.tap(find.text('20°'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(field), '23');
      await tester.tap(find.byKey(confirm));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(captured, [23.0]);
      expect(result.source.refreshCount, 1);
      expect(find.text('23°'), findsOneWidget);
    });

    testWidgets('°F entry converts back to Celsius on commit', (tester) async {
      final result = await _pumpHost(
        tester,
        device: _device(target: 20.0),
        displayUnit: 'F',
      );
      final captured = _captureSetTemperature(result.dio);

      // 20°C shows as 68°F.
      await tester.tap(find.text('68°'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(field), '70');
      await tester.tap(find.byKey(confirm));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(captured, hasLength(1));
      expect(captured.single, isA<double>());
      // 70°F → 21.11°C.
      expect(captured.single! as double, closeTo(21.11, 0.01));
      expect(find.text('70°'), findsOneWidget);
    });

    testWidgets('integer-only: a typed decimal is rounded before commit', (
      tester,
    ) async {
      final result = await _pumpHost(tester, device: _device(target: 19.0));
      final captured = _captureSetTemperature(result.dio);

      await tester.tap(find.text('19°'));
      await tester.pumpAndSettle();
      // enterText bypasses the integer keyboard; the dialog must still round.
      await tester.enterText(find.byKey(field), '20.5');
      await tester.tap(find.byKey(confirm));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(captured, [21.0]); // 20.5 rounds to 21, not a fractional setpoint.
    });

    testWidgets('Cancel dismisses without committing', (tester) async {
      final result = await _pumpHost(tester, device: _device(target: 20.0));
      final captured = _captureSetTemperature(result.dio);

      await tester.tap(find.text('20°'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(field), '28');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(captured, isEmpty);
      expect(find.text('20°'), findsOneWidget);
    });

    testWidgets('tapping the ring (off-center) still jumps, not keyboard', (
      tester,
    ) async {
      final result = await _pumpHost(tester, device: _device(target: 20.0));
      final captured = _captureSetTemperature(result.dio);

      final center = tester.getCenter(find.byType(InteractiveTemperatureDial));
      // Tap low on the ring, well below the center readout cluster (the large
      // target glyph reaches ~100px above center, so stay clear of it).
      await tester.tapAt(center + const Offset(0, 108));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // No keyboard dialog; the ring tap jump-commits instead.
      expect(find.byKey(field), findsNothing);
      expect(captured, isNotEmpty);
    });

    testWidgets('opening the keyboard cancels a pending ring commit', (
      tester,
    ) async {
      final result = await _pumpHost(tester, device: _device(target: 20.0));
      final captured = _captureSetTemperature(result.dio);

      final center = tester.getCenter(find.byType(InteractiveTemperatureDial));
      // Ring tap starts the 250ms debounce (and jumps the displayed value, so
      // find the readout by its stable semantics label rather than its text).
      await tester.tapAt(center + const Offset(0, 108));
      await tester.pump(const Duration(milliseconds: 50)); // < 250ms
      await tester.tap(find.bySemanticsLabel(RegExp('Set temperature')));
      await tester.pumpAndSettle(); // drains past the 250ms debounce window
      await tester.enterText(find.byKey(field), '23');
      await tester.tap(find.byKey(confirm));
      await tester.pumpAndSettle();

      // Only the typed value is written — the pending ring commit was cancelled.
      expect(captured, [23.0]);
    });

    testWidgets('exposes a "Set temperature" accessibility button', (
      tester,
    ) async {
      final result = await _pumpHost(tester, device: _device(target: 20.0));
      _captureSetTemperature(result.dio);

      // The child "20°" text merges into the button node's label, so match on
      // the "Set temperature" substring.
      expect(find.bySemanticsLabel(RegExp('Set temperature')), findsOneWidget);
    });
  });
}
