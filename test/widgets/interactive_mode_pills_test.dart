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
import 'package:rest_thermostat/widgets/interactive_mode_pills.dart';

Device _device({DeviceMode mode = DeviceMode.heat}) {
  final raw = File('test/fixtures/devices_one.json').readAsStringSync();
  final fixture = jsonDecode(raw) as Map<String, dynamic>;
  final entry = Map<String, dynamic>.from(
    (fixture['devices'] as List).first as Map<String, dynamic>,
  );
  entry['mode'] = mode.toApi();
  // Heat-cool requires both can_heat and can_cool — the fixture already has
  // can_heat=true; flip can_cool=true so AUTO pill is visible too.
  final caps = Map<String, dynamic>.from(
    entry['capabilities'] as Map<String, dynamic>,
  );
  caps['can_heat'] = true;
  caps['can_cool'] = true;
  entry['capabilities'] = caps;
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: InteractiveModePills(device: device)),
      ),
    ),
  );
  await tester.pump();
  return (dio: dio, source: source);
}

void main() {
  group('InteractiveModePills — happy path', () {
    testWidgets('tap fires set_mode with API value and kicks refresh', (
      tester,
    ) async {
      final result = await _pumpHost(tester, device: _device());

      final captured = <String>[];
      result.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final body = options.data;
            if (body is Map && body['command'] == 'set_mode') {
              captured.add(body['value'] as String);
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

      await tester.tap(find.text('COOL'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(captured, ['cool']);
      expect(result.source.refreshCount, 1);
    });

    testWidgets('AUTO pill maps to heat-cool on the API', (tester) async {
      final result = await _pumpHost(tester, device: _device());

      String? capturedValue;
      result.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final body = options.data;
            if (body is Map && body['command'] == 'set_mode') {
              capturedValue = body['value'] as String;
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

      await tester.tap(find.text('AUTO'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(capturedValue, 'heat-cool');
    });

    testWidgets('tap on the already-active pill is a no-op', (tester) async {
      final result = await _pumpHost(
        tester,
        device: _device(mode: DeviceMode.heat),
      );

      var calls = 0;
      result.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            handler.next(options);
          },
        ),
      );
      DioAdapter(dio: result.dio).onPost(
        '/command',
        (server) => server.reply(200, {'ok': true}),
        data: Matchers.any,
      );

      await tester.tap(find.text('HEAT'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(calls, 0);
      expect(result.source.refreshCount, 0);
    });
  });

  group('InteractiveModePills — failure paths', () {
    testWidgets('network failure → snackbar + no refresh', (tester) async {
      final result = await _pumpHost(tester, device: _device());

      DioAdapter(dio: result.dio).onPost(
        '/command',
        (server) => server.reply(500, {'error': 'server down'}),
        data: Matchers.any,
      );

      await tester.tap(find.text('COOL'));
      // Let the retry's 2s delay elapse, plus a tick to surface the snackbar.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text('server down'), findsOneWidget);
      expect(result.source.refreshCount, 0);
    });

    testWidgets('4xx without a server message uses the generic copy', (
      tester,
    ) async {
      final result = await _pumpHost(tester, device: _device());

      DioAdapter(dio: result.dio).onPost(
        '/command',
        (server) => server.reply(400, ''),
        data: Matchers.any,
      );

      await tester.tap(find.text('COOL'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('Server rejected mode change'), findsOneWidget);
      expect(result.source.refreshCount, 0);
    });

    testWidgets('4xx with `error` body surfaces the server message', (
      tester,
    ) async {
      final result = await _pumpHost(tester, device: _device());

      DioAdapter(dio: result.dio).onPost(
        '/command',
        (server) => server.reply(400, {'error': 'thermostat asleep'}),
        data: Matchers.any,
      );

      await tester.tap(find.text('COOL'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('thermostat asleep'), findsOneWidget);
    });
  });
}
