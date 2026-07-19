/// Failure modes for importing an encrypted config backup (Issue #109,
/// ADR-0001). Each case maps to a localized message in the UI; the codec throws
/// these instead of leaking raw crypto/format exceptions so the import flow can
/// react precisely (retry the passphrase vs. reject the file outright).
sealed class BackupError implements Exception {
  const BackupError();
}

/// The file isn't one of our backups — its plaintext `app` header is missing or
/// names a different app. Detected before any passphrase prompt.
class BackupForeignFile extends BackupError {
  const BackupForeignFile();
}

/// The file's `schema` is newer than this build understands. We refuse rather
/// than silently dropping fields we can't interpret. Detected before any
/// passphrase prompt.
class BackupTooNewSchema extends BackupError {
  final int fileSchema;
  final int supportedSchema;
  const BackupTooNewSchema({
    required this.fileSchema,
    required this.supportedSchema,
  });
}

/// The envelope is structurally invalid — not JSON, missing required fields, or
/// non-decodable base64. Distinct from a wrong passphrase (which fails the AEAD
/// tag on otherwise well-formed input).
class BackupMalformed extends BackupError {
  final String detail;
  const BackupMalformed(this.detail);
}

/// The passphrase was wrong (or the ciphertext/associated-data was tampered
/// with) — the AEAD authentication tag did not verify. Indistinguishable by
/// design: an attacker learns nothing about which it was.
class BackupWrongPassphrase extends BackupError {
  const BackupWrongPassphrase();
}
