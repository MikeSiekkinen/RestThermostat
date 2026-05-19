import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onStart;
  static const nleDocsUrl = 'https://docs.nolongerevil.com';

  const WelcomeScreen({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                'Rest Thermostat',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Connect to your NoLongerEvil server to control your '
                'Gen 1/2 Nest thermostats.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const SelectableText(
                'Docs: $nleDocsUrl',
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton(
                onPressed: onStart,
                child: const Text('Get started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
