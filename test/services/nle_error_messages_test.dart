import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations_en.dart';
import 'package:rest_thermostat/services/nle_error.dart';
import 'package:rest_thermostat/services/nle_error_messages.dart';

void main() {
  final l = AppLocalizationsEn();

  NleError network(DioExceptionType type, {Object? error}) {
    return NleError.fromDio(
      DioException(
        requestOptions: RequestOptions(
          path: '/api/devices',
          baseUrl: 'https://nest.jmcnal.ly:443',
        ),
        type: type,
        error: error,
      ),
    );
  }

  test('auth error → generic auth copy', () {
    final msg = connectErrorMessage(l, const NleAuthError(statusCode: 401));
    expect(msg, l.connectFailedAuth);
  });

  test('Cloudflare Access gate → service-token guidance copy', () {
    final msg = connectErrorMessage(
      l,
      const NleAuthError(statusCode: 302, isCloudflareAccess: true),
    );
    expect(msg, l.connectFailedCloudflareAccess);
    expect(msg.toLowerCase(), contains('cloudflare access'));
  });

  test('connection refused → refused copy including host:port', () {
    final msg = connectErrorMessage(
      l,
      network(
        DioExceptionType.connectionError,
        error: const SocketException(
          'Connection refused',
          osError: OSError('Connection refused', 61),
        ),
      ),
    );
    expect(msg, contains('nest.jmcnal.ly:443'));
    expect(msg.toLowerCase(), contains('refused'));
  });

  test('DNS failure → name-not-found copy', () {
    final msg = connectErrorMessage(
      l,
      network(
        DioExceptionType.connectionError,
        error: const SocketException("Failed host lookup: 'nest.jmcnal.ly'"),
      ),
    );
    expect(msg, contains('nest.jmcnal.ly:443'));
    expect(msg, l.connectFailedDns('nest.jmcnal.ly:443'));
  });

  test('timeout → timeout copy', () {
    final msg = connectErrorMessage(
      l,
      network(DioExceptionType.receiveTimeout),
    );
    expect(msg, l.connectFailedTimeout('nest.jmcnal.ly:443'));
  });

  test('TLS failure → tls copy', () {
    final msg = connectErrorMessage(
      l,
      network(DioExceptionType.badCertificate),
    );
    expect(msg, l.connectFailedTls('nest.jmcnal.ly:443'));
  });

  test('non-network NleError → generic unreachable copy', () {
    expect(
      connectErrorMessage(l, const NleServerError(statusCode: 500)),
      l.connectFailedUnreachable,
    );
    expect(
      connectErrorMessage(l, const NleParseError(responseExcerpt: 'oops')),
      l.connectFailedUnreachable,
    );
  });

  test('non-Cloudflare redirect → redirect copy naming the target, '
      'not auth copy', () {
    final msg = connectErrorMessage(
      l,
      const NleRedirectError(statusCode: 301, target: 'nest.home:80'),
    );
    expect(msg, l.connectFailedRedirect('nest.home:80'));
    expect(msg.toLowerCase(), contains('redirect'));
    expect(msg.toLowerCase(), isNot(contains('authentication')));
  });

  test('sendTimeout and transformTimeout → timeout copy', () {
    expect(
      connectErrorMessage(l, network(DioExceptionType.sendTimeout)),
      l.connectFailedTimeout('nest.jmcnal.ly:443'),
    );
    expect(
      connectErrorMessage(l, network(DioExceptionType.transformTimeout)),
      l.connectFailedTimeout('nest.jmcnal.ly:443'),
    );
  });

  test('unclassified network failure → catch-all network copy', () {
    final msg = connectErrorMessage(
      l,
      network(DioExceptionType.connectionError, error: 'reset by peer'),
    );
    expect(msg, l.connectFailedNetwork('nest.jmcnal.ly:443'));
  });

  test('Linux ECONNREFUSED (errno 111) → refused copy', () {
    final msg = connectErrorMessage(
      l,
      network(
        DioExceptionType.connectionError,
        error: const SocketException(
          'Connection failed',
          osError: OSError('Connection refused', 111),
        ),
      ),
    );
    expect(msg, l.connectFailedRefused('nest.jmcnal.ly:443'));
  });

  test('unknown target renders as "?" instead of an empty string', () {
    final err = NleError.fromDio(
      DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionTimeout,
      ),
    );
    expect(connectErrorMessage(l, err), l.connectFailedTimeout('?'));
  });
}
