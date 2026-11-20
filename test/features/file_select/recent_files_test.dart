import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Registra i permessi rilasciati, senza toccare file o plugin.
class _RecordingStorage extends FileStorage {
  final released = <FileRef>[];

  @override
  Future<void> release(FileRef ref) async => released.add(ref);
}

class _FailingPreferences extends Fake implements SharedPreferences {
  _FailingPreferences(this.values);
  final List<String> values;
  @override
  List<String>? getStringList(String key) => values;
  @override
  Future<bool> setStringList(String key, List<String> value) async => false;
}

void main() {
  const a = FileRef(uri: 'content://docs/a', name: 'a.kdbx');
  const b = FileRef(uri: 'content://docs/b', name: 'b.kdbx');
  const key = FileRef(uri: 'content://docs/a.key', name: 'a.key');
  late _RecordingStorage storage;

  Future<RecentFilesRepository> repository([
    Map<String, Object> values = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(values);
    storage = _RecordingStorage();
    return RecentFilesRepository(
      await SharedPreferences.getInstance(),
      storage,
    );
  }

  test('ricorda i file dal più recente, senza duplicati', () async {
    final repo = await repository();
    await repo.remember(const RecentFile(database: a));
    await repo.remember(const RecentFile(database: b));
    await repo.remember(const RecentFile(database: a, keyFile: key));

    final files = repo.load();
    expect(files.map((f) => f.database), [a, b]);
    expect(files.first.keyFile, key);
  });

  test(
    'dimentica un file e ne rilascia il permesso e quello del file chiave',
    () async {
      final repo = await repository();
      await repo.remember(const RecentFile(database: a, keyFile: key));
      await repo.remember(const RecentFile(database: b));

      final files = await repo.forget(a);

      expect(files.map((f) => f.database), [b]);
      expect(repo.load().map((f) => f.database), [b]);
      expect(storage.released, unorderedEquals([a, key]));
    },
  );

  test(
    'un file chiave ancora usato da un altro database non viene rilasciato',
    () async {
      final repo = await repository();
      await repo.remember(const RecentFile(database: a, keyFile: key));
      await repo.remember(const RecentFile(database: b, keyFile: key));

      await repo.forget(a);

      expect(storage.released, [a]);
    },
  );

  test('file chiave sostituito: il precedente viene rilasciato', () async {
    final repo = await repository();
    await repo.remember(const RecentFile(database: a, keyFile: key));

    await repo.remember(const RecentFile(database: a));

    expect(storage.released, [key]);
  });

  test(
    'riferimento aggiornato dal sistema: sostituisce la voce precedente',
    () async {
      final repo = await repository();
      const old = FileRef(uri: 'bookmark:vecchio', name: 'a.kdbx');
      const refreshed = FileRef(uri: 'bookmark:nuovo', name: 'a.kdbx');
      await repo.remember(const RecentFile(database: old));
      await repo.remember(const RecentFile(database: b));

      await repo.remember(
        const RecentFile(database: refreshed),
        replacing: old,
      );

      expect(repo.load().map((f) => f.database), [refreshed, b]);
    },
  );

  test(
    'svuota l\'elenco: rilascia i permessi tranne quelli da tenere',
    () async {
      final repo = await repository();
      await repo.remember(const RecentFile(database: a, keyFile: key));
      await repo.remember(const RecentFile(database: b));

      final files = await repo.clear(keep: {a, key});

      expect(files, isEmpty);
      expect(repo.load(), isEmpty);
      expect(storage.released, [b]);
    },
  );

  test('dimentica i file chiave: restano i database', () async {
    final repo = await repository();
    await repo.remember(const RecentFile(database: a, keyFile: key));
    await repo.remember(const RecentFile(database: b));

    await repo.forgetKeyFiles();

    expect(repo.load().map((f) => f.database), [b, a]);
    expect(repo.load().map((f) => f.keyFile), [null, null]);
    expect(storage.released, [key]);
  });

  test('rilascia solo i file che l\'elenco non cita', () async {
    final repo = await repository();
    await repo.remember(const RecentFile(database: a));

    await repo.releaseUnused([a, b, key]);

    expect(storage.released, unorderedEquals([b, key]));
  });

  test('ignora le voci salvate non valide', () async {
    final repo = await repository({
      RecentFilesRepository.storageKey: [
        'non json',
        jsonEncode({'altro': 1}),
        jsonEncode(const RecentFile(database: a).toJson()),
      ],
    });

    expect(repo.load().map((f) => f.database), [a]);
  });
  test('preferenze non scritte: non rilascia il vecchio riferimento', () async {
    final storage = _RecordingStorage();
    final prefs = _FailingPreferences([
      jsonEncode(const RecentFile(database: a).toJson()),
    ]);
    final repo = RecentFilesRepository(prefs, storage);
    await expectLater(
      repo.remember(const RecentFile(database: b), replacing: a),
      throwsA(isA<RecentFilesWriteException>()),
    );
    expect(repo.load().single.database, a);
    expect(storage.released, isEmpty);
  });
}
