import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/features/unlock/unlock_view_model.dart';
import 'package:keepass_mobile/shared/database/database_errors.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/security/biometric_key_store.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_secure_storage.dart';

/// Legge i fixture e simula un riferimento aggiornato dal sistema (bookmark
/// iOS obsoleto).
class _RefreshingStorage extends FileStorage {
  _RefreshingStorage(this.refreshed);

  final FileRef refreshed;

  @override
  Future<StoredFile> read(FileRef ref) async {
    final stored = await super.read(ref);
    return StoredFile(ref: refreshed, bytes: stored.bytes);
  }
}

void main() {
  // Il file chiave content:// passa dal canale del plugin, che richiede il
  // binding (senza plugin nativo risponde MissingPluginException).
  TestWidgetsFlutterBinding.ensureInitialized();
  const dir = 'test/fixtures/kdbx/';
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer newContainer({FileStorage? storage}) {
    final container = ProviderContainer.test(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (storage != null) fileStorageProvider.overrideWithValue(storage),
      ],
    );
    // Mantiene vivo il provider autoDispose come farebbe la schermata.
    container.listen(unlockViewModelProvider, (_, _) {});
    return container;
  }

  FileRef refOf(String name) => FileRef(
    uri: Uri.file(File('$dir$name').absolute.path).toString(),
    name: name,
  );

  PickedFile picked(String name) =>
      PickedFile(ref: refOf(name), bytes: File('$dir$name').readAsBytesSync());

  test(
    'sblocco riuscito: apre la sessione e ricorda file e file chiave',
    () async {
      final container = newContainer();

      await container
          .read(unlockViewModelProvider.notifier)
          .unlock(
            args: UnlockArgs(
              database: picked('test4.kdbx'),
              keyFile: picked('test4.key'),
            ),
            password: 'password',
          );

      expect(container.read(unlockViewModelProvider), isA<AsyncData<void>>());
      final session = container.read(databaseSessionProvider);
      expect(session?.database.root.allEntries, hasLength(15));
      final recent = container
          .read(recentFilesRepositoryProvider)
          .load()
          .single;
      expect(recent.database, refOf('test4.kdbx'));
      expect(recent.keyFile, refOf('test4.key'));
    },
  );

  test('password errata: errore tipizzato, nessuna sessione, nessun file ricordato', () async {
    final container = newContainer();

    await container
        .read(unlockViewModelProvider.notifier)
        .unlock(
          args: UnlockArgs(database: picked('test4_aes_uncompressed.kdbx')),
          password: 'sbagliata',
        );

    expect(
      container.read(unlockViewModelProvider).error,
      isA<InvalidCredentialsError>(),
    );
    expect(container.read(databaseSessionProvider), isNull);
    expect(container.read(recentFilesRepositoryProvider).load(), isEmpty);
  });

  test('"Ricorda file recenti" disattivato: sessione aperta, nessun file ricordato', () async {
    await AppSettingsRepository(prefs)
        .save(const AppSettings(rememberRecentFiles: false));
    final container = newContainer();

    await container
        .read(unlockViewModelProvider.notifier)
        .unlock(
          args: UnlockArgs(
            database: picked('test4.kdbx'),
            keyFile: picked('test4.key'),
          ),
          password: 'password',
        );

    expect(container.read(databaseSessionProvider), isNotNull);
    expect(container.read(recentFilesRepositoryProvider).load(), isEmpty);
  });

  test(
    '"Ricorda file chiave" disattivato: database ricordato senza file chiave',
    () async {
      await AppSettingsRepository(prefs)
          .save(const AppSettings(rememberKeyFile: false));
      final container = newContainer();

      await container
          .read(unlockViewModelProvider.notifier)
          .unlock(
            args: UnlockArgs(
              database: picked('test4.kdbx'),
              keyFile: picked('test4.key'),
            ),
            password: 'password',
          );

      final recent = container
          .read(recentFilesRepositoryProvider)
          .load()
          .single;
      expect(recent.database, refOf('test4.kdbx'));
      expect(recent.keyFile, isNull);
    },
  );

  test('file chiave non più leggibile: KeyFileUnavailableException', () async {
    final container = newContainer();

    await container
        .read(unlockViewModelProvider.notifier)
        .unlock(
          args: UnlockArgs(
            database: picked('test4.kdbx'),
            keyFile: const PickedFile(
              ref: FileRef(uri: 'content://provider/a.key', name: 'a.key'),
            ),
          ),
          password: 'password',
        );

    expect(
      container.read(unlockViewModelProvider).error,
      isA<KeyFileUnavailableException>(),
    );
    expect(container.read(databaseSessionProvider), isNull);
  });

  test('database dai file recenti: letto dal percorso del file', () async {
    final container = newContainer();

    await container
        .read(unlockViewModelProvider.notifier)
        .unlock(
          args: UnlockArgs(
            database: PickedFile(ref: refOf('test4_aes_uncompressed.kdbx')),
          ),
          password: 'password',
        );

    expect(container.read(databaseSessionProvider), isNotNull);
  });

  test('riferimento aggiornato dal sistema: sessione e file recenti usano il nuovo', () async {
    // given: il database è nei recenti con un riferimento ormai obsoleto
    const refreshed = FileRef(uri: 'bookmark:nuovo', name: 'db.kdbx');
    final old = refOf('test4_aes_uncompressed.kdbx');
    final container = newContainer(storage: _RefreshingStorage(refreshed));
    await container
        .read(recentFilesRepositoryProvider)
        .remember(RecentFile(database: old));

    // when
    await container
        .read(unlockViewModelProvider.notifier)
        .unlock(
          args: UnlockArgs(database: PickedFile(ref: old)),
          password: 'password',
        );

    // then
    expect(container.read(databaseSessionProvider)?.file, refreshed);
    final recents = container.read(recentFilesRepositoryProvider).load();
    expect(recents.map((f) => f.database), [refreshed]);
  });

  test(
    'file scelto di nuovo: sostituisce il recente soltanto dopo lo sblocco',
    () async {
      final container = newContainer();
      const old = FileRef(uri: 'content://test/perso', name: 'prima.kdbx');
      final replacement = picked('test4_aes_uncompressed.kdbx');
      await container
          .read(recentFilesRepositoryProvider)
          .remember(const RecentFile(database: old));
      final args = UnlockArgs(database: replacement, replacing: old);
      await container
          .read(unlockViewModelProvider.notifier)
          .unlock(args: args, password: 'errata');
      expect(container.read(databaseSessionProvider), isNull);
      expect(
        container.read(recentFilesRepositoryProvider).load().single.database,
        old,
      );
      await container
          .read(unlockViewModelProvider.notifier)
          .unlock(args: args, password: 'password');
      expect(container.read(databaseSessionProvider)?.file, replacement.ref);
      expect(
        container.read(recentFilesRepositoryProvider).load().single.database,
        replacement.ref,
      );
    },
  );

  test('blocco: la sessione viene chiusa', () async {
    final container = newContainer();
    await container
        .read(unlockViewModelProvider.notifier)
        .unlock(
          args: UnlockArgs(database: picked('test4_aes_uncompressed.kdbx')),
          password: 'password',
        );

    container.read(databaseSessionProvider.notifier).lock();

    expect(container.read(databaseSessionProvider), isNull);
  });

  group('sblocco biometrico', () {
    const texts = BiometricPromptTexts(title: 't', subtitle: 's', cancel: 'c');
    const name = 'test4_aes_uncompressed.kdbx';
    late FakeSecureStorage secure;

    setUp(() => secure = FakeSecureStorage.install());

    /// Sblocca con password, attiva la biometria con [fingerprint] (quella vera
    /// se omessa) e blocca.
    Future<(ProviderContainer, KdbxTransformedKey)> enabled({
      List<int>? fingerprint,
    }) async {
      final container = newContainer();
      await container
          .read(unlockViewModelProvider.notifier)
          .unlock(
            args: UnlockArgs(database: picked(name)),
            password: 'password',
          );
      final key = container
          .read(databaseSessionProvider)!
          .database
          .header
          .transformedKey!;
      await container
          .read(biometricKeyStoreProvider)
          .store(
            refOf(name),
            KdbxTransformedKey(
              key: key.key,
              fingerprint: fingerprint ?? key.fingerprint,
            ),
            texts: texts,
          );
      container.read(databaseSessionProvider.notifier).lock();
      return (container, key);
    }

    Future<void> unlockWithBiometrics(ProviderContainer container) => container
        .read(unlockViewModelProvider.notifier)
        .unlockWithBiometrics(
          args: UnlockArgs(database: picked(name)),
          texts: texts,
        );

    test('apre il database con la chiave salvata, senza password', () async {
      final (container, _) = await enabled();

      await unlockWithBiometrics(container);

      expect(container.read(unlockViewModelProvider), isA<AsyncData<void>>());
      final session = container.read(databaseSessionProvider);
      expect(session?.database.root.allEntries, isNotEmpty);
      expect(session?.hasRawKey, isFalse);
    });

    test('annullato dall\'utente: nessun errore, nessuna sessione', () async {
      final (container, _) = await enabled();
      secure.failure = FakeSecureStorage.canceled();

      await unlockWithBiometrics(container);

      expect(container.read(unlockViewModelProvider), isA<AsyncData<void>>());
      expect(container.read(databaseSessionProvider), isNull);
      expect(
        container.read(biometricKeyStoreProvider).isEnabled(refOf(name)),
        isTrue,
      );
    });

    test(
      'chiave sparita (biometria cambiata): errore e biometria disattivata',
      () async {
        final (container, _) = await enabled();
        secure.data.clear();

        await unlockWithBiometrics(container);

        expect(
          container.read(unlockViewModelProvider).error,
          isA<BiometricKeyException>().having(
            (e) => e.reason,
            'reason',
            BiometricKeyError.invalidated,
          ),
        );
        expect(container.read(databaseSessionProvider), isNull);
        expect(
          container.read(biometricKeyStoreProvider).isEnabled(refOf(name)),
          isFalse,
        );
      },
    );

    test(
      'file cambiato altrove: errore, poi la password aggiorna la chiave',
      () async {
        // given: la chiave salvata è di parametri KDF ormai vecchi
        final (container, key) = await enabled(fingerprint: [0]);

        // when: sblocco biometrico
        await unlockWithBiometrics(container);

        // then: errore dedicato, biometria ancora attiva
        expect(
          container.read(unlockViewModelProvider).error,
          isA<BiometricKeyException>().having(
            (e) => e.reason,
            'reason',
            BiometricKeyError.stale,
          ),
        );
        final store = container.read(biometricKeyStoreProvider);
        expect(store.isEnabled(refOf(name)), isTrue);

        // when: sblocco con password
        await container
            .read(unlockViewModelProvider.notifier)
            .unlock(
              args: UnlockArgs(database: picked(name)),
              password: 'password',
              biometricTexts: texts,
            );

        // then: chiave aggiornata, sessione con la sola chiave derivata
        expect(store.fingerprintOf(refOf(name)), key.fingerprint);
        expect(container.read(databaseSessionProvider)?.hasRawKey, isFalse);
        container.read(databaseSessionProvider.notifier).lock();
        await unlockWithBiometrics(container);
        expect(container.read(databaseSessionProvider), isNotNull);
      },
    );

    test(
      'aggiornamento rifiutato: sessione aperta, biometria disattivata',
      () async {
        final (container, _) = await enabled(fingerprint: [0]);
        secure.failure = FakeSecureStorage.canceled();

        await container
            .read(unlockViewModelProvider.notifier)
            .unlock(
              args: UnlockArgs(database: picked(name)),
              password: 'password',
              biometricTexts: texts,
            );

        expect(container.read(databaseSessionProvider), isNotNull);
        expect(
          container.read(biometricKeyStoreProvider).isEnabled(refOf(name)),
          isFalse,
        );
      },
    );

    test(
      'password con chiave già aggiornata: nessuna richiesta biometrica',
      () async {
        final (container, _) = await enabled();
        final requests = secure.options.length;

        await container
            .read(unlockViewModelProvider.notifier)
            .unlock(
              args: UnlockArgs(database: picked(name)),
              password: 'password',
              biometricTexts: texts,
            );

        expect(secure.options, hasLength(requests));
        expect(container.read(databaseSessionProvider)?.hasRawKey, isFalse);
      },
    );

    test(
      'biometria non attiva: la sessione conserva la chiave completa',
      () async {
        final container = newContainer();

        await container
            .read(unlockViewModelProvider.notifier)
            .unlock(
              args: UnlockArgs(database: picked(name)),
              password: 'password',
              biometricTexts: texts,
            );

        expect(container.read(databaseSessionProvider)?.hasRawKey, isTrue);
        expect(secure.options, isEmpty);
      },
    );
  });
}
