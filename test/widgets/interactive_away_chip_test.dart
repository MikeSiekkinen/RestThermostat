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
import 'package:rest_thermostat/widgets/interactive_away_chip.dart';

Device _device({
  String ecoMode = 'schedule',
  Map<String, double>? eco,
  bool clearEco = false,
}) {
  final raw = File('test/fixtures/devices_one.json').readAsStringSync();
  final fixture = jsonDecode(raw) as Map<String, dynamic>;
  final entry = Map<String, dynamic>.from(
    (fixture['devices'] as List).first as Map<String, dynamic>,
  );
  entry['eco_mode'] = ecoMode;
  if (clearEco) {
    entry['eco_temperatures'] = null;
  } else if (eco != null) {
    entry['eco_temperatures'] = eco;
  }
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
  Future<EcoTemperaturesChoice?> Function(
    BuildContext, {
    required double initialLowC,
    required double initialHighC,
  })?
  showEcoSheet,
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
            child: InteractiveAwayChip(
              device: device,
              showEcoSheet: showEcoSheet,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (dio: dio, source: source);
}

void _wireMock({
  required Dio dio,
  required List<Object?> capturedAway,
  required List<Object?> capturedEco,
  int status = 200,
}) {
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final body = options.data;
        if (body is Map) {
          if (body['command'] == 'set_away') {
            capturedAway.add(body['value']);
          } else if (body['command'] == 'set_eco_temperatures') {
            capturedEco.add(body['value']);
          }
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
  group('InteractiveAwayChip — rendering', () {
    testWidgets('hidden text when not away (eco_mode=schedule)', (
      tester,
    ) async {
      await _pumpHost(tester, device: _device(ecoMode: 'schedule'));
      expect(find.text('AWAY'), findsNothing);
    });

    testWidgets('shows AWAY when eco_mode=manual-eco', (tester) async {
      await _pumpHost(tester, device: _device(ecoMode: 'manual-eco'));
      expect(find.text('AWAY'), findsOneWidget);
    });
  });

  group('InteractiveAwayChip — tap toggles away', () {
    testWidgets('tap from inactive → POST set_away true + refresh', (
      tester,
    ) async {
      final result = await _pumpHost(
        tester,
        device: _device(ecoMode: 'schedule'),
      );
      final captured = <Object?>[];
      final eco = <Object?>[];
      _wireMock(dio: result.dio, capturedAway: captured, capturedEco: eco);

      await tester.tap(find.byType(InteractiveAwayChip));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(captured, [true]);
      expect(result.source.refreshCount, 1);
      // Optimistic state should show the AWAY chip immediately.
      expect(find.text('AWAY'), findsOneWidget);
    });

    testWidgets('tap from active → POST set_away false + refresh', (
      tester,
    ) async {
      final result = await _pumpHost(
        tester,
        device: _device(ecoMode: 'manual-eco'),
      );
      final captured = <Object?>[];
      final eco = <Object?>[];
      _wireMock(dio: result.dio, capturedAway: captured, capturedEco: eco);

      await tester.tap(find.byType(InteractiveAwayChip));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(captured, [false]);
      expect(result.source.refreshCount, 1);
      expect(find.text('AWAY'), findsNothing);
    });
  });

  group('InteractiveAwayChip — long-press sheet', () {
    testWidgets(
      'long-press → sheet returns choice → POST set_eco_temperatures with '
      '{low,high}',
      (tester) async {
        final result = await _pumpHost(
          tester,
          device: _device(
            ecoMode: 'schedule',
            eco: {'low': 18.0, 'high': 26.0},
          ),
          // Fake sheet returns a chosen range.
          showEcoSheet:
              (
                _, {
                required double initialLowC,
                required double initialHighC,
              }) async {
                // Verify the sheet was seeded with the device's current values.
                expect(initialLowC, 18.0);
                expect(initialHighC, 26.0);
                return const EcoTemperaturesChoice(lowC: 16.0, highC: 28.0);
              },
        );
        final captured = <Object?>[];
        final eco = <Object?>[];
        _wireMock(dio: result.dio, capturedAway: captured, capturedEco: eco);

        await tester.longPress(find.byType(InteractiveAwayChip));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        expect(eco, [
          {'low': 16.0, 'high': 28.0},
        ]);
        expect(result.source.refreshCount, 1);
        // No set_away fired.
        expect(captured, isEmpty);
      },
    );

    testWidgets('long-press cancelled → no POST', (tester) async {
      final result = await _pumpHost(
        tester,
        device: _device(ecoMode: 'schedule'),
        showEcoSheet:
            (
              _, {
              required double initialLowC,
              required double initialHighC,
            }) async => null,
      );
      final captured = <Object?>[];
      final eco = <Object?>[];
      _wireMock(dio: result.dio, capturedAway: captured, capturedEco: eco);

      await tester.longPress(find.byType(InteractiveAwayChip));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(captured, isEmpty);
      expect(eco, isEmpty);
      expect(result.source.refreshCount, 0);
    });

    testWidgets(
      'sheet seeds default low/high when device has no eco_temperatures',
      (tester) async {
        double? seenLow;
        double? seenHigh;
        await _pumpHost(
          tester,
          device: _device(ecoMode: 'schedule', clearEco: true),
          showEcoSheet:
              (
                _, {
                required double initialLowC,
                required double initialHighC,
              }) async {
                seenLow = initialLowC;
                seenHigh = initialHighC;
                return null;
              },
        );
        await tester.longPress(find.byType(InteractiveAwayChip));
        await tester.pump(const Duration(milliseconds: 100));

        expect(seenLow, 15.5);
        expect(seenHigh, 29.5);
      },
    );
  });

  group('InteractiveAwayChip — failure paths', () {
    testWidgets('tap → 500 reverts optimistic and shows generic snackbar', (
      tester,
    ) async {
      final result = await _pumpHost(
        tester,
        device: _device(ecoMode: 'schedule'),
      );
      _wireMock(
        dio: result.dio,
        capturedAway: <Object?>[],
        capturedEco: <Object?>[],
        status: 500,
      );

      await tester.tap(find.byType(InteractiveAwayChip));
      // 2s retry + drain.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text('Couldn\'t change away'), findsOneWidget);
      expect(result.source.refreshCount, 0);
      // Optimistic AWAY reverted → no chip visible.
      expect(find.text('AWAY'), findsNothing);
    });
  });

  group('InteractiveAwayChip — accessibility', () {
    testWidgets('touch target is ≥48dp tall even when inactive', (
      tester,
    ) async {
      await _pumpHost(tester, device: _device(ecoMode: 'schedule'));
      final box = tester
          .renderObject<RenderBox>(find.byType(InteractiveAwayChip))
          .size;
      expect(box.height, greaterThanOrEqualTo(48));
    });
  });
}
