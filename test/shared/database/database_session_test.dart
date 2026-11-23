import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void _rename(KdbxDatabase database) => database.meta.name = 'Nuovo';

void _changeKdf(KdbxDatabase database) =>
    database.header.kdfSettings = const AesKdfSettings(rounds: 1234);

DatabaseEdit _signalEdit(SendPort started) => (db) {
  started.send(null);
  db.meta.name = 'Modifica in corso';
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const dir = 'test/fixtures/kdbx/';
  Uint8List fixture(String name) => File('$dir$name').readAsBytesSync();

  group('openDatabase', () {
    test('apre in un isolate un KDBX 4 con Argon2id', () async {
      final db = await openDatabase(
        data: fixture('test4_argon2id.kdbx'),
        password: 'password',
      );
      expect(db.header.version.$1, 4);
    });

    test(
      'password vuota e file chiave: prova prima la password vuota',
      () async {
        final db = await openDatabase(
          data: fixture('test4_blankpass.kdbx'),
          password: '',
          keyFile: fixture('test4.key'),
        );
        expect(db.header.version.$1, 4);
      },
    );

    test(
      'password vuota e file chiave: database creato senza password',
      () async {
        // given: database protetto dalla sola chiave
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        final created = KdbxDatabase.create(
          credentials: KdbxCredentials(keyData: key),
          name: 'solo chiave',
        );
        created.header.kdf = KdfId.aes;
        created.createEntry(parent: created.root).fields['Title'] =
            KdbxTextField.fromText(text: 'voce');
        final bytes = Uint8List.fromList(await created.save());

        // when
        final db = await openDatabase(data: bytes, password: '', keyFile: key);

        // then
        expect(db.root.allEntries.single.fields['Title']?.text, 'voce');
      },
    );

    test('password errata: InvalidCredentialsError', () {
      expect(
        openDatabase(
          data: fixture('test4_aes_uncompressed.kdbx'),
          password: 'sbagliata',
        ),
        throwsA(isA<InvalidCredentialsError>()),
      );
    });

    test('file che non è un database KeePass: FileCorruptedError', () {
      expect(
        openDatabase(
          data: Uint8List.fromList(utf8.encode('non è un database KeePass')),
          password: 'password',
        ),
        throwsA(isA<FileCorruptedError>()),
      );
    });
  });

  group('sola chiave derivata (ADR-008)', () {
    Future<(File, ProviderContainer)> session() async {
      final (file, reopened) = await saveToTempFile(newTestDatabase());
      final container = await newTestContainer(file: file, database: reopened);
      addTearDown(container.dispose);
      return (file, container);
    }

    KdbxTransformedKey keyOf(ProviderContainer container) => container
        .read(databaseSessionProvider)!
        .database
        .header
        .transformedKey!;

    test(
      'il salvataggio non ruota il salt: la chiave salvata riapre il file',
      () async {
        final (file, container) = await session();
        final before = keyOf(container);
        final notifier = container.read(databaseSessionProvider.notifier)
          ..useTransformedKeyOnly();
        expect(container.read(databaseSessionProvider)?.hasRawKey, isFalse);

        await notifier.apply(_rename);

        expect(keyOf(container).fingerprint, before.fingerprint);
        final again = await openDatabaseWithKey(
          data: bytesOf(file),
          key: before,
        );
        expect(again.meta.name, 'Nuovo');
      },
    );

    test(
      'con la password il salt ruota: la chiave vecchia non apre più',
      () async {
        final (file, container) = await session();
        final before = keyOf(container);

        await container.read(databaseSessionProvider.notifier).apply(_rename);

        expect(keyOf(container).fingerprint, isNot(before.fingerprint));
        await expectLater(
          openDatabaseWithKey(data: bytesOf(file), key: before),
          throwsA(isA<TransformedKeyStaleError>()),
        );
      },
    );

    test('la KDF non si cambia: errore e file invariato', () async {
      final (file, container) = await session();
      final bytes = bytesOf(file);
      final notifier = container.read(databaseSessionProvider.notifier)
        ..useTransformedKeyOnly();

      await expectLater(
        notifier.apply(_changeKdf),
        throwsA(isA<TransformedKeyStaleError>()),
      );
      expect(bytesOf(file), bytes);
    });
  });

  test('il blocco azzera i buffer e annulla un salvataggio in corso', () async {
    final db = newTestDatabase();
    addTestEntry(
      db,
      db.root,
      {EntryFields.password: 'valore di prova'},
      protectedKeys: {EntryFields.password},
    );
    final (file, database) = await saveToTempFile(db);
    addTearDown(() => file.parent.deleteSync(recursive: true));
    final container = await newTestContainer(file: file, database: database);
    addTearDown(container.dispose);
    final session = container.read(databaseSessionProvider.notifier);
    final key = database.header.transformedKey!.key;
    final field =
        database.root.allEntries.single.fields[EntryFields.password]
            as ProtectedTextField;
    final before = bytesOf(file);
    final started = ReceivePort();
    addTearDown(started.close);

    final save = session.apply(_signalEdit(started.sendPort));
    final canceled = expectLater(save, throwsA(isA<DatabaseLockedException>()));
    await started.first;
    session.lock();
    await canceled;

    expect(container.read(databaseSessionProvider), isNull);
    expect(key.bytes, everyElement(0));
    expect(field.protectedText.bytes, everyElement(0));
    expect(bytesOf(file), before);
  });

  for (final dispose in [false, true]) {
    test(
      '${dispose ? "dispose" : "blocco"}: pulisce subito anche il database in precaricamento',
      () async {
        // given: la sessione non è ancora pubblicata, una lettura è in attesa.
        final (file, database) = await saveToTempFile(newTestDatabase());
        addTearDown(() => file.parent.deleteSync(recursive: true));
        final key = database.header.transformedKey!.key;
        final container = await newTestContainer();
        final sessions = container.read(databaseSessionProvider.notifier);
        sessions.trackOpeningDatabase(database);
        expect(key.bytes, isNot(everyElement(0)));

        // when
        if (dispose) {
          container.dispose();
        } else {
          sessions.lock();
        }

        // then: nessuna attesa per completare la lettura dello store.
        expect(key.bytes, everyElement(0));
        sessions.untrackOpeningDatabase(database);
      },
    );
  }

  test('cronologie separate: salvataggio, cambio database, chiusura e blocco', () async {
    // given
    final first = newTestDatabase();
    final firstEntry = addTestEntry(first, first.root, {
      EntryFields.title: 'Prima',
    });
    final secondEntry = addTestEntry(first, first.root, {
      EntryFields.title: 'Seconda',
    });
    final firstId = itemIdOf(firstEntry);
    final secondId = itemIdOf(secondEntry);
    final (file, database) = await saveToTempFile(first);
    addTearDown(() => file.parent.deleteSync(recursive: true));
    final container = await newTestContainer();
    final sessions = container.read(databaseSessionProvider.notifier);
    final original = DatabaseSession(
      file: fileRefOf(file),
      database: database,
      recentPasswordIds: [firstId],
    );
    sessions.open(original);
    final firstIds = original.recentPasswordIds;
    final started = ReceivePort();
    addTearDown(started.close);

    // when: una copia arriva durante il salvataggio della versione precedente.
    final saving = sessions.apply(_signalEdit(started.sendPort));
    await started.first;
    sessions.recordRecentPassword(secondId);
    await saving;

    // then: la nuova versione conserva il recente aggiornato.
    expect(container.read(databaseSessionProvider)!.recentPasswordIds, [
      secondId,
      firstId,
    ]);
    expect(firstIds, [secondId, firstId]);
    expect(() => firstIds.add(firstId), throwsUnsupportedError);

    final otherDatabase = newTestDatabase();
    final (otherFile, other) = await saveToTempFile(otherDatabase);
    addTearDown(() => otherFile.parent.deleteSync(recursive: true));
    final otherSession = DatabaseSession(
      file: fileRefOf(otherFile),
      database: other,
      recentPasswordIds: ['00000000000000000000000000000001'],
    );
    final otherIds = otherSession.recentPasswordIds;
    sessions.openAdditional(otherSession, sessions.lockGeneration);
    sessions.switchTo(fileRefOf(file));
    expect(container.read(databaseSessionProvider)!.recentPasswordIds, [
      secondId,
      firstId,
    ]);
    sessions.closeSession(fileRefOf(file));
    expect(firstIds, isEmpty);
    expect(otherIds, ['00000000000000000000000000000001']);
    sessions.lock();
    expect(otherIds, isEmpty);
  });
}
