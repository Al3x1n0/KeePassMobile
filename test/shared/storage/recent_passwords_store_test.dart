import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/recent_passwords_store.dart';

import '../../helpers/fake_secure_storage.dart';

String _id(int value) => value.toRadixString(16).padLeft(32, '0');

void main() {
  const file = FileRef(uri: 'file:///test/first.kdbx', name: 'first.kdbx');
  const otherFile = FileRef(
    uri: 'file:///test/second.kdbx',
    name: 'second.kdbx',
  );
  final first = RecentPasswordsStore.databaseKey(file, _id(100));
  final second = RecentPasswordsStore.databaseKey(otherFile, _id(100));

  late FakeSecureStorage platform;
  late RecentPasswordsStore store;

  setUp(() {
    platform = FakeSecureStorage.install();
    store = RecentPasswordsStore();
  });

  test(
    'recente in testa, al massimo 15 identificatori distinti per database',
    () async {
      await Future.wait([
        for (var index = 1; index <= 16; index++)
          store.record(first, _id(index)),
        store.record(second, _id(1)),
        store.record(first, _id(4)),
      ]);

      expect(await RecentPasswordsStore().read(first), [
        _id(4),
        for (var index = 16; index >= 2; index--)
          if (index != 4) _id(index),
      ]);
      expect(await store.read(second), [_id(1)]);
      expect(first, isNot(contains(file.uri)));
      expect(first, isNot(contains(_id(100))));
      expect(first, isNot(RecentPasswordsStore.databaseKey(file, _id(101))));
      expect(
        platform.options.every(
          (options) => options['storageNamespace'] == 'kpm_recent_passwords',
        ),
        isTrue,
      );
    },
  );

  test(
    'la cancellazione riguarda solo la cronologia in ordine con le scritture',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      platform.data['remote:synthetic'] = 'unrelated';

      await Future.wait([
        store.record(first, _id(1)),
        store.record(second, _id(2)),
        store.clear(),
        store.record(first, _id(3)),
      ]);

      expect(await store.read(first), [_id(3)]);
      expect(await store.read(second), isEmpty);
      expect(platform.data['remote:synthetic'], 'unrelated');
      expect(
        platform.options.every(
          (options) => options['accountName'] == 'kpm_recent_passwords',
        ),
        isTrue,
      );
    },
  );

  test('ignora i dati non validi e riprende a registrare', () async {
    platform.data[first] = 'invalid JSON';
    expect(await store.read(first), isEmpty);
    await store.record(first, _id(1));
    expect(await store.read(first), [_id(1)]);

    platform.data[first] = jsonEncode([_id(1), _id(1), 'invalid', 2, _id(2)]);
    expect(await store.read(first), [_id(1), _id(2)]);
    await store.record(first, 'invalid');
    expect(await store.read(first), [_id(1), _id(2)]);
  });

  test(
    'una lettura fallita lascia la cronologia disponibile per il prossimo uso',
    () async {
      await store.record(first, _id(1));
      platform.failure = PlatformException(code: 'unavailable');
      await store.record(first, _id(2));
      expect(await store.read(first), isEmpty);

      platform.failure = null;
      await store.record(first, _id(3));
      expect(await store.read(first), [_id(3), _id(1)]);
    },
  );
}
