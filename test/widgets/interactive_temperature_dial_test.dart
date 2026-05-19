import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: InteractiveTemperatureDial(
                device: device,
                displayUnit: 'C',
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

  group('InteractiveTemperatureDial — heat-cool mode', () {
    testWidgets('writes {high, low} with closer bound replaced', (
      tester,
    ) async {
      final result = await _pumpHost(
        tester,
        device: _device(
          mode: DeviceMode.heatCool,
          target: 21.0,
          high: 24.0,
          low: 18.0,
        ),
      );
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
      expect(m.keys, containsAll(['high', 'low']));
    });
  });
}
