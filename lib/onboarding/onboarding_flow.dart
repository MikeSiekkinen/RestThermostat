import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_config.dart';
import '../models/device.dart';
import '../services/backup/backup_service.dart';
import '../services/nle_api_client.dart';
import '../services/nle_error.dart';
import '../services/nle_error_messages.dart';
import '../services/onboarding_store.dart';
import '../settings/backup_flow.dart';
import 'connect_outcome.dart';
import 'device_picker_screen.dart';
import 'server_setup_screen.dart';
import 'welcome_screen.dart';

typedef NleClientFactory =
    NleApiClient Function(String baseUrl, AuthConfig auth);

enum _Step { welcome, serverSetup, noDevices, devicePicker }

class OnboardingFlow extends StatefulWidget {
  final OnboardingStore store;
  final OnboardingConfig initial;
  final NleClientFactory clientFactory;
  final VoidCallback onComplete;

  /// Backup service for the welcome-screen "Restore from backup" affordance
  /// (Issue #109). When null, the affordance is hidden.
  final BackupService? backupService;

  /// Runs after a restore writes config, before [onComplete] rebuilds the app —
  /// the host uses it to refresh appearance providers that hydrated at startup.
  final Future<void> Function()? onRestoreApplied;

  const OnboardingFlow({
    super.key,
    required this.store,
    required this.initial,
    required this.clientFactory,
    required this.onComplete,
    this.backupService,
    this.onRestoreApplied,
  });

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late _Step _step;
  late String? _resumedUrl;
  late AuthConfig _resumedAuth;
  List<Device> _devices = const [];

  @override
  void initState() {
    super.initState();
    _resumedUrl = widget.initial.serverUrl;
    _resumedAuth = widget.initial.auth;
    // Mid-flow resume: if a URL is already persisted, skip Welcome and land
    // on Server Setup so the user can re-test with the saved values.
    _step = _resumedUrl == null ? _Step.welcome : _Step.serverSetup;
  }

  Future<ConnectOutcome> _attemptConnect(String url, AuthConfig auth) async {
    final client = widget.clientFactory(url, auth);
    try {
      final response = await client.getDevices();
      // Persist URL + auth now that the round-trip succeeded.
      await widget.store.saveServerUrl(url);
      await widget.store.saveAuth(auth);

      final devices = response.devices;
      if (devices.isEmpty) {
        if (!mounted) return const ConnectBlocking();
        setState(() => _step = _Step.noDevices);
        return const ConnectBlocking();
      }
      if (devices.length == 1) {
        await widget.store.saveActiveSerial(devices.first.serial);
        await widget.store.markComplete();
        widget.onComplete();
        return const ConnectSuccess();
      }
      if (!mounted) return const ConnectSuccess();
      setState(() {
        _devices = devices;
        _step = _Step.devicePicker;
      });
      return const ConnectSuccess();
    } on NleError catch (e) {
      if (!mounted) return const ConnectInlineError('');
      final l = AppLocalizations.of(context);
      return ConnectInlineError(connectErrorMessage(l, e));
    }
  }

  Future<void> _pickDevice(Device d) async {
    await widget.store.saveActiveSerial(d.serial);
    await widget.store.markComplete();
    widget.onComplete();
  }

  Future<void> _onRestore() async {
    final service = widget.backupService;
    if (service == null) return;
    final applied = await runBackupImport(
      context,
      service,
      onApplied: () async => widget.onRestoreApplied?.call(),
    );
    if (!applied || !mounted) return;
    final l = AppLocalizations.of(context);
    // Root ScaffoldMessenger survives the rebuild triggered by onComplete().
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.backupRestoredSnack)));
    // Config now marks onboarding complete → Bootstrap re-reads and lands Home.
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _Step.welcome => WelcomeScreen(
        onStart: () => setState(() => _step = _Step.serverSetup),
        onRestore: widget.backupService == null ? null : _onRestore,
      ),
      _Step.serverSetup => ServerSetupScreen(
        initialUrl: _resumedUrl,
        initialAuth: _resumedAuth,
        onConnect: _attemptConnect,
      ),
      _Step.noDevices => NoDevicesScreen(
        onBack: () => setState(() => _step = _Step.serverSetup),
      ),
      _Step.devicePicker => DevicePickerScreen(
        devices: _devices,
        onPick: _pickDevice,
      ),
    };
  }
}
