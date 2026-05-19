import 'package:flutter/material.dart';

import '../models/device.dart';

class DevicePickerScreen extends StatelessWidget {
  final List<Device> devices;
  final ValueChanged<Device> onPick;

  const DevicePickerScreen({
    super.key,
    required this.devices,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a thermostat')),
      body: SafeArea(
        child: ListView.separated(
          itemCount: devices.length,
          separatorBuilder: (_, _) => const Divider(height: 0),
          itemBuilder: (context, i) {
            final d = devices[i];
            return ListTile(
              title: Text(d.name ?? 'unnamed'),
              subtitle: Text(d.serial),
              onTap: () => onPick(d),
            );
          },
        ),
      ),
    );
  }
}

class NoDevicesScreen extends StatelessWidget {
  final VoidCallback onBack;

  const NoDevicesScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'No thermostats registered.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Pair your Nest Gen 1/2 with your NoLongerEvil server before '
                'continuing.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              OutlinedButton(onPressed: onBack, child: const Text('Go back')),
            ],
          ),
        ),
      ),
    );
  }
}
