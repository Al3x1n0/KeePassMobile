import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/file_select/demo_database.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/features/settings/settings_view_model.dart';
import 'package:keepass_mobile/features/unlock/unlock_view_model.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/item_edits.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/security/biometric_key_store.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/test_database.dart';

class _DemoStorage extends FileStorage {
  Uint8List? bytes;
  bool removed = false;
  int ensureCalls = 0;
  int copies = 0;
  int leases = 0;
  final removals = <bool>[];
  final released = <FileRef>[];
  Completer<void>? ensureGate;
  Completer<void>? readGate;
  Completer<void>? readEntered;

  @override
  Future<FileRef?> ensureDemoDatabase(Uint8List bytes) async {
    ensureCalls++;
    await ensureGate?.future;
    if (removed) return null;
    if (this.bytes == null) {
      this.bytes = Uint8List.fromList(bytes);
      copies++;
    }
    return DemoDatabaseRepository.file;
  }

  @override
  Future<FileRef> demoDatabaseRef() async => DemoDatabaseRepository.file;

  @override
  Future<void> deleteDemoDatabase({bool keepFile = false}) async {
    removed = true;
    removals.add(keepFile);
    if (!keepFile && leases == 0) bytes = null;
  }

  @override
  Future<bool> retainDemoDatabase() async {
    if (removed || bytes == null) return false;
    leases++;
    return true;
  }

  @override
  Future<void> releaseDemoDatabase() async {
    if (leases > 0) leases--;
    if (removed && leases == 0) bytes = null;
  }

  @override
  Future<bool> isDemoDatabaseRemoved() async => removed;

  @override
  Future<StoredFile> read(FileRef ref) async {
    if (readGate case final gate?) {
      readEntered?.complete();
      await gate.future;
    }
    final data = bytes;
    if (ref != DemoDatabaseRepository.file || data == null) {
      throw const FileUnavailableException();
    }
    return StoredFile(ref: ref, bytes: Uint8List.fromList(data));
  }

  @override
  Future<void> write(
    FileRef ref,
    Uint8List bytes, {
    String? expectedVersion,
  }) async {
    if (ref != DemoDatabaseRepository.file || this.bytes == null) {
      throw const FileUnavailableException();
    }
    this.bytes = Uint8List.fromList(bytes);
  }

  @override
  Future<void> release(FileRef ref) async => released.add(ref);
}

/// Cache separata dello stesso archivio persistente, come in un altro motore.
class _CachedPreferences extends Fake implements SharedPreferences {
  _CachedPreferences(this.delegate) {
    _refresh();
  }

  final SharedPreferences delegate;
  final _values = <String, Object?>{};

  void _refresh() {
    _values
      ..clear()
      ..addAll({for (final key in delegate.getKeys()) key: delegate.get(key)});
  }

  @override
  Object? get(String key) => _values[key];

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  List<String>? getStringList(String key) =>
      (_values[key] as List<String>?)?.toList();

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  int? getInt(String key) => _values[key] as int?;

  @override
  double? getDouble(String key) => _values[key] as double?;

  @override
  Set<String> getKeys() => _values.keys.toSet();

  @override
  bool containsKey(String key) => _values.containsKey(key);

  Future<bool> _write(
    String key,
    Object value,
    Future<bool> Function() save,
  ) async {
    final saved = await save();
    if (saved) _values[key] = value;
    return saved;
  }

  @override
  Future<bool> setString(String key, String value) =>
      _write(key, value, () => delegate.setString(key, value));

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _write(key, value.toList(), () => delegate.setStringList(key, value));

  @override
  Future<bool> setBool(String key, bool value) =>
      _write(key, value, () => delegate.setBool(key, value));

  @override
  Future<bool> setInt(String key, int value) =>
      _write(key, value, () => delegate.setInt(key, value));

  @override
  Future<bool> remove(String key) async {
    final removed = await delegate.remove(key);
    if (removed) _values.remove(key);
    return removed;
  }

  @override
  Future<void> reload() async {
    await delegate.reload();
    _refresh();
  }
}

