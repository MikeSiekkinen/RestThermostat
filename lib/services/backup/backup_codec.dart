import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show compute;

import 'backup_errors.dart';

/// Argon2id cost parameters, stored in the envelope so a file made with today's
/// parameters still decrypts after we raise them (the reader always uses the
/// file's own values, never the current defaults). `memory` is in 1 KiB blocks.
class Argon2idParams {
  final int memory;
  final int iterations;
  final int parallelism;

  const Argon2idParams({
    required this.memory,
    required this.iterations,
    required this.parallelism,
  });

  /// OWASP Password Storage Cheat Sheet baseline for Argon2id: 19 MiB, t=2, p=1
  /// (Issue #109 research pass). Tuned to be a one-shot ~1 s unlock on a
  /// mid-tier phone; can be raised later without breaking old files.
  static const owaspDefault = Argon2idParams(
    memory: 19456, // 19 MiB in KiB
    iterations: 2,
    parallelism: 1,
  );

  Map<String, dynamic> toJson() => {
    'm': memory,
    't': iterations,
    'p': parallelism,
  };

  factory Argon2idParams.fromJson(Map<String, dynamic> json) {
    final m = json['m'], t = json['t'], p = json['p'];
    if (m is! int || t is! int || p is! int || m < 1 || t < 1 || p < 1) {
      throw const BackupMalformed('invalid argon2id params');
    }
    return Argon2idParams(memory: m, iterations: t, parallelism: p);
  }
}

/// Derives a raw key from a passphrase + salt. Injectable so tests can run the
/// KDF inline instead of on an isolate. Production runs it via [compute] to keep
/// the ~1 s pure-Dart Argon2id off the UI thread.
typedef KeyDeriver =
    Future<Uint8List> Function(
      Argon2idParams params,
      String passphrase,
      Uint8List salt,
    );

