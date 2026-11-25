import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/database_settings/biometric_unlock_view_model.dart';
import 'package:keepass_mobile/features/database_settings/change_master_key_view_model.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/features/settings/settings_view_model.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/security/biometric_key_store.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const texts = BiometricPromptTexts(title: 't', subtitle: 's', cancel: 'c');
  late FakeSecureStorage secure;

  setUp(() => secure = FakeSecureStorage.install());

  Future<ProviderContainer> open() async {
    final (file, reopened) = await saveToTempFile(newTestDatabase());
    final container = await newTestContainer(file: file, database: reopened);
    addTearDown(container.dispose);
    container.listen(biometricUnlockViewModelProvider, (_, _) {});
    return container;
  }

  Future<void> enable(ProviderContainer container) =>
      container.read(biometricUnlockViewModelProvider.notifier).enable(texts);

  bool enabledFor(ProviderContainer container) => container
      .read(biometricKeyStoreProvider)
      .isEnabled(container.read(databaseSessionProvider)!.file);

  test(
    'attivazione: salva la chiave derivata, la sessione usa solo quella',
    () async {
      final container = await open();
      expect(
        await container.read(biometricUnlockViewModelProvider.future),
        isFalse,
      );

      await enable(container);

      expect(container.read(biometricUnlockViewModelProvider).value, isTrue);
      final session = container.read(databaseSessionProvider)!;
      expect(session.hasRawKey, isFalse);
      final stored = await container
          .read(biometricKeyStoreProvider)
          .read(session.file, texts: texts);
      expect(
        stored?.key.bytes,
        session.database.header.transformedKey?.key.bytes,
      );
    },
  );

  test('annullata: resta disattivata, senza errore', () async {
    final container = await open();
    secure.failure = FakeSecureStorage.canceled();

    await enable(container);

    final state = container.read(biometricUnlockViewModelProvider);
    expect(state.hasError, isFalse);
    expect(state.value, isFalse);
    expect(enabledFor(container), isFalse);
    expect(container.read(databaseSessionProvider)?.hasRawKey, isTrue);
  });

  test('biometria non disponibile: errore dedicato', () async {
    final container = await open();
    secure.failure = PlatformException(
      code: 'Exception encountered',
      message: 'BIOMETRIC_UNAVAILABLE: Device has no PIN',
    );

    await enable(container);

    expect(
      container.read(biometricUnlockViewModelProvider).error,
      isA<BiometricKeyException>().having(
        (e) => e.reason,
        'reason',
        BiometricKeyError.unavailable,
      ),
    );
  });

  test('disattivazione: chiave rimossa', () async {
    final container = await open();
    await enable(container);

    await container.read(biometricUnlockViewModelProvider.notifier).disable();

    expect(container.read(biometricUnlockViewModelProvider).value, isFalse);
    expect(secure.data, isEmpty);
  });

  test('cambio della chiave principale: biometria disattivata', () async {
    final container = await open();
    container.listen(changeMasterKeyViewModelProvider, (_, _) {});
    await enable(container);

    final viewModel = container.read(changeMasterKeyViewModelProvider.notifier);
    expect(
      await viewModel.change(currentPassword: testMasterKey, password: 'nuova'),
      isTrue,
    );

    expect(viewModel.biometricDisabled, isTrue);
    expect(enabledFor(container), isFalse);
    expect(container.read(databaseSessionProvider)?.hasRawKey, isTrue);
  });

  test('file tolto dai recenti: biometria disattivata', () async {
    final container = await open();
    await enable(container);
    final file = container.read(databaseSessionProvider)!.file;

    await container
        .read(recentFilesProvider.notifier)
        .forget(RecentFile(database: file));

    expect(enabledFor(container), isFalse);
  });

  test('"Ricorda file recenti" disattivato: biometria disattivata', () async {
    final container = await open();
    await enable(container);
    container.listen(settingsViewModelProvider, (_, _) {});

    await container
        .read(settingsViewModelProvider.notifier)
        .update(const AppSettings(rememberRecentFiles: false));

    expect(enabledFor(container), isFalse);
  });
}
