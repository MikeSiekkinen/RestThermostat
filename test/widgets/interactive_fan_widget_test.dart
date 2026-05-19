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
import 'package:rest_thermostat/widgets/interactive_fan_widget.dart';

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
  DateTime Function()? now,
  Future<int?> Function(BuildContext)? showDurationSheet,
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
            child: InteractiveFanWidget(
              device: device,
              now: now ?? DateTime.now,
              showDurationSheet: showDurationSheet,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (dio: dio, source: source);
}

/// Capture the request body and stub a 200 response.
void _wireMock({
  required Dio dio,
  required List<Object?> capturedValues,
  int status = 200,
}) {
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final body = options.data;
        if (body is Map && body['command'] == 'set_fan') {
          capturedValues.add(body['value']);
        }
        handler.next(options);
      },
    ),
  );
  DioAdapter(dio: dio).onPost(
    '/command',
    (server) => server.reply(status, {'ok': true}),
    data: Matchers.any,
  );
}

void main() {
  group('InteractiveFanWidget — tap toggle', () {
    testWidgets(
      'tap when auto → optimistic on (1h) + POST set_fan 3600 + refresh',
      (tester) async {
        final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
        final result = await _pumpHost(
          tester,
          device: _device(hasFan: true, fanTimerActive: false),
          now: () => now,
        );

        final captured = <Object?>[];
        _wireMock(dio: result.dio, capturedValues: captured);

        await tester.tap(find.byType(InteractiveFanWidget));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        expect(captured, [3600]);
        expect(result.source.refreshCount, 1);
        // Synthesized timeout = now + 3600s → countdown reads 60:00.
        expect(find.text('FAN ON • 60:00'), findsOneWidget);
      },
    );

    testWidgets(
      'tap when on → optimistic auto + POST set_fan "auto" + refresh',
      (tester) async {
        final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
        final timeout = now.add(const Duration(minutes: 30));
        final result = await _pumpHost(
          tester,
          device: _device(
            hasFan: true,
            fanTimerActive: true,
            fanTimerTimeout: timeout.millisecondsSinceEpoch ~/ 1000,
          ),
          now: () => now,
        );

        final captured = <Object?>[];
        _wireMock(dio: result.dio, capturedValues: captured);

        await tester.tap(find.byType(InteractiveFanWidget));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        expect(captured, ['auto']);
        expect(result.source.refreshCount, 1);
        expect(find.text('FAN AUTO'), findsOneWidget);
      },
    );
  });

  group('InteractiveFanWidget — long-press duration sheet', () {
    testWidgets('long-press invokes the sheet and posts the chosen seconds', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
      final result = await _pumpHost(
        tester,
        device: _device(hasFan: true, fanTimerActive: false),
        now: () => now,
        // Fake sheet — pick 30 minutes.
        showDurationSheet: (_) async => 1800,
      );

      final captured = <Object?>[];
      _wireMock(dio: result.dio, capturedValues: captured);

      await tester.longPress(find.byType(InteractiveFanWidget));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(captured, [1800]);
      expect(result.source.refreshCount, 1);
      expect(find.text('FAN ON • 30:00'), findsOneWidget);
    });

    testWidgets('long-press cancelled (sheet returns null) does not POST', (
      tester,
    ) async {
      final result = await _pumpHost(
        tester,
        device: _device(hasFan: true, fanTimerActive: false),
        showDurationSheet: (_) async => null,
      );

      final captured = <Object?>[];
      _wireMock(dio: result.dio, capturedValues: captured);

      await tester.longPress(find.byType(InteractiveFanWidget));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(captured, isEmpty);
      expect(result.source.refreshCount, 0);
      // No optimistic state applied — still auto.
      expect(find.text('FAN AUTO'), findsOneWidget);
    });
  });

  group('InteractiveFanWidget — failure paths', () {
    testWidgets('500 reverts optimistic state and surfaces snackbar', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 5, 19, 12, 0, 0);
      final result = await _pumpHost(
        tester,
        device: _device(hasFan: true, fanTimerActive: false),
        now: () => now,
      );
      _wireMock(dio: result.dio, capturedValues: <Object?>[], status: 500);

      await tester.tap(find.byType(InteractiveFanWidget));
      // Retry path waits 2s.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text('Couldn\'t change fan'), findsOneWidget);
      expect(result.source.refreshCount, 0);
      // Optimistic 'on' reverted → back to FAN AUTO.
      expect(find.text('FAN AUTO'), findsOneWidget);
    });
  });

  group('InteractiveFanWidget — hidden when no fan capability', () {
    testWidgets('renders nothing', (tester) async {
      await _pumpHost(
        tester,
        device: _device(hasFan: false, fanTimerActive: false),
      );
      expect(find.text('FAN AUTO'), findsNothing);
    });
  });
}
