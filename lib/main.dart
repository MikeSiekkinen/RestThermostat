import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models/device.dart';
import 'onboarding/onboarding_flow.dart';
import 'services/app_info.dart';
import 'services/device_display_name.dart';
import 'services/onboarding_store.dart';
import 'settings/settings_screen.dart';
import 'state/devices_snapshot.dart';
import 'state/lifecycle_bridge.dart';
import 'state/providers.dart';
import 'theme/ember_theme.dart';
import 'widgets/ember_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force bundled-only font lookups. Any GoogleFonts.* call whose asset isn't
  // present under assets/fonts/ will throw rather than silently fall back to
  // an HTTP fetch.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Edge-to-edge dark per docs/DESIGN.md §11.6: transparent status bar with
  // light icons, transparent nav bar on Android.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final appInfo = await PackageInfoAppInfo.load();
  final store = FlutterOnboardingStore();
  runApp(
    ProviderScope(
      overrides: [
        appInfoProvider.overrideWithValue(appInfo),
        onboardingStoreProvider.overrideWithValue(store),
      ],
      child: RestThermostatApp(store: store),
    ),
  );
}

class RestThermostatApp extends StatelessWidget {
  final OnboardingStore? store;

  const RestThermostatApp({super.key, this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rest Thermostat',
      themeMode: ThemeMode.dark,
      darkTheme: emberTheme,
      home: _Bootstrap(store: store ?? FlutterOnboardingStore()),
    );
  }
}

class _Bootstrap extends ConsumerStatefulWidget {
  final OnboardingStore store;

  const _Bootstrap({required this.store});

  @override
  ConsumerState<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends ConsumerState<_Bootstrap> {
  late Future<OnboardingConfig> _configFuture;

  @override
  void initState() {
    super.initState();
    _configFuture = _load();
  }

  Future<OnboardingConfig> _load() async {
    final config = await widget.store.read();
    if (config.isComplete && config.serverUrl != null) {
      ref.read(activeServerProvider.notifier).set((
        url: config.serverUrl!,
        auth: config.auth,
      ));
    }
    return config;
  }

  void _onOnboardingComplete() {
    setState(() {
      _configFuture = _load();
    });
  }

  void _onDisconnect() {
    // Re-read the (now-wiped) config; Bootstrap's switch will render Welcome.
    setState(() {
      _configFuture = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OnboardingConfig>(
      future: _configFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const EmberBackground(
            mode: DeviceMode.off,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final config = snapshot.data!;
        if (config.isComplete && config.serverUrl != null) {
          return LifecycleBridge(
            child: _Home(
              overrides: config.deviceNameOverrides,
              onDisconnect: _onDisconnect,
            ),
          );
        }
        return OnboardingFlow(
          store: widget.store,
          initial: config,
          clientFactory: ref.read(clientFactoryProvider),
          onComplete: _onOnboardingComplete,
        );
      },
    );
  }
}

class _Home extends ConsumerWidget {
  final Map<String, String> overrides;
  final VoidCallback onDisconnect;

  const _Home({required this.overrides, required this.onDisconnect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(devicesSnapshotProvider);

    // Resolve the mode for the background gradient. Loading and error paths
    // fall back to `off` (neutral gradient) — we don't want to flash a heat
    // glow on a stale state before the first poll resolves.
    final mode = async.maybeWhen(
      data: (snapshot) => snapshot.devices.isEmpty
          ? DeviceMode.off
          : snapshot.devices.first.mode,
      orElse: () => DeviceMode.off,
    );

    return EmberBackground(
      mode: mode,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Rest Thermostat'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      onDisconnect: () {
                        Navigator.of(context).pop();
                        onDisconnect();
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: async.when(
              data: (snapshot) => _renderSnapshot(snapshot),
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _renderSnapshot(DevicesSnapshot snapshot) {
    if (snapshot.devices.isEmpty) return const Text('No devices');
    final d = snapshot.devices.first;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(displayNameFor(d, overrides)),
        Text('Current: ${d.currentTemperature}'),
        Text('Target: ${d.targetTemperature}'),
        Text('Mode: ${d.mode.toApi()}'),
      ],
    );
  }
}
