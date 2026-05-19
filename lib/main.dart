import 'package:flutter/material.dart';

import 'models/devices_response.dart';
import 'services/nle_api_client.dart';

// TODO(#4): replace with onboarding-configured URL.
const _devServerUrl = 'http://192.168.1.100:8082';

void main() {
  runApp(const RestThermostatApp());
}

class RestThermostatApp extends StatelessWidget {
  final NleApiClient? client;

  const RestThermostatApp({super.key, this.client});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rest Thermostat',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: _Home(
        client: client ?? NleApiClient.create(baseUrl: _devServerUrl),
      ),
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
