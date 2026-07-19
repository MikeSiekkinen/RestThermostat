import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'l10n/gen/app_localizations.dart';
import 'models/device.dart';
import 'onboarding/onboarding_flow.dart';
import 'screens/home/home_body.dart';
import 'screens/main_shell.dart';
import 'services/app_info.dart';
import 'services/backup/backup_service.dart';
import 'services/onboarding_store.dart';
import 'settings/numeral_font.dart';
import 'settings/settings_screen.dart';
import 'settings/time_field_palette.dart';
import 'state/auth_failure_coordinator.dart';
import 'state/devices_snapshot.dart';
import 'state/lifecycle_bridge.dart';
import 'state/providers.dart';
import 'theme/ember_theme.dart';
import 'widgets/device_indicator_dots.dart';
import 'widgets/device_picker_sheet.dart';
import 'widgets/ember_background.dart';
import 'widgets/stale_state_pill.dart';

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
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      themeMode: ThemeMode.dark,
      darkTheme: emberTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
      // Seed the active-serial provider from persisted state. The fallback
      // path inside _Home reconciles this against the live snapshot once the
      // first /api/devices fetch resolves (DESIGN §4.5).
      ref.read(activeDeviceSerialProvider.notifier).set(config.activeSerial);
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
              store: widget.store,
              onDisconnect: _onDisconnect,
            ),
          );
        }
        return OnboardingFlow(
          store: widget.store,
          initial: config,
          clientFactory: ref.read(clientFactoryProvider),
          onComplete: _onOnboardingComplete,
          // Built from widget.store (not backupServiceProvider) so Bootstrap
          // stays self-contained — it already persists through widget.store and
          // doesn't require the provider override to be wired.
          backupService: BackupService(store: widget.store),
          onRestoreApplied: () async {
            // Appearance notifiers hydrated at startup with the fresh-install
            // defaults; a restore rewrites their prefs, so force a re-read.
            ref.invalidate(numeralFontProvider);
            ref.invalidate(timeFieldPaletteProvider);
          },
        );
      },
    );
  }
}

class _Home extends ConsumerStatefulWidget {
  final Map<String, String> overrides;
  final OnboardingStore store;
  final VoidCallback onDisconnect;