class _Environment {
  _Environment(this.prefs, this.storage)
    : recents = RecentFilesRepository(prefs, storage),
      biometrics = BiometricKeyStore(prefs);

  final SharedPreferences prefs;
  final _DemoStorage storage;
  final RecentFilesRepository recents;
  final BiometricKeyStore biometrics;

  DemoDatabaseRepository repository() =>
      DemoDatabaseRepository(prefs, storage, recents, biometrics);

  ProviderContainer container({SharedPreferences? preferences}) =>
      ProviderContainer.test(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences ?? prefs),
          fileStorageProvider.overrideWithValue(storage),
        ],
      );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const demo = DemoDatabaseRepository.file;
  const userFile = FileRef(uri: 'content://docs/user', name: 'personale.kdbx');
  const sameName = FileRef(
    uri: 'content://docs/other-demo',
    name: 'Rifugio-Aurora.kdbx',
  );
  const keyFile = FileRef(uri: 'content://docs/key', name: 'prova.keyx');
  const texts = BiometricPromptTexts(title: 't', subtitle: 's', cancel: 'c');
  late FakeSecureStorage secure;

  setUp(() {
    secure = FakeSecureStorage.install();
    FakeClipboard(binding);
  });

  Future<_Environment> environment({
    List<RecentFile> recents = const [],
    String? state,
    bool remember = true,
    _DemoStorage? storage,
  }) async {
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: [
        for (final file in recents) jsonEncode(file.toJson()),
      ],
      DemoDatabaseRepository.stateKey: ?state,
    });
    final prefs = await SharedPreferences.getInstance();
    await AppSettingsRepository(prefs)
        .save(AppSettings(rememberRecentFiles: remember));
    return _Environment(prefs, storage ?? _DemoStorage());
  }

  Future<void> enableBiometrics(_Environment env) async {
    final database = newTestDatabase();
    await database.save();
    await env.biometrics.store(
      demo,
      database.header.transformedKey!,
      texts: texts,
    );
    database.clearSensitiveData();
  }

  group('DemoDatabaseRepository', () {
    test(
      'primo avvio concorrente: installa una sola copia nei recenti',
      () async {
        // given
        final env = await environment();
        final repository = env.repository();
        env.storage.ensureGate = Completer<void>();

        // when
        final first = repository.initialize();
        final second = repository.initialize();
        env.storage.ensureGate!.complete();
        await Future.wait([first, second]);
        await repository.initialize();

        // then
        final original = await rootBundle.load(
          'assets/demo/Rifugio-Aurora.kdbx',
        );
        expect(env.storage.bytes, Uint8List.sublistView(original));
        expect(env.storage.copies, 1);
        expect(env.storage.ensureCalls, 1);
        expect(env.recents.load().map((file) => file.database), [demo]);
        expect(env.prefs.getString(DemoDatabaseRepository.stateKey), 'ready');
        expect(repository.isPresent, isTrue);
      },
    );

    test(
      'upgrade: conserva tutti i recenti e i file chiave esistenti',
      () async {
        // given
        final env = await environment(
          recents: [
            const RecentFile(database: userFile, keyFile: keyFile),
            const RecentFile(database: sameName),
          ],
        );
        final repository = env.repository();

        // when
        await repository.initialize();

        // then
        expect(env.recents.load().map((file) => file.database), [
          demo,
          userFile,
          sameName,
        ]);
        expect(env.recents.load()[1].keyFile, keyFile);
        expect(repository.isDemo(demo), isTrue);
        expect(repository.isDemo(sameName), isFalse);
        expect(env.storage.released, isEmpty);
      },
    );

    test(
      'riavvio prima del marcatore: conserva modifiche e riferimento',
      () async {
        // given
        final savedBytes = Uint8List.fromList([4, 3, 2, 1]);
        final storage = _DemoStorage()..bytes = savedBytes;
        final env = await environment(
          storage: storage,
          recents: [const RecentFile(database: demo, keyFile: keyFile)],
        );

        // when
        await env.repository().initialize();

        // then
        expect(storage.bytes, savedBytes);
        expect(storage.copies, 0);
        expect(env.recents.load().single.database, demo);
        expect(env.recents.load().single.keyFile, keyFile);
        expect(env.prefs.getString(DemoDatabaseRepository.stateKey), 'ready');
      },
    );

    test(
      'installazione completata: il riavvio non ricopia il database',
      () async {
        // given
        final storage = _DemoStorage()..bytes = Uint8List.fromList([9, 8, 7]);
        final env = await environment(
          state: 'ready',
          storage: storage,
          recents: [const RecentFile(database: demo)],
        );

        // when
        await env.repository().initialize();

        // then
        expect(storage.ensureCalls, 0);
        expect(storage.bytes, [9, 8, 7]);
        expect(env.recents.load(), hasLength(1));
      },
    );

    test(
      'la copia si sblocca, salva e riapre senza modificare l’asset',
      () async {
        // given
        final original = List<int>.of(
          Uint8List.sublistView(
            await rootBundle.load('assets/demo/Rifugio-Aurora.kdbx'),
          ),
        );
        final env = await environment();
        await env.repository().initialize();
        final container = env.container();
        container.listen(unlockViewModelProvider, (_, _) {});
        await container.read(unlockViewModelProvider.future);
        final unlock = container.read(unlockViewModelProvider.notifier);
        const args = UnlockArgs(database: PickedFile(ref: demo));
        await unlock.unlock(args: args, password: 'demo1234');
        expect(container.read(unlockViewModelProvider).hasError, isFalse);
        final opened = container.read(databaseSessionProvider)!;
        final sessions = container.read(databaseSessionProvider.notifier);

        // when
        await sessions.apply(
          updateGroupEdit(
            itemIdOf(opened.database.root),
            GroupDraft(
              name: 'Demo modificata',
              icon: opened.database.root.icon,
            ),
          ),
        );
        sessions.lock();
        await unlock.unlock(args: args, password: 'demo1234');

        // then
        expect(container.read(unlockViewModelProvider).hasError, isFalse);
        final reopened = container.read(databaseSessionProvider)!;
        expect(reopened.file, demo);
        expect(reopened.database.root.name, 'Demo modificata');
        expect(env.storage.bytes, isNot(original));
        expect(env.recents.load().single.database, demo);
        final bundled = await rootBundle.load(
          'assets/demo/Rifugio-Aurora.kdbx',
        );
        expect(Uint8List.sublistView(bundled), original);
      },
    );

    test('rimozione nativa già registrata: non ripristina la demo', () async {
      // given
      final storage = _DemoStorage()..removed = true;
      final env = await environment(storage: storage);

      // when
      final repository = env.repository();
      await repository.initialize();

      // then
      expect(storage.copies, 0);
      expect(storage.bytes, isNull);
      expect(env.recents.load(), isEmpty);
      expect(repository.isRemoved, isTrue);
    });

    test(
      'rimozione: elimina copia, recenti, chiave e rifiuto biometrico',
      () async {
        // given
        final env = await environment();
        final repository = env.repository();
        await repository.initialize();
        await enableBiometrics(env);
        await env.biometrics.declineOffer(demo);
        expect(env.biometrics.isEnabled(demo), isTrue);
        expect(secure.data, isNotEmpty);

        // when
        await repository.remove();
        await env.repository().initialize();

        // then
        expect(env.recents.load(), isEmpty);
        expect(env.biometrics.isEnabled(demo), isFalse);
        expect(env.biometrics.isOfferDeclined(demo), isFalse);
        expect(secure.data, isEmpty);
        expect(repository.isRemoved, isTrue);
        expect(repository.isPresent, isFalse);
        expect(env.storage.bytes, isNull);
        expect(env.storage.copies, 1);
      },
    );

    test(
      'rimozione interrotta: completa la pulizia al successivo avvio',
      () async {
        // given
        final storage = _DemoStorage()
          ..removed = true
          ..bytes = Uint8List.fromList([1, 2, 3]);
        final env = await environment(
          state: 'removed',
          storage: storage,
          recents: [
            const RecentFile(database: demo),
            const RecentFile(database: userFile),
          ],
        );
        await enableBiometrics(env);

        // when
        await env.repository().initialize();

        // then
        expect(env.recents.load().single.database, userFile);
        expect(env.biometrics.isEnabled(demo), isFalse);
        expect(storage.bytes, isNull);
        expect(storage.ensureCalls, 0);
      },
    );

    test('upgrade con recenti disattivati: rispetta la preferenza', () async {
      // given
      final env = await environment(remember: false);

      // when
      final repository = env.repository();
      await repository.initialize();
      await AppSettingsRepository(env.prefs).save(const AppSettings());
      await env.repository().initialize();

      // then
      expect(env.storage.ensureCalls, 0);
      expect(env.storage.bytes, isNull);
      expect(env.recents.load(), isEmpty);
      expect(repository.isRemoved, isTrue);
    });

    test(
      'rimozione rinviata: il file resta scrivibile finché è in uso',
      () async {
        // given
        final env = await environment();
        final repository = env.repository();
        await repository.initialize();

        // when
        await repository.remove(keep: {demo});
        await env.storage.write(demo, Uint8List.fromList([7, 6, 5]));
        await repository.cleanup(keep: {demo});

        // then
        expect(repository.isRemoved, isTrue);
        expect(env.recents.load(), isEmpty);
        expect((await env.storage.read(demo)).bytes, [7, 6, 5]);
        await repository.cleanup();
        expect(env.storage.bytes, isNull);
      },
    );
  });

  group('Rimozione demo e sessioni', () {
    test(
      'rimozione nell’app durante lo sblocco Autofill: non apre la demo',
      () async {
        // given
        final env = await environment();
        await env.repository().initialize();
        final autofill = env.container(
          preferences: _CachedPreferences(env.prefs),
        );
        final mainApp = env.container();
        autofill.listen(unlockViewModelProvider, (_, _) {});
        await autofill.read(unlockViewModelProvider.future);
        mainApp.listen(settingsViewModelProvider, (_, _) {});
        env.storage
          ..readEntered = Completer<void>()
          ..readGate = Completer<void>();

        // when
        final opening = autofill
            .read(unlockViewModelProvider.notifier)
            .unlock(
              args: const UnlockArgs(database: PickedFile(ref: demo)),
              password: 'demo1234',
            );
        await env.storage.readEntered!.future;
        expect(env.storage.leases, 1);
        await mainApp
            .read(settingsViewModelProvider.notifier)
            .update(const AppSettings(rememberRecentFiles: false));
        expect(env.storage.bytes, isNotNull);
        env.storage.readGate!.complete();
        await opening;

        // then
        expect(autofill.read(databaseSessionProvider), isNull);
        expect(autofill.read(recentFilesRepositoryProvider).load(), isEmpty);
        expect(env.recents.load(), isEmpty);
        expect(env.storage.leases, 0);
        expect(env.storage.bytes, isNull);
        expect(env.repository().isRemoved, isTrue);
      },
    );

    test(
      'Autofill aperto: la rimozione nell’app aspetta l’ultimo motore',
      () async {
        // given
        final env = await environment();
        await env.repository().initialize();
        final autofillPreferences = _CachedPreferences(env.prefs);
        final autofill = env.container(preferences: autofillPreferences);
        final mainApp = env.container();
        autofill.listen(unlockViewModelProvider, (_, _) {});
        await autofill.read(unlockViewModelProvider.future);
        final unlock = autofill.read(unlockViewModelProvider.notifier);
        const args = UnlockArgs(database: PickedFile(ref: demo));
        await unlock.unlock(args: args, password: 'demo1234');
        expect(autofill.read(unlockViewModelProvider).hasError, isFalse);
        expect(env.storage.leases, 1);
        final sessions = autofill.read(databaseSessionProvider.notifier);
        final opened = autofill.read(databaseSessionProvider)!;
        mainApp.listen(settingsViewModelProvider, (_, _) {});

        // when
        await mainApp
            .read(settingsViewModelProvider.notifier)
            .update(const AppSettings(rememberRecentFiles: false));

        // then
        expect(mainApp.read(databaseSessionProvider), isNull);
        expect(autofill.read(databaseSessionProvider), same(opened));
        expect(
          autofillPreferences.getString(DemoDatabaseRepository.stateKey),
          'ready',
        );
        expect(
          AppSettingsRepository(autofillPreferences).load().rememberRecentFiles,
          isTrue,
        );
        expect(env.storage.bytes, isNotNull);
        expect(env.recents.load(), isEmpty);
        await sessions.apply(
          updateGroupEdit(
            itemIdOf(opened.database.root),
            GroupDraft(
              name: 'Demo da Autofill',
              icon: opened.database.root.icon,
            ),
          ),
        );
        expect(
          autofill.read(databaseSessionProvider)!.database.root.name,
          'Demo da Autofill',
        );
        sessions.lock();
        await pumpEventQueue();
        expect(env.storage.leases, 0);
        expect(env.storage.bytes, isNull);
        await unlock.unlock(args: args, password: 'demo1234');
        expect(
          autofill.read(unlockViewModelProvider).error,
          isA<FileUnavailableException>(),
        );
        expect(autofill.read(databaseSessionProvider), isNull);
        expect(env.recents.load(), isEmpty);
        expect(env.repository().isRemoved, isTrue);
        expect(env.storage.copies, 1);
      },
    );

    test(
      'la X elimina definitivamente solo il riferimento demo gestito',
      () async {
        // given
        final env = await environment(
          recents: [const RecentFile(database: sameName)],
        );
        await env.repository().initialize();
        final container = env.container();
        container.listen(recentFilesProvider, (_, _) {});

        // when
        await container
            .read(recentFilesProvider.notifier)
            .forget(const RecentFile(database: sameName));

        // then
        expect(env.storage.removals, isEmpty);
        expect(env.storage.bytes, isNotNull);
        await container
            .read(recentFilesProvider.notifier)
            .forget(const RecentFile(database: demo));
        expect(container.read(recentFilesProvider), isEmpty);
        expect(env.storage.bytes, isNull);
        expect(env.repository().isRemoved, isTrue);
      },
    );

    for (final demoIsAdditional in [false, true]) {
      test(
        'recenti disattivati: conserva demo ${demoIsAdditional ? 'secondaria' : 'attiva'} fino alla chiusura',
        () async {
          // given
          final env = await environment(
            recents: [const RecentFile(database: userFile)],
          );
          await env.repository().initialize();
          final container = env.container();
          container.read(demoDatabaseCleanupProvider);
          container.listen(settingsViewModelProvider, (_, _) {});
          final sessions = container.read(databaseSessionProvider.notifier);
          sessions.open(
            DatabaseSession(file: demo, database: newTestDatabase()),
          );
          if (demoIsAdditional) {
            sessions.openAdditional(
              DatabaseSession(file: userFile, database: newTestDatabase()),
              sessions.lockGeneration,
            );
          }
          final active = container.read(databaseSessionProvider);

          // when
          await container
              .read(settingsViewModelProvider.notifier)
              .update(const AppSettings(rememberRecentFiles: false));

          // then
          expect(container.read(databaseSessionProvider), same(active));
          expect(env.recents.load(), isEmpty);
          expect(env.repository().isRemoved, isTrue);
          expect(env.storage.bytes, isNotNull);
          await env.storage.write(demo, Uint8List.fromList([5, 4, 3]));
          if (demoIsAdditional) {
            sessions.closeSession(demo);
            expect(container.read(databaseSessionProvider)?.file, userFile);
          } else {
            sessions.lock();
          }
          await pumpEventQueue();
          expect(env.storage.bytes, isNull);
        },
      );
    }

    test('uno sblocco in ritardo non reinserisce la demo rimossa', () async {
      // given
      final env = await environment();
      final repository = env.repository();
      await repository.initialize();
      await repository.remove(keep: {demo});

      // when
      await env.recents.remember(const RecentFile(database: demo));

      // then
      expect(env.recents.load(), isEmpty);
      expect(repository.isRemoved, isTrue);
    });
  });
}
