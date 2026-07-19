import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/numeral_font.dart';
import '../../settings/time_field_palette.dart';
import '../onboarding_store.dart';
import 'backup_codec.dart';
import 'config_snapshot.dart';

/// Gathers every user-owned config key into an encrypted backup and rewrites
/// them on restore (Issue #109, ADR-0001). Bridges [BackupCodec] (opaque crypto)
/// and the app's split persistence: [OnboardingStore] owns server/auth/serial/
/// overrides; the two appearance keys are read/written directly against
/// SharedPreferences using the notifiers' public [NumeralFontNotifier.prefsKey]
/// / [TimeFieldPaletteNotifier.prefsKey].
///
/// The prefs loader is injected the same way [FlutterOnboardingStore] injects
/// it, so this is unit-testable with a fake store + in-memory prefs and never
/// touches a platform channel in tests.
class BackupService {
  final OnboardingStore store;
  final BackupCodec _codec;
  final Future<SharedPreferences> Function() _prefs;

  BackupService({
    required this.store,
    BackupCodec? codec,
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _codec = codec ?? BackupCodec(),
       _prefs = prefsLoader ?? SharedPreferences.getInstance;

  /// Reads current config into a [ConfigSnapshot] and returns the encrypted
  /// envelope JSON string, ready to share. Runs the Argon2id KDF (off the UI
  /// thread inside the codec).
  Future<String> exportEncrypted(String passphrase) async {
    final config = await store.read();
    final prefs = await _prefs();
    final snapshot = ConfigSnapshot(
      serverUrl: config.serverUrl,
      auth: config.auth,
      activeSerial: config.activeSerial,
      deviceNameOverrides: config.deviceNameOverrides,
      numeralFont: prefs.getString(NumeralFontNotifier.prefsKey),
      timeFieldPalette: prefs.getString(TimeFieldPaletteNotifier.prefsKey),
    );
    return _codec.encrypt(snapshot.toJson(), passphrase);
  }

  /// Checks the file's plaintext header (app + schema) without a passphrase, so
  /// the import UI can reject a foreign or too-new file before prompting. Throws
  /// [BackupForeignFile] / [BackupTooNewSchema] / [BackupMalformed].
  void inspect(String envelope) => _codec.inspectHeader(envelope);

  /// Decrypts and parses a backup without writing anything, so the UI can show a
  /// confirmation summary before overwriting the device's config. Throws a
  /// [BackupError] subtype on foreign/too-new/malformed files or a wrong
  /// passphrase.
  Future<ConfigSnapshot> decrypt(String envelope, String passphrase) async {
    final payload = await _codec.decrypt(envelope, passphrase);
    return ConfigSnapshot.fromJson(payload);
  }

  /// Writes a decrypted [snapshot] into the app's live persistence. Marks
  /// onboarding complete so the user lands connected rather than back in setup.
  /// Appearance keys are written straight to prefs; callers should refresh the
  /// appearance providers (e.g. `ref.invalidate`) so live state re-hydrates.
  Future<void> apply(ConfigSnapshot snapshot) async {
    final current = await store.read();

    if (snapshot.serverUrl != null) {
      await store.saveServerUrl(snapshot.serverUrl!);
    }
    await store.saveAuth(snapshot.auth);
    if (snapshot.activeSerial != null) {
      await store.saveActiveSerial(snapshot.activeSerial!);
    }

    // Mirror device-name overrides rather than merge: drop any the current
    // config carries that the backup doesn't, so a restore reproduces the
    // backup exactly (a stale override from the pre-restore device must not
    // survive). Then write the backup's set.
    for (final serial in current.deviceNameOverrides.keys) {
      if (!snapshot.deviceNameOverrides.containsKey(serial)) {
        await store.setDeviceNameOverride(serial, null);
      }
    }
    for (final entry in snapshot.deviceNameOverrides.entries) {
      await store.setDeviceNameOverride(entry.key, entry.value);
    }

    final prefs = await _prefs();
    await _writeOrRemove(
      prefs,
      NumeralFontNotifier.prefsKey,
      snapshot.numeralFont,
    );
    await _writeOrRemove(
      prefs,
      TimeFieldPaletteNotifier.prefsKey,
      snapshot.timeFieldPalette,
    );

    // Only land the user "connected" if there's actually a server to reach —
    // from the backup or already on disk. A serverUrl-less file marking
    // onboarding complete would soft-stick Bootstrap (isComplete but no
    // server → it falls through to onboarding anyway).
    if ((snapshot.serverUrl ?? current.serverUrl) != null) {
      await store.markComplete();
    }
  }

  static Future<void> _writeOrRemove(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}
