import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/external_change.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void _addHere(KdbxDatabase db) =>
    addTestEntry(db, db.root, {EntryFields.title: 'Qui'});

void _changeKey(KdbxDatabase db) => db.header.credentials = KdbxCredentials(
  password: ProtectedData.fromString('nuova'),
);

Set<String> titles(KdbxDatabase db) => {
  for (final e in db.root.allEntries)
    if (e.parent != db.recycleBin) e.fields[EntryFields.title]?.text ?? '',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late File file;
  late List<ExternalChangeChoice> answers;
  late int asked;

  /// Database con la voce "Comune", aperto in sessione con il controllo delle
  /// modifiche esterne; l'utente risponde con [answers] in ordine.
  Future<ProviderContainer> open([
    List<ExternalChangeChoice> choices = const [],
  ]) async {
    final db = newTestDatabase();
    addTestEntry(db, db.root, {EntryFields.title: 'Comune'});
    final (saved, reopened) = await saveToTempFile(db);
    file = saved;
    answers = [...choices];
    asked = 0;
    final container = await newTestContainer(
      file: file,
      database: reopened,
      checkExternalChanges: true,
      overrides: [
        externalChangeResolverProvider.overrideWithValue((_) async {
          asked++;
          return answers.removeAt(0);
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Un'altra app aggiunge "Altrove" (e un salt nuovo) e salva il file.
  Future<void> changeElsewhere({
    void Function(KdbxDatabase db)? also,
    KdbxCredentials? credentials,
  }) async {
    final other = await reopenFile(file);
    addTestEntry(other, other.root, {EntryFields.title: 'Altrove'});
    also?.call(other);
    if (credentials != null) other.header.credentials = credentials;
    file.writeAsBytesSync(await other.save());
  }

  DatabaseSessionNotifier sessions(ProviderContainer c) =>
      c.read(databaseSessionProvider.notifier);

  test('file invariato: nessuna domanda', () async {
    final c = await open();

    await sessions(c).apply(_addHere);

    expect(asked, 0);
    expect(titles(await reopenFile(file)), {'Comune', 'Qui'});
  });

  test('Sincronizza: le due versioni unite nel file e in memoria', () async {
    final c = await open([ExternalChangeChoice.synchronize]);
    await changeElsewhere();

    await sessions(c).apply(_addHere);

    expect(asked, 1);
    expect(titles(await reopenFile(file)), {'Comune', 'Altrove', 'Qui'});
    expect(titles(c.read(databaseSessionProvider)!.database), {
      'Comune',
      'Altrove',
      'Qui',
    });
    // Il file scritto è quello noto: il salvataggio dopo non chiede.
    await sessions(c).apply((db) => db.meta.name = 'Dopo');
    expect(asked, 1);
  });

  test('Sincronizza: una voce eliminata altrove sparisce anche qui', () async {
    final c = await open([ExternalChangeChoice.synchronize]);
    await changeElsewhere(
      also: (db) => db.move(
        item: db.root.allEntries.firstWhere(
          (e) => e.fields[EntryFields.title]?.text == 'Comune',
        ),
      ),
    );

    await sessions(c).apply(_addHere);

    expect(titles(await reopenFile(file)), {'Altrove', 'Qui'});
  });

  test('Sovrascrivi: resta solo la versione di questa app', () async {
    final c = await open([ExternalChangeChoice.overwrite]);
    await changeElsewhere();

    await sessions(c).apply(_addHere);

    expect(titles(await reopenFile(file)), {'Comune', 'Qui'});
  });

  test('Annulla: errore dedicato, file e sessione invariati', () async {
    final c = await open([ExternalChangeChoice.cancel]);
    await changeElsewhere();
    final bytes = bytesOf(file);
    final before = c.read(databaseSessionProvider);

    await expectLater(
      sessions(c).apply(_addHere),
      throwsA(isA<ExternalChangeCanceledException>()),
    );

    expect(bytesOf(file), bytes);
    expect(c.read(databaseSessionProvider), same(before));
  });

  test('chiave diversa nel file esterno: errore, niente scritto; poi si può sovrascrivere', () async {
    final c = await open([
      ExternalChangeChoice.synchronize,
      ExternalChangeChoice.overwrite,
    ]);
    await changeElsewhere(
      credentials: KdbxCredentials(password: ProtectedData.fromString('altra')),
    );
    final bytes = bytesOf(file);

    await expectLater(
      sessions(c).apply(_addHere),
      throwsA(isA<SyncKeyMismatchException>()),
    );
    expect(bytesOf(file), bytes);

    await sessions(c).apply(_addHere);
    expect(titles(await reopenFile(file)), {'Comune', 'Qui'});
  });

  test(
    'file sostituito con un altro database: errore, niente scritto',
    () async {
      final c = await open([ExternalChangeChoice.synchronize]);
      final other = newTestDatabase();
      file.writeAsBytesSync(await other.save());
      final bytes = bytesOf(file);

      await expectLater(
        sessions(c).apply(_addHere),
        throwsA(isA<SyncDifferentDatabaseException>()),
      );
      expect(bytesOf(file), bytes);
    },
  );

  test(
    'sola chiave derivata e salt nuovo altrove: serve la password',
    () async {
      final c = await open([ExternalChangeChoice.synchronize]);
      sessions(c).useTransformedKeyOnly();
      await changeElsewhere();

      await expectLater(
        sessions(c).apply(_addHere),
        throwsA(isA<SyncNeedsPasswordException>()),
      );
    },
  );

  test('cambio della chiave principale con sincronizzazione: unito con la chiave vecchia, scritto con la nuova', () async {
    final c = await open([ExternalChangeChoice.synchronize]);
    await changeElsewhere();

    await sessions(c).apply(_changeKey);

    final reopened = await KdbxDatabase.fromBytes(
      data: bytesOf(file),
      credentials: KdbxCredentials(password: ProtectedData.fromString('nuova')),
    );
    expect(titles(reopened), {'Comune', 'Altrove'});
  });

  test('database bloccato mentre l\'utente decide: niente scritto', () async {
    late ProviderContainer c;
    final db = newTestDatabase();
    final (saved, reopened) = await saveToTempFile(db);
    file = saved;
    c = await newTestContainer(
      file: file,
      database: reopened,
      checkExternalChanges: true,
      overrides: [
        externalChangeResolverProvider.overrideWithValue((_) async {
          c.read(databaseSessionProvider.notifier).lock();
          return ExternalChangeChoice.overwrite;
        }),
      ],
    );
    addTearDown(c.dispose);
    await changeElsewhere();
    final bytes = bytesOf(file);

    await expectLater(
      sessions(c).apply(_addHere),
      throwsA(isA<DatabaseLockedException>()),
    );
    expect(bytesOf(file), bytes);
  });

  group('Sincronizza ora', () {
    test('file invariato: niente scritto', () async {
      final c = await open();
      final modified = file.lastModifiedSync();

      expect(await sessions(c).synchronize(), SyncResult.unchanged);
      expect(file.lastModifiedSync(), modified);
    });

    test('file cambiato: unito senza domande', () async {
      final c = await open();
      await changeElsewhere();

      expect(await sessions(c).synchronize(), SyncResult.synchronized);

      expect(asked, 0);
      expect(titles(c.read(databaseSessionProvider)!.database), {
        'Comune',
        'Altrove',
      });
      expect(titles(await reopenFile(file)), {'Comune', 'Altrove'});
      expect(await sessions(c).synchronize(), SyncResult.unchanged);
    });
  });

  test('fileHashOf: cambia con il contenuto', () {
    expect(
      fileHashOf(Uint8List.fromList([1, 2])),
      isNot(fileHashOf(Uint8List.fromList([1, 3]))),
    );
  });
}