  const _Home({
    required this.overrides,
    required this.store,
    required this.onDisconnect,
  });

  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> {
  late final PageController _pageController = PageController();
  bool _fallbackSnackbarShown = false;
  AuthFailureCoordinator? _authCoordinator;
  VoidCallback? _authListener;

  @override
  void initState() {
    super.initState();
    // Hook the cross-cutting auth-failure signal. Fires from either the
    // polling source (background 401) or any interactive widget's catch
    // block (write 401). De-duplication lives in the coordinator. The
    // coordinator reference is cached in a field so dispose() can detach
    // without needing `ref` (which is unsafe post-deactivation).
    _authCoordinator = ref.read(authFailureCoordinatorProvider);
    _authListener = _showAuthFailureSnackbar;
    _authCoordinator!.addListener(_authListener!);
  }

  @override
  void dispose() {
    if (_authCoordinator != null && _authListener != null) {
      _authCoordinator!.removeListener(_authListener!);
    }
    _pageController.dispose();
    super.dispose();
  }

  void _showAuthFailureSnackbar() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final l = AppLocalizations.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.homeAuthFailed),
        action: SnackBarAction(
          label: l.homeAuthOpenSettingsAction,
          onPressed: () {
            ref.read(authFailureCoordinatorProvider).reset();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  initiallyExpandAuth: true,
                  onDisconnect: () {
                    Navigator.of(context).pop();
                    widget.onDisconnect();
                  },
                  onConfigRestored: () {
                    Navigator.of(context).pop();
                    widget.onDisconnect();
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// DESIGN §4.5: if the persisted serial isn't in the latest snapshot,
  /// fall back to the first device and surface a one-time snackbar. Called
  /// from build via a post-frame callback so we don't mutate provider state
  /// during widget build.
  void _reconcileActiveSerial(DevicesSnapshot snapshot) {
    if (snapshot.devices.isEmpty) return;
    final current = ref.read(activeDeviceSerialProvider);
    final inSnapshot =
        current != null && snapshot.devices.any((d) => d.serial == current);
    if (inSnapshot) return;

    final firstSerial = snapshot.devices.first.serial;
    final wasMismatch = current != null && !inSnapshot;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(activeDeviceSerialProvider.notifier).set(firstSerial);
      // Only surface the snackbar when the user actually had a persisted
      // serial that's no longer present. The "no persisted serial yet"
      // case (just-finished onboarding) silently seeds to first.
      if (wasMismatch && !_fallbackSnackbarShown) {
        _fallbackSnackbarShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).homeActiveDeviceFallback,
            ),
          ),
        );
      }
    });
  }

  Future<void> _openDevicePicker(
    BuildContext context,
    List<Device> devices,
    String? activeSerial,
  ) async {
    final picked = await DevicePickerSheet.show(
      context,
      devices: devices,
      activeSerial: activeSerial,
      nameOverrides: widget.overrides,
    );
    if (picked == null || picked == activeSerial) return;
    await _setActiveSerial(picked, devices);
  }

  Future<void> _setActiveSerial(String serial, List<Device> devices) async {
    ref.read(activeDeviceSerialProvider.notifier).set(serial);
    // Best-effort persistence; failures here aren't user-facing — the next
    // launch falls back to the §4.5 path.
    try {
      await widget.store.saveActiveSerial(serial);
    } catch (_) {
      // Swallow — the in-memory provider is authoritative for this session.
    }
    // Keep PageView in sync if the change came from the picker sheet.
    final index = devices.indexWhere((d) => d.serial == serial);
    if (index >= 0 && _pageController.hasClients) {
      final currentPage = _pageController.page?.round() ?? 0;
      if (currentPage != index) {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(devicesSnapshotProvider);
    final activeSerial = ref.watch(activeDeviceSerialProvider);

    final devices = async.maybeWhen(
      data: (snapshot) => snapshot.devices,
      orElse: () => const <Device>[],
    );
    if (devices.isNotEmpty) {
      _reconcileActiveSerial(async.requireValue);
    }

    final activeDevice = devices.isEmpty
        ? null
        : devices.firstWhere(
            (d) => d.serial == activeSerial,
            orElse: () => devices.first,
          );
    final mode = activeDevice?.mode ?? DeviceMode.off;
    final lastSyncAt = async.maybeWhen<DateTime?>(
      data: (snapshot) => snapshot.fetchedAt,
      orElse: () => null,
    );

    return EmberBackground(
      mode: mode,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(AppLocalizations.of(context).homeAppBarTitle),
          actions: [
            IconButton(
              tooltip: AppLocalizations.of(context).homeSettingsTooltip,
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      onDisconnect: () {
                        Navigator.of(context).pop();
                        widget.onDisconnect();
                      },
                      onConfigRestored: () {
                        Navigator.of(context).pop();
                        widget.onDisconnect();
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
            data: (snapshot) {
              if (snapshot.devices.isEmpty) {
                return Center(
                  child: Text(AppLocalizations.of(context).homeNoDevices),
                );
              }
              return Column(
                children: [
                  const StaleStatePill(),
                  Expanded(
                    child: MainShell(
                      device: activeDevice!,
                      overrides: widget.overrides,
                      lastSyncAt: lastSyncAt,
                      homeTab: _buildHomeTab(
                        context,
                        snapshot.devices,
                        activeDevice,
                        activeSerial,
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(AppLocalizations.of(context).homeErrorPrefix(e)),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the Home-tab body. Single-device: a plain `HomeBody`. Multi-
  /// device: wraps `HomeBody` in a `PageView` that drives
  /// `activeDeviceSerialProvider` on swipe, and threads the device-picker
  /// trigger + indicator dots into the body. The PageController is reused
  /// across rebuilds so picker-driven changes can animate to the right
  /// page rather than resetting.
  Widget _buildHomeTab(
    BuildContext context,
    List<Device> devices,
    Device activeDevice,
    String? activeSerial,
  ) {
    if (devices.length < 2) {
      return HomeBody(device: activeDevice, overrides: widget.overrides);
    }
    final activeIndex = devices.indexWhere((d) => d.serial == activeSerial);
    final resolvedIndex = activeIndex >= 0 ? activeIndex : 0;

    // Keep the PageController in sync with provider-driven changes (e.g.
    // picker-sheet selection). Without this jump, picking a row in the
    // sheet wouldn't move the page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_pageController.hasClients) return;
      final currentPage = _pageController.page?.round();
      if (currentPage != resolvedIndex) {
        _pageController.jumpToPage(resolvedIndex);
      }
    });

    return PageView.builder(
      controller: _pageController,
      itemCount: devices.length,
      onPageChanged: (index) {
        final serial = devices[index].serial;
        if (serial != activeSerial) {
          _setActiveSerial(serial, devices);
        }
      },
      itemBuilder: (_, index) {
        final d = devices[index];
        return HomeBody(
          device: d,
          overrides: widget.overrides,
          onNameTap: () => _openDevicePicker(context, devices, activeSerial),
          indicatorDots: DeviceIndicatorDots(
            count: devices.length,
            activeIndex: resolvedIndex,
            activeMode: activeDevice.mode,
          ),
        );
      },
    );
  }
}
