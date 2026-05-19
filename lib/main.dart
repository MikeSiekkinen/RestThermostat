import 'package:flutter/material.dart';

import 'models/auth_config.dart';
import 'models/devices_response.dart';
import 'onboarding/onboarding_flow.dart';
import 'services/nle_api_client.dart';
import 'services/onboarding_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RestThermostatApp());
}

NleApiClient _defaultClientFactory(String baseUrl, AuthConfig auth) =>
    NleApiClient.create(
      baseUrl: baseUrl,
      authorizationHeader: auth.authorizationHeader,
    );

class RestThermostatApp extends StatelessWidget {
  final OnboardingStore? store;
  final NleClientFactory? clientFactory;

  const RestThermostatApp({super.key, this.store, this.clientFactory});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rest Thermostat',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: _Bootstrap(
        store: store ?? FlutterOnboardingStore(),
        clientFactory: clientFactory ?? _defaultClientFactory,
      ),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  final OnboardingStore store;
  final NleClientFactory clientFactory;

  const _Bootstrap({required this.store, required this.clientFactory});

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<OnboardingConfig> _configFuture;

  @override
  void initState() {
    super.initState();
    _configFuture = widget.store.read();
  }

  void _onOnboardingComplete() {
    setState(() {
      _configFuture = widget.store.read();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OnboardingConfig>(
      future: _configFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final config = snapshot.data!;
        if (config.isComplete && config.serverUrl != null) {
          return _Home(
            client: widget.clientFactory(config.serverUrl!, config.auth),
          );
        }
        return OnboardingFlow(
          store: widget.store,
          initial: config,
          clientFactory: widget.clientFactory,
          onComplete: _onOnboardingComplete,
        );
      },
    );
  }
}

class _Home extends StatefulWidget {
  final NleApiClient client;
  const _Home({required this.client});

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  late final Future<DevicesResponse> _future = widget.client.getDevices();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: FutureBuilder<DevicesResponse>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const CircularProgressIndicator();
              }
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              final devices = snapshot.data!.devices;
              if (devices.isEmpty) {
                return const Text('No devices');
              }
              final d = devices.first;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(d.name ?? 'unnamed'),
                  Text('Current: ${d.currentTemperature}'),
                  Text('Target: ${d.targetTemperature}'),
                  Text('Mode: ${d.mode.toApi()}'),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
