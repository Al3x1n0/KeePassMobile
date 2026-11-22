import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<AppSettingsRepository> repository([
    Map<String, Object> values = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(values);
    return AppSettingsRepository(await SharedPreferences.getInstance());
  }

  test(
    'predefiniti: appunti 30 s, blocco dopo 5 min, schermo protetto',
    () async {
      final settings = (await repository()).load();

      expect(settings, const AppSettings());
      expect(settings.clipboardTimeout, const Duration(seconds: 30));
      expect(settings.lockTimeout, const Duration(minutes: 5));
      expect(settings.lockOnScreenOff, isFalse);
      expect(settings.secureScreen, isTrue);
      expect(settings.openNotification, isTrue);
      expect(settings.maskPassword, isTrue);
      expect(settings.maskTotp, isTrue);
      expect(settings.expireTanOnOpen, isTrue);
      expect(settings.showUserNameInList, isTrue);
      expect(settings.showGroupNameInSearch, isTrue);
      expect(settings.showGroupInEntry, isFalse);
      expect(settings.showRecentPasswords, isTrue);
      expect(settings.recentPasswordLimit, 5);
      expect(settings.listTextSize, 20);
      expect(settings.rememberRecentFiles, isTrue);
      expect(settings.rememberKeyFile, isTrue);
      expect(settings.themeMode, ThemeMode.system);
    },
  );

  test(
    'pulizia degli appunti: 10, 15, 30, 60, 120, 180, 240 s, senza "mai"',
    () {
      expect(AppSettings.clipboardTimeouts.map((d) => d.inSeconds), [
        10,
        15,
        30,
        60,
        120,
        180,
        240,
      ]);
    },
  );

  test(
    'salva e rilegge tutte le impostazioni, anche il blocco "mai"',
    () async {
      final repo = await repository();
      const changed = AppSettings(
        clipboardTimeout: Duration(seconds: 240),
        lockTimeout: null,
        lockOnScreenOff: true,
        secureScreen: false,
        openNotification: false,
        maskPassword: false,
        maskTotp: false,
        expireTanOnOpen: false,
        showUserNameInList: false,
        showGroupNameInSearch: false,
        showGroupInEntry: true,
        showRecentPasswords: false,
        recentPasswordLimit: 15,
        listTextSize: 28,
        rememberRecentFiles: false,
        rememberKeyFile: false,
        themeMode: ThemeMode.dark,
      );

      await repo.save(changed);

      expect(repo.load(), changed);
    },
  );

  test('valori non ammessi: si usano i predefiniti', () async {
    // given: 5 minuti e "mai" (valori di Keepass2Android) per gli appunti,
    // tempo di blocco e tema sconosciuti
    for (final clipboardMs in [300000, -1]) {
      final repo = await repository({
        'settings.clipboard_timeout_ms': clipboardMs,
        'settings.lock_timeout_ms': 42,
        'settings.theme_mode': 'viola',
        'settings.list_text_size': 99,
      });

      // when
      final settings = repo.load();

      // then
      expect(settings.clipboardTimeout, const Duration(seconds: 30));
      expect(settings.lockTimeout, const Duration(minutes: 5));
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.listTextSize, 20);
    }
  });

  test('copyWith: blocco "mai" con null, gli altri valori invariati', () {
    const settings = AppSettings(lockOnScreenOff: true);

    final never = settings.copyWith(lockTimeout: null);

    expect(never.lockTimeout, isNull);
    expect(never.lockOnScreenOff, isTrue);
    expect(never.copyWith(maskTotp: false).lockTimeout, isNull);
  });

  test(
    'password recenti: salva 5, 10 e 15 e normalizza gli altri limiti',
    () async {
      const key = 'settings.recent_password_limit';
      final repo = await repository({key: '10'});
      expect(repo.load().recentPasswordLimit, 5);

      for (final limit in [5, 10, 15]) {
        final settings = repo.load().copyWith(
          showRecentPasswords: true,
          recentPasswordLimit: limit,
        );
        await repo.save(settings);
        expect(repo.load().showRecentPasswords, isTrue);
        expect(repo.load().recentPasswordLimit, limit);
      }

      await repo.save(repo.load().copyWith(recentPasswordLimit: 42));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(key), 5);
    },
  );

  test('permesso per le notifiche: chiesto una volta sola', () async {
    final repo = await repository();
    expect(repo.notificationPermissionRequested, isFalse);

    await repo.markNotificationPermissionRequested();
    // Non è un'impostazione: il salvataggio non lo cancella.
    await repo.save(repo.load());

    expect(repo.notificationPermissionRequested, isTrue);
  });

  test(
    'impostazioni di QuickUnlock (tolto in D22) cancellate al salvataggio',
    () async {
      final repo = await repository({
        'settings.quick_unlock': true,
        'settings.quick_unlock_length': 3,
        'settings.quick_unlock_hide_length': false,
      });
      final prefs = await SharedPreferences.getInstance();

      await repo.save(repo.load());

      expect(prefs.getKeys().where((k) => k.contains('quick_unlock')), isEmpty);
    },
  );
}
