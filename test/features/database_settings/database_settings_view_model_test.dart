import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/database_settings/database_settings_view_model.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, Future<KdbxDatabase> Function())> open({
    (int, int) version = (4, 1),
  }) async {
    final db = newTestDatabase();
    if (version.$1 < 4) {
      db.header
        ..version = version
        ..keyEncryptionRounds = 1000;
    } else {
      db.header.kdfSettings = const AesKdfSettings(rounds: 1000);
    }
    final (file, reopened) = await saveToTempFile(db);
    final container = await newTestContainer(file: file, database: reopened);
    addTearDown(container.dispose);
    container.listen(databaseSettingsViewModelProvider, (_, _) {});
    return (container, () => reopenFile(file));
  }

  test('legge le impostazioni del database aperto', () async {
    final (container, _) = await open();

    final settings = container.read(databaseSettingsProvider);

    expect(settings?.name, 'Prova');
    expect(settings?.recycleBinEnabled, isTrue);
    expect(settings?.historyMaxItems, 10);
    expect(settings?.cipher, CipherId.aes);
    expect(settings?.kdf, const AesKdfSettings(rounds: 1000));
    expect(settings?.allowedCiphers, contains(CipherId.chaCha20));
  });

  test(
    'salva nome, nome utente predefinito, cestino e cronologia nel file',
    () async {
      final (container, onDisk) = await open();
      final settings = container.read(databaseSettingsProvider)!;

      final saved = await container
          .read(databaseSettingsViewModelProvider.notifier)
          .save(
            settings.copyWith(
              name: 'Personale',
              defaultUserName: 'alex',
              recycleBinEnabled: false,
              historyMaxItems: 5,
              historyMaxSize: DatabaseSettings.unlimited,
            ),
          );

      expect(saved, isTrue);
      final db = await onDisk();
      expect(db.meta.name, 'Personale');
      expect(db.meta.defaultUser, 'alex');
      expect(db.meta.recycleBinEnabled, isFalse);
      expect(db.meta.historyMaxItems, 5);
      expect(db.meta.historyMaxSize, -1);
      expect(container.read(databaseSettingsProvider)?.name, 'Personale');
    },
  );

  test(
    'ChaCha20 e Argon2id: il file si riapre con la stessa password',
    () async {
      final (container, onDisk) = await open();
      final settings = container.read(databaseSettingsProvider)!;
      const argon = Argon2KdfSettings(
        id: true,
        memory: 1024 * 1024,
        iterations: 1,
        parallelism: 1,
      );

      await container
          .read(databaseSettingsViewModelProvider.notifier)
          .save(settings.copyWith(cipher: CipherId.chaCha20, kdf: argon));

      final db = await onDisk();
      expect(db.header.dataCipherUuid?.string, CipherId.chaCha20);
      expect(db.header.kdfSettings, argon);
    },
  );

  test('Twofish e AES-KDF con altri round: il file si riapre', () async {
    final (container, onDisk) = await open();
    final settings = container.read(databaseSettingsProvider)!;

    await container
        .read(databaseSettingsViewModelProvider.notifier)
        .save(
          settings.copyWith(
            cipher: CipherId.twofish,
            kdf: const AesKdfSettings(rounds: 2000),
          ),
        );

    final db = await onDisk();
    expect(db.header.dataCipherUuid?.string, CipherId.twofish);
    expect(db.header.kdfSettings, const AesKdfSettings(rounds: 2000));
  });

  test('KDBX 3: niente ChaCha20 né Argon2, il formato non cambia', () async {
    final (container, onDisk) = await open(version: (3, 1));
    final settings = container.read(databaseSettingsProvider)!;
    expect(settings.allowedCiphers, isNot(contains(CipherId.chaCha20)));
    expect(settings.allowedKdfs, [KdfId.aes]);

    final refused = await container
        .read(databaseSettingsViewModelProvider.notifier)
        .save(settings.copyWith(cipher: CipherId.chaCha20));
    expect(refused, isFalse);
    expect(
      container.read(databaseSettingsViewModelProvider).error,
      isA<UnsupportedValueError>(),
    );

    await container
        .read(databaseSettingsViewModelProvider.notifier)
        .save(settings.copyWith(kdf: const AesKdfSettings(rounds: 1500)));
    final db = await onDisk();
    expect(db.header.version.$1, 3);
    expect(db.header.kdfSettings, const AesKdfSettings(rounds: 1500));
  });

  test('seleziona e rimuove il gruppo modelli nel file', () async {
    final (container, onDisk) = await open();
    final db = container.read(databaseSessionProvider)!.database;
    final group = db.createGroup(parent: db.root, name: 'Modelli');
    final settings = container.read(databaseSettingsProvider)!;
    final viewModel = container.read(
      databaseSettingsViewModelProvider.notifier,
    );

    expect(
      await viewModel.save(
        settings.copyWith(templatesGroupId: itemIdOf(group)),
      ),
      isTrue,
    );
    expect((await onDisk()).meta.entryTemplatesGroup, group.uuid);
    expect(
      await viewModel.save(settings.copyWith(templatesGroupId: '')),
      isTrue,
    );
    final cleared = (await onDisk()).meta.entryTemplatesGroup;
    expect(cleared == null || cleared == KdbxUuid.zero, isTrue);
  });

  test('rifiuta un gruppo modelli inesistente', () async {
    final (container, onDisk) = await open();
    final settings = container.read(databaseSettingsProvider)!;
    final saved = await container
        .read(databaseSettingsViewModelProvider.notifier)
        .save(settings.copyWith(templatesGroupId: 'inesistente'));
    expect(saved, isFalse);
    final group = (await onDisk()).meta.entryTemplatesGroup;
    expect(group == null || group == KdbxUuid.zero, isTrue);
  });

  test('misura della KDF: durata nello stato', () async {
    final (container, _) = await open();

    await container
        .read(databaseSettingsViewModelProvider.notifier)
        .measure(const AesKdfSettings(rounds: 1000), kdbxVersion: 4);

    expect(container.read(databaseSettingsViewModelProvider).value, isNotNull);
  });

  test('database bloccato: nessuna impostazione', () async {
    final (container, _) = await open();

    container.read(databaseSessionProvider.notifier).lock();

    expect(container.read(databaseSettingsProvider), isNull);
  });
}
