import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:rest_thermostat/main.dart';
import 'package:rest_thermostat/services/nle_api_client.dart';

void main() {
  testWidgets('renders first device fields from /api/devices', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
    final adapter = DioAdapter(dio: dio);
    final body = jsonDecode(
      File('test/fixtures/devices_one.json').readAsStringSync(),
    );
    adapter.onGet('/api/devices', (server) => server.reply(200, body));

    await tester.pumpWidget(RestThermostatApp(client: NleApiClient(dio: dio)));
    await tester.pumpAndSettle();

    expect(find.text('Upstairs'), findsOneWidget);
    expect(find.textContaining('Current: 24.76'), findsOneWidget);
    expect(find.textContaining('Target: 24.44'), findsOneWidget);
    expect(find.text('Mode: cool'), findsOneWidget);
  });

  testWidgets('shows error text on network failure', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local:8082'));
    final adapter = DioAdapter(dio: dio);
    adapter.onGet(
      '/api/devices',
      (server) => server.reply(500, {'error': 'boom'}),
    );

    await tester.pumpWidget(RestThermostatApp(client: NleApiClient(dio: dio)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Error:'), findsOneWidget);
  });
}
