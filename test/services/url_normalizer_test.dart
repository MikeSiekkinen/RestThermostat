import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/services/url_normalizer.dart';

void main() {
  group('normalizeServerUrl', () {
    test('adds http scheme and default port when both missing', () {
      expect(normalizeServerUrl('nest.home'), 'http://nest.home:8082');
    });

    test(
      'defaults https without a port to 443 (reverse proxy / Cloudflare)',
      () {
        expect(
          normalizeServerUrl('https://nest.example.com'),
          'https://nest.example.com:443',
        );
      },
    );

    test('defaults http without a port to 8082 (direct-LAN NLE)', () {
      expect(normalizeServerUrl('http://nest.home'), 'http://nest.home:8082');
    });

    test('preserves an explicit port on https', () {
      expect(
        normalizeServerUrl('https://nest.example.com:8443'),
        'https://nest.example.com:8443',
      );
    });

    test('preserves explicit non-default port', () {
      expect(
        normalizeServerUrl('http://nest.home:9000'),
        'http://nest.home:9000',
      );
    });

    test('handles bare IP', () {
      expect(normalizeServerUrl('192.168.1.42'), 'http://192.168.1.42:8082');
    });

    test('strips trailing slash', () {
      expect(
        normalizeServerUrl('http://nest.home:8082/'),
        'http://nest.home:8082',
      );
    });

    test('trims surrounding whitespace', () {
      expect(normalizeServerUrl('  nest.home  '), 'http://nest.home:8082');
    });

    test('rejects empty input', () {
      expect(
        () => normalizeServerUrl(''),
        throwsA(isA<UrlNormalizationException>()),
      );
    });

    test('rejects whitespace-only input', () {
      expect(
        () => normalizeServerUrl('   '),
        throwsA(isA<UrlNormalizationException>()),
      );
    });

    test('rejects ftp scheme', () {
      expect(
        () => normalizeServerUrl('ftp://nest.home'),
        throwsA(isA<UrlNormalizationException>()),
      );
    });

    test('rejects paths beyond root', () {
      expect(
        () => normalizeServerUrl('http://nest.home:8082/api/devices'),
        throwsA(isA<UrlNormalizationException>()),
      );
    });
  });
}
