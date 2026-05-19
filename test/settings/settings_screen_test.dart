import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:rest_thermostat/models/auth_config.dart';
import 'package:rest_thermostat/services/app_info.dart';
import 'package:rest_thermostat/services/nle_api_client.dart';
import 'package:rest_thermostat/settings/settings_screen.dart';
import 'package:rest_thermostat/state/providers.dart';
import 'package:rest_thermostat/state/state_cache.dart';

import '../onboarding/fake_onboarding_store.dart';
import '../state/fake_state_cache.dart';

class _Harness {
  final Widget widget;
  final Dio dio;
  final DioAdapter adapter;
  final FakeOnboardingStore store;
  final FakeStateCache cache;

  _Harness({
    required this.widget,
    required this.dio,
    required this.adapter,
    required this.store,
    required this.cache,
  });
}

_Harness _setup({
  String? initialUrl,
  AuthConfig initialAuth = const AuthNone(),
  Map<String, String> overrides = const {},
  VoidCallback? onDisconnect,
  bool initiallyExpandAuth = false,
}) {
  final store = FakeOnboardingStore()
    ..serverUrl = initialUrl
    ..auth = initialAuth
    ..activeSerial = '02AA01AC041403JM'
    ..complete = true
    ..nameOverrides.addAll(overrides);

  final dio = Dio(BaseOptions(baseUrl: initialUrl ?? 'http://placeholder'));
  final adapter = DioAdapter(dio: dio);
  final cache = FakeStateCache();

  final widget = ProviderScope(
    overrides: [
      onboardingStoreProvider.overrideWithValue(store),
      appInfoProvider.overrideWithValue(
        const StaticAppInfo(version: '1.0.0', buildNumber: '1'),
      ),
      stateCacheProvider.overrideWithValue(cache),
      clientFactoryProvider.overrideWithValue(
        (url, auth) => NleApiClient(dio: dio),
      ),
      // Seed an active server so Riverpod's nleApiClientProvider doesn't
      // throw when devicesSnapshotProvider is read.
      activeServerProvider.overrideWith(
        () => _SeedActiveServer(
          initialUrl == null ? null : (url: initialUrl, auth: initialAuth),
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(
        onDisconnect: onDisconnect ?? () {},
        initiallyExpandAuth: initiallyExpandAuth,
      ),
    ),
  );

  return _Harness(
    widget: widget,
    dio: dio,
    adapter: adapter,
    store: store,
    cache: cache,
  );
}

class _SeedActiveServer extends ActiveServerNotifier {
  final ActiveServer? seed;
  _SeedActiveServer(this.seed);
  @override
  ActiveServer? build() => seed;
}

/// Drains microtasks the Dio mock resolves outside `pumpAndSettle`'s reach,
/// then unmounts the [ProviderScope] so the polling source's periodic timer
/// is cancelled before the test framework's pending-timer assertion runs.
Future<void> _settleAndUnmount(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Map<String, dynamic> _devicesOne() =>
    jsonDecode(File('test/fixtures/devices_one.json').readAsStringSync())
        as Map<String, dynamic>;

Future<void> _seedCache(FakeStateCache cache) async {
  cache.entry = CachedDevicesResponse(
    fetchedAt: DateTime(2026, 5, 18),
    response: _devicesOne(),
  );
}

void main() {
  testWidgets('pre-populates Server URL from store', (tester) async {
    final h = _setup(initialUrl: 'http://saved.local:8082');
    h.adapter.onGet('/api/devices', (s) => s.reply(200, _devicesOne()));

    await tester.pumpWidget(h.widget);
    await _settleAndUnmount(tester);

    expect(
      find.widgetWithText(TextFormField, 'http://saved.local:8082'),
      findsOneWidget,
    );

    await _disposeTree(tester);
  });

  testWidgets('Save is disabled until a successful Test connection', (
    tester,
  ) async {
    final h = _setup(initialUrl: 'http://saved.local:8082');
    h.adapter.onGet('/api/devices', (s) => s.reply(200, _devicesOne()));

    await tester.pumpWidget(h.widget);
    await _settleAndUnmount(tester);

    final saveButton = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Test connection'));
    await _settleAndUnmount(tester);

    expect(find.textContaining('Connected'), findsOneWidget);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);

    await _disposeTree(tester);
  });

  testWidgets('Edit after successful test re-disables Save until re-test', (
    tester,
  ) async {
    final h = _setup(initialUrl: 'http://saved.local:8082');
    h.adapter.onGet('/api/devices', (s) => s.reply(200, _devicesOne()));

    await tester.pumpWidget(h.widget);
    await _settleAndUnmount(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Test connection'));
    await _settleAndUnmount(tester);

    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    // Now edit the URL — Save should disable again until re-tested.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'http://saved.local:8082'),
      'http://other.local:8082',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await _disposeTree(tester);
  });

  testWidgets('401 test failure preserves previous config (no save)', (
    tester,
  ) async {
    final h = _setup(
      initialUrl: 'http://saved.local:8082',
      initialAuth: const AuthBearer(token: 'old-token'),
    );
    h.adapter.onGet(
      '/api/devices',
      (s) => s.reply(401, {'error': 'unauthorized'}),
    );
    // Pre-seed the cache so the Devices list renders from cache instead of
    // hanging on a CircularProgressIndicator (which keeps `pumpAndSettle`
    // from settling) while the live 401 poll fails silently.
    await _seedCache(h.cache);

    await tester.pumpWidget(h.widget);
    await _settleAndUnmount(tester);

    // Change the bearer token, then test → expect failure. (Advanced is
    // auto-expanded by _loadInitial when initialAuth is non-None.)
    final tokenField = find.widgetWithText(TextFormField, 'Token');
    expect(tokenField, findsOneWidget);
    await tester.enterText(tokenField, 'new-broken-token');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Test connection'));
    await _settleAndUnmount(tester);

    expect(find.text('Authentication failed.'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    // Store still holds the old token (§7.6 "previous working config in place")
    expect((h.store.auth as AuthBearer).token, 'old-token');

    await _disposeTree(tester);
  });

  testWidgets('Successful Save persists URL+auth and clears cache', (
    tester,
  ) async {
    final h = _setup(initialUrl: 'http://saved.local:8082');
    h.adapter.onGet('/api/devices', (s) => s.reply(200, _devicesOne()));

    await tester.pumpWidget(h.widget);
    await _settleAndUnmount(tester);
    final clearsBefore = h.cache.clearCount;

    await tester.enterText(
      find.widgetWithText(TextFormField, 'http://saved.local:8082'),
      'nest.home',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Test connection'));
    await _settleAndUnmount(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _settleAndUnmount(tester);

    expect(h.store.serverUrl, 'http://nest.home:8082');
    expect(
      h.cache.clearCount,
      greaterThan(clearsBefore),
      reason: 'Save should clear the state cache per DESIGN §12.6',
    );

    await _disposeTree(tester);
  });

  testWidgets('Rename dialog writes override; empty rename clears it', (
    tester,
  ) async {
    final h = _setup(initialUrl: 'http://saved.local:8082');
    h.adapter.onGet('/api/devices', (s) => s.reply(200, _devicesOne()));

    await tester.pumpWidget(h.widget);
    await _settleAndUnmount(tester);

    final upstairsTile = find.text('Upstairs');
    expect(upstairsTile, findsOneWidget);
    await tester.tap(upstairsTile);
    await tester.pumpAndSettle();

    expect(find.text('Rename thermostat'), findsOneWidget);
    final dialogField = find.widgetWithText(TextField, 'Display name');
    await tester.enterText(dialogField, 'Den');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(h.store.nameOverrides['02AA01AC041403JM'], 'Den');
    expect(find.text('Den'), findsOneWidget);

    // Re-open and clear it.
    await tester.tap(find.text('Den'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Display name'), '');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(h.store.nameOverrides.containsKey('02AA01AC041403JM'), isFalse);
    expect(find.text('Upstairs'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('Disconnect dialog cancel keeps config; confirm wipes it', (
    tester,
  ) async {
    var disconnected = 0;
    final h = _setup(
      initialUrl: 'http://saved.local:8082',
      onDisconnect: () => disconnected++,
    );
    h.adapter.onGet('/api/devices', (s) => s.reply(200, _devicesOne()));

    await tester.pumpWidget(h.widget);
    await _settleAndUnmount(tester);

    // Cancel path. The danger-zone button sits below the viewport in the
    // default 800x600 test surface; scroll it on-screen before tapping.
    final disconnectButton = find.widgetWithText(
      TextButton,
      'Disconnect from server',
    );
    await tester.ensureVisible(disconnectButton);
    await tester.pumpAndSettle();
    await tester.tap(disconnectButton);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This will remove your server settings and saved credentials. Continue?',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(disconnected, 0);
    expect(h.store.serverUrl, 'http://saved.local:8082');
    expect(h.store.complete, isTrue);

    // Confirm path.
    await tester.ensureVisible(disconnectButton);
    await tester.pumpAndSettle();
    await tester.tap(disconnectButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Disconnect'));
    await tester.pumpAndSettle();

    expect(disconnected, 1);
    expect(h.store.serverUrl, isNull);
    expect(h.store.complete, isFalse);
    expect(h.store.auth, isA<AuthNone>());

    await _disposeTree(tester);
  });

  testWidgets('About section renders version, NLE credit, repo URL', (
    tester,
  ) async {
    final h = _setup(initialUrl: 'http://saved.local:8082');
    h.adapter.onGet('/api/devices', (s) => s.reply(200, _devicesOne()));

    await tester.pumpWidget(h.widget);
    await _settleAndUnmount(tester);

    expect(find.textContaining('Rest Thermostat 1.0.0'), findsOneWidget);
    expect(find.text(settingsNleCredit), findsOneWidget);
    expect(find.textContaining(settingsRepoUrl), findsOneWidget);
    expect(find.textContaining(settingsNleDocsUrl), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('initiallyExpandAuth=true reveals auth section on first frame', (
    tester,
  ) async {
    final h = _setup(
      initialUrl: 'http://saved.local:8082',
      initiallyExpandAuth: true,
    );
    h.adapter.onGet('/api/devices', (s) => s.reply(200, _devicesOne()));

    await tester.pumpWidget(h.widget);
    await _settleAndUnmount(tester);

    // The Authentication dropdown only renders inside the expanded
    // "Advanced" section. With initiallyExpandAuth=true it should be
    // visible without the user tapping the expander first.
    expect(find.text('Authentication'), findsOneWidget);

    await _disposeTree(tester);
  });
}
