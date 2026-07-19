# ADR-0001: Encrypted config backup format

- **Status:** Accepted
- **Date:** 2026-07-18
- **Context issue:** [#109](https://github.com/MikeSiekkinen/RestThermostat/issues/109)
- **Supersedes / superseded by:** —

> This is the repo's first ADR. The backup file is a **forward-compatibility contract** — files written by this build must remain restorable by future builds — so the format decisions are recorded here rather than left implicit in code.

## Context

Reinstalls, new devices, and Android signing-key changes wipe the app's local config; at minimum the server URL is lost. The obvious "let Android Auto Backup handle it" path is a known footgun: `flutter_secure_storage`'s encrypted blob is backed up but the Android Keystore key that decrypts it is not, so a restore yields undecryptable data. We need a user-controlled backup that survives a *new* Keystore.

Requirements:

- Round-trips **all user-owned config**, including secrets, across devices.
- Secrets must never appear in plaintext in a shareable file (the app's whole posture is secure-storage-backed credentials).
- A backup made today must still restore after we harden crypto parameters or add config keys.
- No native build weight on the signed-APK CI (DESIGN §13.4 bakes the resolved dependency set into the build number).

## Decision

### Passphrase-encrypted envelope

The backup is a single JSON file encrypting the config under a **user passphrase** set at export and required at import. Chosen over "exclude secrets" (forces re-entering credentials — defeats the point) and "plaintext" (a token in a shareable file contradicts the secure-storage posture).

```json
{ "app": "rest-thermostat", "schema": 1,
  "kdf": "argon2id", "salt": "<b64>", "params": { "m": 19456, "t": 2, "p": 1 },
  "cipher": "xchacha20poly1305", "nonce": "<b64>", "ciphertext": "<b64>" }
```

- **Plaintext header** (`app`, `schema`) lets import reject a foreign or too-new file **before** prompting for a passphrase.
- **AEAD associated-data** binds `app` + `schema` (`utf8("rest-thermostat|1")`), so tampering with the header or feeding a foreign file fails the authentication tag — fails closed.
- `ciphertext` is `base64(cipherText ‖ poly1305_tag)`; the tag is a fixed 16 bytes, split off the tail on decrypt.
- KDF parameters are stored **in the envelope**, so raising them later doesn't break old files — the reader always uses the file's own values.

### Crypto library: `cryptography` (pure Dart)

`Argon2id` (KDF) + `Xchacha20.poly1305Aead()` (AEAD), both from the single `cryptography` package (Apache-2.0). It's the only candidate meeting every requirement — Argon2id + XChaCha20-Poly1305 + web + **zero native build complexity** — from one dependency. The tradeoff accepted: pure-Dart Argon2id is ~1 s on a mid-tier phone; we run it inside a `compute` isolate behind a spinner so the UI stays responsive.

Rejected: `cryptography_flutter` (doesn't accelerate the KDF, no web), `pointycastle` (no XChaCha20-Poly1305), `sodium` (native FFI + a manual web step — build weight we don't need at this scale). `sodium` remains the documented fallback **iff** a real on-device Argon2id benchmark shows the pure-Dart latency is unacceptable.

### Argon2id parameters

OWASP Password Storage Cheat Sheet baseline: **m = 19 MiB (19456 KiB), t = 2, p = 1**, 32-byte key, 16-byte salt. Tuned toward a ~1 s one-shot unlock. Because params live in the envelope, these are a floor we can raise without a schema bump.

### Schema / forward-compatibility policy

- `schema` starts at **1**. Import **rejects** `schema` greater than the build supports (`BackupTooNewSchema`) rather than silently dropping fields it can't interpret.
- Within a supported schema, the payload decoder **ignores unknown keys and tolerates missing ones** — a file written by a future build with extra keys still restores everything the current build understands, and a shorter file still restores.
- A new config key that older builds can safely ignore does **not** need a schema bump. Bump `schema` only for a change that would make an old build mis-restore.

## Scope

Backed up: `server_url`; auth type + credentials (Basic user/pass, Bearer token, Cloudflare `client_id`/`client_secret`); `device_name_overrides`; `active_device_serial`; appearance (`numeralFont`, `timeFieldPalette`). Restore also sets `onboarding_complete` so the user lands connected.

**Not** backed up: `last_state_cache` (device *state*, not config, and server-owned). **Temperature scale was dropped** from the Issue #109 scope line: it is not user-owned config but a per-device API property (`Device.temperature_scale`), display-only, server-driven (DESIGN §8.1) — there is nothing on disk to export.

## Consequences

- **Positive:** survives Keystore loss; no plaintext secret ever leaves the app; no native toolchain in CI; old backups keep working as params/keys evolve.
- **Negative:** ~1 s Argon2id unlock on device (mitigated by isolate + spinner); adds two compiled deps (`cryptography`, `file_picker`) → a `pubspec.lock` change and a build-number bump (DESIGN §13.4). `file_picker` (chosen for its real filesystem save-document dialog, vs a share sheet that can't save to a chosen folder) needs a `dependency_overrides: win32: ^6.0.1` to co-resolve with `share_plus` — harmless, as win32 is Windows-only and this app targets Android/iOS.
- **Open / follow-up:** confirm on-device Argon2id latency at the chosen params on the min-spec target; if unacceptable, revisit `sodium` (this ADR would be superseded).

## Testing

Round-trip encrypt→decrypt; wrong-passphrase rejection; foreign-file, too-new-schema, and malformed rejection; tampered-ciphertext fails closed; **assert no plaintext secret appears in the envelope**; every config key restores. See `test/services/backup/`.
