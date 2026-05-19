import 'package:flutter/material.dart';

void main() {
  runApp(const RestThermostatApp());
}

class RestThermostatApp extends StatelessWidget {
  const RestThermostatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rest Thermostat',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold();
  }
}
