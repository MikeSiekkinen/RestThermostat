import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rest_thermostat/main.dart';

void main() {
  testWidgets('App builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(const RestThermostatApp());
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
