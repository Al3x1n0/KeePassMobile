import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/database_settings/biometric_unlock_view_model.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/features/unlock/unlock_view_model.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/security/biometric_key_store.dart';
import 'package:keepass_mobile/shared/security/device_security.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_app_security.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const texts = BiometricPromptTexts(title: 't', subtitle: 's', cancel: 'c');
  late File file;
  late FileRef ref;
  late FakeAppSecurity security;
  late SharedPreferences prefs;

  setUp(() async {
    (file, _) = await saveToTempFile(newTestDatabase());
    ref = fileRefOf(file);
    security = FakeAppSecurity(biometrics: true);
    FakeSecureStorage.install();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer container() {
    final c = ProviderContainer.test(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appSecurityProvider.overrideWithValue(security),
      ],
    );
    c
      ..listen(unlockViewModelProvider, (_, _) {})
      ..listen(biometricUnlockViewModelProvider, (_, _) {});
    return c;
  }

  Future<void> unlock(ProviderContainer c) async {
    await c
        .read(unlockViewModelProvider.notifier)
        .unlock(
          args: UnlockArgs(database: PickedFile(ref: ref)),
          password: testMasterKey,
          biometricTexts: texts,
        );
    expect(c.read(databaseSessionProvider), isNotNull);
  }

  test(
    'sblocco con password e biometria registrata: proposta per il file',
    () async {
      final c = container();

      await unlock(c);

      expect(c.read(biometricOfferProvider), ref);
    },
  );

  test('nessuna biometria sul dispositivo: nessuna proposta', () async {
    security.biometrics = false;
    final c = container();

    await unlock(c);

    expect(c.read(biometricOfferProvider), isNull);
  });

  test('"Non chiedere più": nessuna proposta per quel file', () async {
    final c = container();
    await BiometricKeyStore(prefs).declineOffer(ref);

    await unlock(c);

    expect(c.read(biometricOfferProvider), isNull);
  });

  test('biometria già attiva: nessuna proposta', () async {
    final c = container();
    await unlock(c);
    await c.read(biometricUnlockViewModelProvider.notifier).enable(texts);
    c.read(databaseSessionProvider.notifier).lock();

    await unlock(c);

    expect(c.read(biometricOfferProvider), isNull);
  });

  test('"Ricorda file recenti" spento: nessuna proposta', () async {
    await AppSettingsRepository(prefs)
        .save(const AppSettings(rememberRecentFiles: false));
    final c = container();

    await unlock(c);

    expect(c.read(biometricOfferProvider), isNull);
  });

  test(
    'disattivata dalle impostazioni del database: non si ripropone',
    () async {
      final c = container();
      await unlock(c);
      final viewModel = c.read(biometricUnlockViewModelProvider.notifier);
      await viewModel.enable(texts);
      await viewModel.disable();
      c.read(databaseSessionProvider.notifier).lock();

      await unlock(c);

      expect(c.read(biometricOfferProvider), isNull);
    },
  );

  test('file tolto dai recenti: il rifiuto si azzera', () async {
    final c = container();
    await BiometricKeyStore(prefs).declineOffer(ref);

    await c
        .read(recentFilesProvider.notifier)
        .forget(RecentFile(database: ref));

    expect(BiometricKeyStore(prefs).isOfferDeclined(ref), isFalse);
  });

  test('blocco: la proposta decade', () async {
    final c = container();
    await unlock(c);

    c.read(databaseSessionProvider.notifier).lock();

    expect(c.read(biometricOfferProvider), isNull);
  });
}