/// Top-level so it can cross the isolate boundary for [compute]. Runs Argon2id
/// and returns the raw key bytes (cryptography's `SecretKey` isn't sendable, so
/// we extract bytes inside the isolate and rebuild it on the other side).
Future<Uint8List> _deriveKeyIsolate(
  (Argon2idParams, String, Uint8List) req,
) async {
  final (params, passphrase, salt) = req;
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

Future<Uint8List> _defaultKeyDeriver(
  Argon2idParams params,
  String passphrase,
  Uint8List salt,
) => compute(_deriveKeyIsolate, (params, passphrase, salt));

/// Turns a plaintext config payload into a passphrase-encrypted JSON envelope
/// and back (Issue #109, ADR-0001). Knows nothing about app config — it moves
/// an opaque `Map` through Argon2id + XChaCha20-Poly1305.
///
/// Envelope shape:
/// ```json
/// { "app": "rest-thermostat", "schema": 1,
///   "kdf": "argon2id", "salt": "<b64>", "params": {"m":…,"t":…,"p":…},
///   "cipher": "xchacha20poly1305", "nonce": "<b64>", "ciphertext": "<b64>" }
/// ```
/// The AEAD associated-data binds `app`+`schema`, so a tampered header or a
/// foreign file fails the MAC. The plaintext `app`/`schema` header lets import
/// reject foreign or too-new files *before* prompting for a passphrase.
class BackupCodec {
  static const appId = 'rest-thermostat';
  static const schemaVersion = 1;
  static const kdfId = 'argon2id';
  static const cipherId = 'xchacha20poly1305';

  static const keyLength = 32; // XChaCha20 key
  static const saltLength = 16;
  static const _nonceLength = 24; // XChaCha20 nonce
  static const _macLength = 16; // Poly1305 tag

  final Argon2idParams params;
  final KeyDeriver _deriveKey;
  final List<int> Function(int length) _randomBytes;
  final Cipher _cipher = Xchacha20.poly1305Aead();

  BackupCodec({
    this.params = Argon2idParams.owaspDefault,
    KeyDeriver? keyDeriver,
    List<int> Function(int length)? randomBytes,
  }) : _deriveKey = keyDeriver ?? _defaultKeyDeriver,
       _randomBytes = randomBytes ?? _secureRandomBytes;

  /// Associated authenticated data binds the header to the ciphertext so a
  /// swapped `app`/`schema` fails decryption rather than silently mis-parsing.
  static List<int> _aad(int schema) => utf8.encode('$appId|$schema');

  Future<String> encrypt(
    Map<String, dynamic> payload,
    String passphrase,
  ) async {
    final salt = Uint8List.fromList(_randomBytes(saltLength));
    final nonce = Uint8List.fromList(_randomBytes(_nonceLength));
    final keyBytes = await _deriveKey(params, passphrase, salt);
    final secretBox = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
      aad: _aad(schemaVersion),
    );
    // Concatenate ciphertext || mac into the single `ciphertext` field; the
    // Poly1305 tag is a fixed 16 bytes, so decrypt splits it back off the tail.
    final blob = Uint8List(secretBox.cipherText.length + _macLength)
      ..setAll(0, secretBox.cipherText)
      ..setAll(secretBox.cipherText.length, secretBox.mac.bytes);
    return jsonEncode({
      'app': appId,
      'schema': schemaVersion,
      'kdf': kdfId,
      'salt': base64Encode(salt),
      'params': params.toJson(),
      'cipher': cipherId,
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(blob),
    });
  }

  /// Validates just the plaintext header — throws [BackupForeignFile],
  /// [BackupTooNewSchema], or [BackupMalformed] — so the import UI can reject a
  /// foreign or too-new file *before* asking for a passphrase. Cheap: no KDF.
  void inspectHeader(String envelopeText) {
    _parseAndValidateHeader(envelopeText);
  }

  /// Validates the header (throwing [BackupForeignFile]/[BackupTooNewSchema]
  /// before any KDF work), then derives the key and AEAD-decrypts. A wrong
  /// passphrase or tampered file surfaces as [BackupWrongPassphrase].
  Future<Map<String, dynamic>> decrypt(
    String envelopeText,
    String passphrase,
  ) async {
    final header = _parseAndValidateHeader(envelopeText);
    final fileParams = Argon2idParams.fromJson(
      _asMap(header['params'], 'params'),
    );
    final salt = _decodeB64(header['salt'], 'salt');
    final nonce = _decodeB64(header['nonce'], 'nonce');
    final blob = _decodeB64(header['ciphertext'], 'ciphertext');
    if (nonce.length != _nonceLength || blob.length < _macLength) {
      throw const BackupMalformed('bad nonce or ciphertext length');
    }
    final cipherText = blob.sublist(0, blob.length - _macLength);
    final mac = Mac(blob.sublist(blob.length - _macLength));

    final keyBytes = await _deriveKey(fileParams, passphrase, salt);
    final List<int> clear;
    try {
      clear = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: SecretKey(keyBytes),
        aad: _aad(header['schema'] as int),
      );
    } on SecretBoxAuthenticationError {
      throw const BackupWrongPassphrase();
    }
    try {
      final decoded = jsonDecode(utf8.decode(clear));
      return _asMap(decoded, 'payload');
    } catch (_) {
      // Decrypted (MAC verified) but not the JSON we expect — treat as
      // malformed rather than a passphrase problem.
      throw const BackupMalformed('decrypted payload is not a JSON object');
    }
  }

  /// Parses the outer envelope and checks the fields that gate whether we should
  /// even prompt for a passphrase. Order matters: foreign-app before schema so a
  /// random JSON file reads as "not our backup", not "too new".
  Map<String, dynamic> _parseAndValidateHeader(String envelopeText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(envelopeText);
    } catch (_) {
      throw const BackupMalformed('not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BackupMalformed('envelope is not a JSON object');
    }
    if (decoded['app'] != appId) throw const BackupForeignFile();
    final schema = decoded['schema'];
    if (schema is! int || schema < 1) {
      throw const BackupMalformed('missing or invalid schema');
    }
    if (schema > schemaVersion) {
      throw BackupTooNewSchema(
        fileSchema: schema,
        supportedSchema: schemaVersion,
      );
    }
    if (decoded['kdf'] != kdfId || decoded['cipher'] != cipherId) {
      throw const BackupMalformed('unsupported kdf or cipher');
    }
    return decoded;
  }

  static Map<String, dynamic> _asMap(Object? v, String field) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    throw BackupMalformed('$field is not an object');
  }

  static Uint8List _decodeB64(Object? v, String field) {
    if (v is! String) throw BackupMalformed('$field is not a string');
    try {
      return base64Decode(v);
    } catch (_) {
      throw BackupMalformed('$field is not valid base64');
    }
  }
}

List<int> _secureRandomBytes(int length) {
  final rng = Random.secure();
  return List<int>.generate(length, (_) => rng.nextInt(256));
}
