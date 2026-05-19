import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/auth_config.dart';

void main() {
  test('AuthNone produces no header', () {
    expect(const AuthNone().authorizationHeader, isNull);
    expect(const AuthNone().tag, 'none');
  });

  test('AuthBasic emits RFC 7617 base64-encoded credentials', () {
    const auth = AuthBasic(username: 'mike', password: 'hunter2');
    final expected = 'Basic ${base64Encode(utf8.encode('mike:hunter2'))}';
    expect(auth.authorizationHeader, expected);
    expect(auth.tag, 'basic');
  });

  test('AuthBearer emits Bearer token unchanged', () {
    const auth = AuthBearer(token: 'eyJabc.def');
    expect(auth.authorizationHeader, 'Bearer eyJabc.def');
    expect(auth.tag, 'bearer');
  });
}
