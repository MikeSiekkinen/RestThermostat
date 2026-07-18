import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/services/mac_formatter.dart';

void main() {
  group('formatMacAddress', () {
    test('formats bare 12-digit hex as lowercase colon-separated pairs', () {
      expect(formatMacAddress('18b430aabbcc'), '18:b4:30:aa:bb:cc');
    });

    test('lowercases uppercase hex input', () {
      expect(formatMacAddress('18B430AABBCC'), '18:b4:30:aa:bb:cc');
    });

    test('returns already-separated MAC verbatim', () {
      expect(formatMacAddress('18:b4:30:aa:bb:cc'), '18:b4:30:aa:bb:cc');
    });

    test('returns too-short value verbatim', () {
      expect(formatMacAddress('18b430'), '18b430');
    });

    test('returns non-hex value verbatim', () {
      expect(formatMacAddress('not-a-mac-addr'), 'not-a-mac-addr');
    });

    test('returns empty string verbatim', () {
      expect(formatMacAddress(''), '');
    });
  });
}
