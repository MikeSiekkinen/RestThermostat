import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:rest_thermostat/services/backup/backup_codec.dart';

/// Argon2id params small enough to run in milliseconds under test. The real
/// production params (`Argon2idParams.owaspDefault`) take ~1 s by design, which
/// would make the suite crawl. Because the codec stores params in the envelope,
/// a file made with these decrypts fine regardless.
const testParams = Argon2idParams(memory: 64, iterations: 1, parallelism: 1);

/// Runs Argon2id inline instead of on a `compute` isolate, so tests exercise the
/// real KDF without isolate spin-up overhead or flakiness.
Future<Uint8List> inlineKeyDeriver(
  Argon2idParams params,
  String passphrase,
  Uint8List salt,
) async {
  final argon2id = Argon2id(
    memory: params.memory,
    iterations: params.iterations,
    parallelism: params.parallelism,
    hashLength: BackupCodec.keyLength,
  );
  final key = await argon2id.deriveKeyFromPassword(
    password: passphrase,
    nonce: salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}

/// Deterministic, non-random bytes for salt/nonce so envelopes are reproducible
/// in assertions. Each call returns a fixed, position-varying pattern — never
/// used in production, only to make tests stable.
List<int> fixedBytes(int length) =>
    List<int>.generate(length, (i) => (i * 7 + 3) & 0xff);

/// A codec wired for fast, deterministic tests: real (tiny-param) Argon2id,
/// inline KDF, fixed salt/nonce.
BackupCodec testCodec() => BackupCodec(
  params: testParams,
  keyDeriver: inlineKeyDeriver,
  randomBytes: fixedBytes,
);
