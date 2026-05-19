import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models/device.dart';
import 'onboarding/onboarding_flow.dart';
import 'screens/schedule/schedule_screen.dart';
import 'services/app_info.dart';
import 'services/onboarding_store.dart';
import 'settings/settings_screen.dart';
import 'state/devices_snapshot.dart';
import 'state/lifecycle_bridge.dart';
import 'state/providers.dart';
import 'theme/ember_theme.dart';
import 'widgets/ember_background.dart';
import 'widgets/fan_widget.dart';
import 'widgets/mode_pills.dart';
import 'widgets/status_row.dart';
import 'widgets/temperature_dial.dart';

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
              activeSerial: config.activeSerial,
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
  final String? activeSerial;
  final VoidCallback onDisconnect;

  const _Home({
    required this.overrides,
    required this.activeSerial,
    required this.onDisconnect,
  });

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

    // Active serial for the Schedule entry-point. Prefer the persisted
    // active-device value; fall back to the first device in the snapshot when
    // onboarding hasn't recorded one yet. Temporary wiring — #16 will replace
    // this with a proper `activeSerial` provider.
    final scheduleSerial =
        activeSerial ??
        async.maybeWhen(
          data: (snapshot) =>
              snapshot.devices.isEmpty ? null : snapshot.devices.first.serial,
          orElse: () => null,
        );
    final scheduleDevice = async.maybeWhen<Device?>(
      data: (snapshot) {
        if (snapshot.devices.isEmpty) return null;
        return snapshot.devices.firstWhere(
          (d) => d.serial == scheduleSerial,
          orElse: () => snapshot.devices.first,
        );
      },
      orElse: () => null,
    );
    final scheduleScale = scheduleDevice?.temperatureScale ?? 'F';
    final scheduleMode = scheduleDevice?.mode ?? DeviceMode.heat;
    final scheduleCapabilities =
        scheduleDevice?.capabilities ??
        const Capabilities(
          canHeat: true,
          canCool: false,
          hasFan: false,
          hasEmerHeat: false,
          hasHumidifier: false,
          hasDehumidifier: false,
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
            if (scheduleSerial != null)
              IconButton(
                tooltip: 'Schedule',
                icon: const Icon(Icons.calendar_month),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ScheduleScreen(
                        serial: scheduleSerial,
                        temperatureScale: scheduleScale,
                        deviceMode: scheduleMode,
                        capabilities: scheduleCapabilities,
                      ),
                    ),
                  );
                },
              ),
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
          child: async.when(
            data: (snapshot) => _renderSnapshot(context, snapshot),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ),
    );
  }

  Widget _renderSnapshot(BuildContext context, DevicesSnapshot snapshot) {
    if (snapshot.devices.isEmpty) return const Text('No devices');
    // Resolve which device to show. Prefer the persisted active serial (set
    // during onboarding); fall back to the first device in the snapshot.
    // DESIGN §4.5 has a one-time bounce to onboarding when the persisted
    // serial isn't in the snapshot — deferred to a later ticket. For now
    // we just degrade gracefully to "first" rather than blowing up.
    final d = snapshot.devices.firstWhere(
      (device) => device.serial == activeSerial,
      orElse: () => snapshot.devices.first,
    );
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                StatusRow(device: d, nameOverrides: overrides),
                const SizedBox(height: 24),
                // Cap the dial at the §10.3 ~240dp diameter, but let it shrink
                // on narrower viewports rather than overflowing.
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: TemperatureDial.preferredDiameter,
                    maxHeight: TemperatureDial.preferredDiameter,
                  ),
                  child: TemperatureDial(
                    currentTemperatureCelsius: d.currentTemperature,
                    targetTemperatureCelsius: d.targetTemperature,
                    mode: d.mode,
                    displayUnit: d.temperatureScale,
                    capabilities: d.capabilities,
                  ),
                ),
                const SizedBox(height: 24),
                // Mode pills are read-only in this ticket; #12 will wire taps
                // to `POST /command set_mode`. Pass a no-op so the row stays
                // tappable-looking while the action is plumbed in a follow-up.
                ModePills(
                  currentMode: d.mode,
                  capabilities: d.capabilities,
                  onModeTap: (_) {},
                ),
              ],
            ),
          ),
        ),
        // Fan widget at the top-right of the body per DESIGN §10.2. Hidden
        // automatically by FanWidget when `has_fan = false`. Tap behavior
        // arrives in issue #13.
        Positioned(top: 16, right: 16, child: FanWidget(device: d)),
      ],
    );
  }
}
