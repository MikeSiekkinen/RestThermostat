import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'l10n/gen/app_localizations.dart';
import 'models/device.dart';
import 'onboarding/onboarding_flow.dart';
import 'screens/details/details_screen.dart';
import 'screens/home/home_body.dart';
import 'screens/main_shell.dart';
import 'screens/schedule/schedule_screen.dart';
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
      // App-level opaque background behind the whole Navigator. The ember theme
      // makes every Scaffold transparent (scaffoldBackgroundColor + canvasColor
      // = transparent) so the mode-aware EmberBackground on Home can show
      // through; but every OTHER route (onboarding, settings, logs, schedule)
      // then had nothing opaque behind it and rendered see-through — most
      // visibly on iOS, where route compositing exposes it (Issue #70). This
      // neutral base guarantees an opaque backdrop for every route and during
      // transitions; Home paints its own mode-colored EmberBackground on top.
      builder: (context, child) => EmberBackground(
        mode: DeviceMode.off,
        child: child ?? const SizedBox.shrink(),
      ),
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
          // No EmberBackground here — the app-level MaterialApp.builder base
          // (mode: off) already paints the identical neutral backdrop behind
          // this transparent Scaffold.
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
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
  // One PageController per tab: the three tabs live together in the shell's
  // `IndexedStack` (all mounted at once), so a single controller can't back
  // all of them (Issue #125). Each tab's swipe drives the shared
  // `activeDeviceSerialProvider`; the other controllers re-sync on the next
  // build via the post-frame `jumpToPage` in [_buildSwipeableTab].
  //
  // Created lazily on each tab's first multi-device build so `initialPage`
  // can be seeded to the restored active device — otherwise the fresh
  // controller paints index 0 for one frame before the post-frame sync, a
  // visible flash of the wrong device on cold start (CodeRabbit, PR #126).
  PageController? _homeController;
  PageController? _scheduleController;
  PageController? _detailsController;
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
    _homeController?.dispose();
    _scheduleController?.dispose();
    _detailsController?.dispose();
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
    // Keep the Home PageView in sync if the change came from the picker sheet
    // (the picker only exists on the Home tab). The Schedule/Details
    // controllers re-sync via the post-frame `jumpToPage` in
    // [_buildSwipeableTab] on the rebuild this triggers.
    final home = _homeController;
    final index = devices.indexWhere((d) => d.serial == serial);
    if (index >= 0 && home != null && home.hasClients) {
      final currentPage = home.page?.round() ?? 0;
      if (currentPage != index) {
        home.animateToPage(
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
                      homeTab: _buildHomeTab(
                        context,
                        snapshot.devices,
                        activeDevice,
                        activeSerial,
                      ),
                      scheduleTab: _buildScheduleTab(
                        context,
                        snapshot.devices,
                        activeSerial,
                      ),
                      detailsTab: _buildDetailsTab(
                        context,
                        snapshot.devices,
                        activeSerial,
                        lastSyncAt,
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

  /// Wraps a tab body in a horizontal device-swipe `PageView` when 2+ devices
  /// are connected, so the user can flip between thermostats from any tab
  /// (Issue #125 extends the Home-only swipe from Issue #15). A swipe writes
  /// the swiped-to serial through [_setActiveSerial] — i.e. into the shared
  /// `activeDeviceSerialProvider`, the single source of truth — so all three
  /// tabs and the persisted active serial stay in lockstep.
  ///
  /// Single-device: the plain [pageBuilder] body, no `PageView`.
  ///
  /// [controller] is per-tab because the three tabs are mounted together in
  /// the shell's `IndexedStack`; one controller can't back multiple viewports.
  /// The post-frame `jumpToPage` realigns this tab's controller with the
  /// active serial when it changed from another surface (another tab's swipe,
  /// or the Home picker sheet) rather than from this tab's own gesture.
  Widget _buildSwipeableTab({
    required List<Device> devices,
    required String? activeSerial,
    required PageController? Function() getController,
    required void Function(PageController) setController,
    required Widget Function(Device device) pageBuilder,
  }) {
    if (devices.length < 2) {
      final active = devices.firstWhere(
        (d) => d.serial == activeSerial,
        orElse: () => devices.first,
      );
      return pageBuilder(active);
    }
    final activeIndex = devices.indexWhere((d) => d.serial == activeSerial);
    final resolvedIndex = activeIndex >= 0 ? activeIndex : 0;

    // Create this tab's controller on its first multi-device build, seeding
    // `initialPage` to the active device so the first frame paints the right
    // device (no index-0 flash before the post-frame sync).
    var controller = getController();
    if (controller == null) {
      controller = PageController(initialPage: resolvedIndex);
      setController(controller);
    }
    final tabController = controller;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!tabController.hasClients) return;
      final currentPage = tabController.page?.round();
      if (currentPage != resolvedIndex) {
        tabController.jumpToPage(resolvedIndex);
      }
    });

    return PageView.builder(
      controller: tabController,
      itemCount: devices.length,
      onPageChanged: (index) {
        final serial = devices[index].serial;
        if (serial != activeSerial) {
          _setActiveSerial(serial, devices);
        }
      },
      // Each [pageBuilder] keys its child by `device.serial` so Flutter ties
      // page State to device identity, not to the index slot — a device-list
      // reorder can't bleed one thermostat's page state onto another
      // (CodeRabbit, PR #126).
      itemBuilder: (_, index) => pageBuilder(devices[index]),
    );
  }

  /// Builds the Home-tab body. Single-device: a plain `HomeBody`. Multi-
  /// device: a swipeable `PageView` (via [_buildSwipeableTab]) with the
  /// device-picker trigger + indicator dots threaded into each page.
  Widget _buildHomeTab(
    BuildContext context,
    List<Device> devices,
    Device activeDevice,
    String? activeSerial,
  ) {
    final multiDevice = devices.length >= 2;
    final activeIndex = devices.indexWhere((d) => d.serial == activeSerial);
    final resolvedIndex = activeIndex >= 0 ? activeIndex : 0;

    return _buildSwipeableTab(
      devices: devices,
      activeSerial: activeSerial,
      getController: () => _homeController,
      setController: (c) => _homeController = c,
      pageBuilder: (device) => HomeBody(
        key: ValueKey(device.serial),
        device: device,
        overrides: widget.overrides,
        onNameTap: multiDevice
            ? () => _openDevicePicker(context, devices, activeSerial)
            : null,
        indicatorDots: multiDevice
            ? DeviceIndicatorDots(
                count: devices.length,
                activeIndex: resolvedIndex,
                activeMode: activeDevice.mode,
              )
            : null,
      ),
    );
  }

  /// Builds the Schedule-tab body: swipeable between devices when 2+ are
  /// connected (Issue #125), otherwise a plain `ScheduleScreen`. With 2+
  /// devices the header device name is also tappable → the shared
  /// `DevicePickerSheet` (Issue #127), a non-gesture device switch at parity
  /// with Home for assistive-tech / switch-control users. No indicator dots.
  Widget _buildScheduleTab(
    BuildContext context,
    List<Device> devices,
    String? activeSerial,
  ) {
    final multiDevice = devices.length >= 2;
    return _buildSwipeableTab(
      devices: devices,
      activeSerial: activeSerial,
      getController: () => _scheduleController,
      setController: (c) => _scheduleController = c,
      pageBuilder: (device) => ScheduleScreen(
        key: ValueKey(device.serial),
        serial: device.serial,
        temperatureScale: device.temperatureScale,
        deviceMode: device.mode,
        scheduleMode: device.scheduleMode,
        capabilities: device.capabilities,
        device: device,
        overrides: widget.overrides,
        onDeviceNameTap: multiDevice
            ? () => _openDevicePicker(context, devices, activeSerial)
            : null,
      ),
    );
  }

  /// Builds the Details-tab body: swipeable between devices when 2+ are
  /// connected (Issue #125), otherwise a plain `DetailsScreen`. With 2+ devices
  /// the "CURRENT" header is tappable → the shared `DevicePickerSheet` (Issue
  /// #127), matching Home's non-gesture device switch. No indicator dots.
  Widget _buildDetailsTab(
    BuildContext context,
    List<Device> devices,
    String? activeSerial,
    DateTime? lastSyncAt,
  ) {
    final multiDevice = devices.length >= 2;
    return _buildSwipeableTab(
      devices: devices,
      activeSerial: activeSerial,
      getController: () => _detailsController,
      setController: (c) => _detailsController = c,
      pageBuilder: (device) => DetailsScreen(
        key: ValueKey(device.serial),
        device: device,
        lastSyncAt: lastSyncAt,
        overrides: widget.overrides,
        onDeviceNameTap: multiDevice
            ? () => _openDevicePicker(context, devices, activeSerial)
            : null,
      ),
    );
  }
}
