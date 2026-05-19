import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/state/devices_snapshot.dart';

void main() {
  test('fromResponseJson parses fixture and tags metadata', () {
    final body =
        jsonDecode(File('test/fixtures/devices_one.json').readAsStringSync())
            as Map<String, dynamic>;
    final fetchedAt = DateTime.utc(2026, 5, 19, 1, 0);

    final snapshot = DevicesSnapshot.fromResponseJson(
      json: body,
      fetchedAt: fetchedAt,
      fromCache: true,
    );

    expect(snapshot.devices, hasLength(1));
    expect(snapshot.devices.first.name, 'Upstairs');
    expect(snapshot.fetchedAt, fetchedAt);
    expect(snapshot.fromCache, isTrue);
  });
}
