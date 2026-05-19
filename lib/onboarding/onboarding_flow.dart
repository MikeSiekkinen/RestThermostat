import 'package:flutter/material.dart';

import '../models/auth_config.dart';
import '../models/device.dart';
import '../services/nle_api_client.dart';
import '../services/nle_error.dart';
import '../services/onboarding_store.dart';
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

  const OnboardingFlow({
    super.key,
    required this.store,
    required this.initial,
    required this.clientFactory,
    required this.onComplete,
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
    } on NleAuthError catch (_) {
      return const ConnectInlineError('Authentication failed.');
    } on NleError catch (_) {
      return const ConnectInlineError("Couldn't reach server.");
    }
  }

  Future<void> _pickDevice(Device d) async {
    await widget.store.saveActiveSerial(d.serial);
    await widget.store.markComplete();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _Step.welcome => WelcomeScreen(
        onStart: () => setState(() => _step = _Step.serverSetup),
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
