import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/models/auth_config.dart';
import 'package:rest_thermostat/services/backup/backup_service.dart';
import 'package:rest_thermostat/services/backup/config_snapshot.dart';
import 'package:rest_thermostat/settings/numeral_font.dart';
import 'package:rest_thermostat/settings/time_field_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../onboarding/fake_onboarding_store.dart';
import 'backup_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BackupService serviceFor(FakeOnboardingStore store) => BackupService(
    store: store,
    codec: testCodec(),
    prefsLoader: SharedPreferences.getInstance,
  );

  group('BackupService export → decrypt', () {
    test(
      'gathers every config key, including secrets and appearance',
      () async {
        SharedPreferences.setMockInitialValues({
          NumeralFontNotifier.prefsKey: 'anton',
          TimeFieldPaletteNotifier.prefsKey: 'neutral',
        });
        final store = FakeOnboardingStore()
          ..serverUrl = 'https://nest.example.com'
          ..auth = const AuthCfServiceToken(
            clientId: 'cf-id',
            clientSecret: 'cf-secret-value',
          )
          ..activeSerial = 'SERIAL-1'
          ..nameOverrides['SERIAL-1'] = 'Hallway';
        final service = serviceFor(store);

        final envelope = await service.exportEncrypted('pw-strong');
        final snap = await service.decrypt(envelope, 'pw-strong');

        expect(snap.serverUrl, 'https://nest.example.com');
        expect(snap.activeSerial, 'SERIAL-1');
        expect(snap.deviceNameOverrides, {'SERIAL-1': 'Hallway'});
        expect(snap.numeralFont, 'anton');
        expect(snap.timeFieldPalette, 'neutral');
        final auth = snap.auth as AuthCfServiceToken;
        expect(auth.clientId, 'cf-id');
        expect(auth.clientSecret, 'cf-secret-value');
      },
    );

    test('the encrypted envelope contains no plaintext secret', () async {
      SharedPreferences.setMockInitialValues({});
      final store = FakeOnboardingStore()
        ..auth = const AuthBearer(token: 'PLAINTEXT-BEARER-7ac9');
      final envelope = await serviceFor(store).exportEncrypted('pw-strong');
      expect(envelope.contains('PLAINTEXT-BEARER-7ac9'), isFalse);
    });
  });

  group('BackupService apply', () {
    test('writes a decrypted snapshot back into store + prefs', () async {
      // Source device: fully configured.
      SharedPreferences.setMockInitialValues({
        NumeralFontNotifier.prefsKey: 'jetBrainsMono',
        TimeFieldPaletteNotifier.prefsKey: 'neutral',
      });
      final source = FakeOnboardingStore()
        ..serverUrl = 'https://nest.example.com'
        ..auth = const AuthBasic(username: 'u', password: 'p')
        ..activeSerial = 'SERIAL-9'
        ..nameOverrides['SERIAL-9'] = 'Bedroom';
      final envelope = await serviceFor(source).exportEncrypted('pw-strong');
      final snap = await serviceFor(source).decrypt(envelope, 'pw-strong');

      // Target device: blank slate.
      SharedPreferences.setMockInitialValues({});
      final target = FakeOnboardingStore();
      await serviceFor(target).apply(snap);

      expect(target.serverUrl, 'https://nest.example.com');
      expect(target.activeSerial, 'SERIAL-9');
      expect(target.nameOverrides, {'SERIAL-9': 'Bedroom'});
      expect(target.complete, isTrue, reason: 'restore lands connected');
      expect(target.auth, isA<AuthBasic>());
      final auth = target.auth as AuthBasic;
      expect(auth.username, 'u');
      expect(auth.password, 'p');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(NumeralFontNotifier.prefsKey), 'jetBrainsMono');
      expect(prefs.getString(TimeFieldPaletteNotifier.prefsKey), 'neutral');
    });

    test('mirrors device-name overrides — stale ones do not survive', () async {
      // Backup carries only S1; target device already has a different override
      // (S2) that must be dropped so restore reproduces the backup exactly.
      SharedPreferences.setMockInitialValues({});
      final source = FakeOnboardingStore()
        ..serverUrl = 'https://a.example'
        ..nameOverrides['S1'] = 'Hallway';
      final envelope = await serviceFor(source).exportEncrypted('pw');

      final target = FakeOnboardingStore()
        ..serverUrl = 'https://old.example'
        ..nameOverrides['S2'] = 'Bedroom';
      final targetService = serviceFor(target);
      await targetService.apply(await targetService.decrypt(envelope, 'pw'));

      expect(target.nameOverrides, {'S1': 'Hallway'});
      expect(
        target.nameOverrides.containsKey('S2'),
        isFalse,
        reason: 'stale override must be removed on restore',
      );
    });

    test(
      'a serverUrl-less snapshot does not mark onboarding complete',
      () async {
        // Guards against soft-sticking Bootstrap (isComplete but no server).
        SharedPreferences.setMockInitialValues({});
        final target =
            FakeOnboardingStore(); // fresh: serverUrl null, incomplete
        final service = serviceFor(target);
        const noServer = ConfigSnapshot(
          serverUrl: null,
          auth: AuthNone(),
          activeSerial: null,
          deviceNameOverrides: {},
          numeralFont: null,
          timeFieldPalette: null,
        );

        await service.apply(noServer);

        expect(target.complete, isFalse);
      },
    );

    test('full restore round-trip preserves every value', () async {
      SharedPreferences.setMockInitialValues({
        NumeralFontNotifier.prefsKey: 'anton',
        TimeFieldPaletteNotifier.prefsKey: 'matchMode',
      });
      final source = FakeOnboardingStore()
        ..serverUrl = 'https://a.example'
        ..auth = const AuthBearer(token: 'restore-me')
        ..activeSerial = 'S1'
        ..nameOverrides['S1'] = 'Den'
        ..nameOverrides['S2'] = 'Attic';
      final envelope = await serviceFor(source).exportEncrypted('secret');

      SharedPreferences.setMockInitialValues({});
      final target = FakeOnboardingStore();
      final targetService = serviceFor(target);
      await targetService.apply(
        await targetService.decrypt(envelope, 'secret'),
      );

      final restored = await target.read();
      expect(restored.serverUrl, 'https://a.example');
      expect((restored.auth as AuthBearer).token, 'restore-me');
      expect(restored.activeSerial, 'S1');
      expect(restored.deviceNameOverrides, {'S1': 'Den', 'S2': 'Attic'});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(NumeralFontNotifier.prefsKey), 'anton');
      expect(prefs.getString(TimeFieldPaletteNotifier.prefsKey), 'matchMode');
    });
  });
}
