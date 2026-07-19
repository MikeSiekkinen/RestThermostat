import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/services/backup/backup_codec.dart';
import 'package:rest_thermostat/services/backup/backup_errors.dart';

import 'backup_test_support.dart';

void main() {
  group('BackupCodec', () {
    test('round-trips a payload through encrypt → decrypt', () async {
      final codec = testCodec();
      final payload = {
        'server_url': 'https://nest.example.com',
        'auth': {'type': 'bearer', 'token': 'abc123'},
        'nested': {
          'list': [1, 2, 3],
        },
      };

      final envelope = await codec.encrypt(payload, 'correct horse');
      final decoded = await codec.decrypt(envelope, 'correct horse');

      expect(decoded, equals(payload));
    });

    test('envelope has the documented plaintext header', () async {
      final envelope = await testCodec().encrypt({'x': 1}, 'pw12345678');
      final header = jsonDecode(envelope) as Map<String, dynamic>;

      expect(header['app'], 'rest-thermostat');
      expect(header['schema'], 1);
      expect(header['kdf'], 'argon2id');
      expect(header['cipher'], 'xchacha20poly1305');
      expect(header['params'], {'m': 64, 't': 1, 'p': 1});
      expect(header['salt'], isA<String>());
      expect(header['nonce'], isA<String>());
      expect(header['ciphertext'], isA<String>());
    });

    test('a wrong passphrase throws BackupWrongPassphrase', () async {
      final codec = testCodec();
      final envelope = await codec.encrypt({'secret': 'x'}, 'right-pass');

      expect(
        () => codec.decrypt(envelope, 'wrong-pass'),
        throwsA(isA<BackupWrongPassphrase>()),
      );
    });

    test('tampered ciphertext fails closed (wrong-passphrase path)', () async {
      final codec = testCodec();
      final envelope = await codec.encrypt({'secret': 'x'}, 'pw');
      final header = jsonDecode(envelope) as Map<String, dynamic>;

      // Flip one byte of the ciphertext blob and re-encode.
      final blob = base64Decode(header['ciphertext'] as String);
      blob[0] ^= 0xff;
      header['ciphertext'] = base64Encode(blob);

      expect(
        () => codec.decrypt(jsonEncode(header), 'pw'),
        throwsA(isA<BackupWrongPassphrase>()),
      );
    });

    test('a foreign app header is rejected before decryption', () async {
      final codec = testCodec();
      final foreign = jsonEncode({
        'app': 'some-other-app',
        'schema': 1,
        'kdf': 'argon2id',
        'cipher': 'xchacha20poly1305',
        'salt': base64Encode([1, 2, 3]),
        'params': {'m': 64, 't': 1, 'p': 1},
        'nonce': base64Encode(List.filled(24, 0)),
        'ciphertext': base64Encode(List.filled(32, 0)),
      });

      expect(
        () => codec.decrypt(foreign, 'anything'),
        throwsA(isA<BackupForeignFile>()),
      );
    });

    test('a too-new schema is rejected before decryption', () async {
      final codec = testCodec();
      final tooNew = jsonEncode({
        'app': 'rest-thermostat',
        'schema': 99,
        'kdf': 'argon2id',
        'cipher': 'xchacha20poly1305',
        'salt': base64Encode([1, 2, 3]),
        'params': {'m': 64, 't': 1, 'p': 1},
        'nonce': base64Encode(List.filled(24, 0)),
        'ciphertext': base64Encode(List.filled(32, 0)),
      });

      expect(
        () => codec.decrypt(tooNew, 'anything'),
        throwsA(
          isA<BackupTooNewSchema>()
              .having((e) => e.fileSchema, 'fileSchema', 99)
              .having((e) => e.supportedSchema, 'supportedSchema', 1),
        ),
      );
    });

    test('non-JSON input throws BackupMalformed', () async {
      expect(
        () => testCodec().decrypt('not json at all', 'pw'),
        throwsA(isA<BackupMalformed>()),
      );
    });

    test('missing schema throws BackupMalformed', () async {
      final noSchema = jsonEncode({'app': 'rest-thermostat'});
      expect(
        () => testCodec().decrypt(noSchema, 'pw'),
        throwsA(isA<BackupMalformed>()),
      );
    });

    test(
      'out-of-bounds Argon2id params are rejected before the KDF runs',
      () async {
        // A hand-crafted file with enormous cost params would OOM/hang the app if
        // the KDF ran; it must be rejected as malformed instead.
        String envelopeWith(Map<String, dynamic> params) => jsonEncode({
          'app': 'rest-thermostat',
          'schema': 1,
          'kdf': 'argon2id',
          'cipher': 'xchacha20poly1305',
          'salt': base64Encode(List.filled(16, 0)),
          'params': params,
          'nonce': base64Encode(List.filled(24, 0)),
          'ciphertext': base64Encode(List.filled(32, 0)),
        });

        for (final params in <Map<String, dynamic>>[
          {'m': 2000000000, 't': 2, 'p': 1}, // ~2 TB memory
          {'m': 19456, 't': 100000, 'p': 1}, // absurd iterations
          {'m': 19456, 't': 2, 'p': 4096}, // absurd parallelism
        ]) {
          expect(
            () => testCodec().decrypt(envelopeWith(params), 'anything'),
            throwsA(isA<BackupMalformed>()),
            reason: 'params $params should be rejected',
          );
        }
      },
    );

    test('no plaintext secret leaks into the envelope', () async {
      const secret = 'SUPER-SECRET-TOKEN-9f3a1c';
      final envelope = await testCodec().encrypt({
        'auth': {'type': 'bearer', 'token': secret},
      }, 'a strong passphrase');

      expect(envelope.contains(secret), isFalse);
      // Also guard against a partial/encoded leak of the distinctive core.
      expect(envelope.contains('9f3a1c'), isFalse);
    });

    test('different salts/nonces produce different ciphertext', () async {
      // Real randomness (not the fixed test generator): same payload +
      // passphrase must still yield distinct envelopes.
      final codec = BackupCodec(
        params: testParams,
        keyDeriver: inlineKeyDeriver,
      );
      final a = await codec.encrypt({'x': 1}, 'pw');
      final b = await codec.encrypt({'x': 1}, 'pw');
      expect(a, isNot(equals(b)));

      // Both still decrypt correctly.
      expect(await codec.decrypt(a, 'pw'), {'x': 1});
      expect(await codec.decrypt(b, 'pw'), {'x': 1});
    });
  });
}
