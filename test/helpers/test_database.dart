import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/external_change.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:secure_clipboard/secure_clipboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chiave principale dei database creati nei test.
const testMasterKey = 'segreta';

KdbxCredentials testCredentials() =>
    KdbxCredentials(password: ProtectedData.fromString(testMasterKey));

/// Database KDBX 4 con KDF veloce (AES-KDF) per i test.
KdbxDatabase newTestDatabase() {
  final db = KdbxDatabase.create(credentials: testCredentials(), name: 'Prova');
  db.header.kdf = KdfId.aes;
  return db;
}

KdbxEntry addTestEntry(
  KdbxDatabase db,
  KdbxGroup group,
  Map<String, String> fields, {
  Set<String> protectedKeys = const {},
}) {
  final entry = db.createEntry(parent: group, icon: KdbxIcon.key);
  for (final MapEntry(:key, :value) in fields.entries) {
    entry.fields[key] = KdbxTextField.fromText(
      text: value,
      protected: protectedKeys.contains(key),
    );
  }
  return entry;
}

/// Salva [db] in un file temporaneo e lo riapre, come farebbe lo sblocco:
/// la sessione contiene così un database letto da file.
Future<(File, KdbxDatabase)> saveToTempFile(KdbxDatabase db) async {
  final dir = Directory.systemTemp.createTempSync('keepass_mobile_test');
  final file = File('${dir.path}/prova.kdbx')
    ..writeAsBytesSync(await db.save());
  final reopened = await KdbxDatabase.fromBytes(
    data: file.readAsBytesSync(),
    credentials: testCredentials(),
  );
  return (file, reopened);
}

Future<KdbxDatabase> reopenFile(File file) => KdbxDatabase.fromBytes(
  data: file.readAsBytesSync(),
  credentials: testCredentials(),
);

FileRef fileRefOf(File file) =>
    FileRef(uri: file.uri.toString(), name: file.uri.pathSegments.last);

/// Container con preferenze in memoria e, se indicato, la sessione aperta.
/// Con [checkExternalChanges] la sessione conosce l'impronta del file e i
/// salvataggi controllano le modifiche fatte altrove.
Future<ProviderContainer> newTestContainer({
  File? file,
  KdbxDatabase? database,
  List<Override> overrides = const [],
  bool checkExternalChanges = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer.test(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
  );
  if (file != null && database != null) {
    container
        .read(databaseSessionProvider.notifier)
        .open(
          DatabaseSession(
            file: fileRefOf(file),
            database: database,
            fileHash: checkExternalChanges
                ? fileHashOf(file.readAsBytesSync())
                : null,
          ),
        );
  }
  return container;
}

/// Appunti simulati: canale del plugin `secure_clipboard` e appunti di
/// sistema di Flutter (per simulare una copia fatta fuori dall'app).
class FakeClipboard {
  FakeClipboard(TestDefaultBinaryMessengerBinding binding) {
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SecureClipboard.channel, (call) async {
      switch (call.method) {
        case 'copy':
          final args = call.arguments as Map;
          text = args['text'] as String?;
          _ownCopy = text;
          clearAfter = Duration(milliseconds: args['clearAfterMs'] as int);
          return null;
        case 'clearOwnCopy':
          final ours = _ownCopy != null && text == _ownCopy;
          _ownCopy = null;
          if (ours) text = '';
          return ours;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          text = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return text == null ? null : {'text': text};
        case 'Clipboard.hasStrings':
          return {'value': text?.isNotEmpty ?? false};
      }
      return null;
    });
  }

  String? text;
  String? _ownCopy;

  /// Durata della pulizia chiesta al plugin con l'ultima copia.
  Duration? clearAfter;
}

/// Attende un risultato prodotto fuori dal tempo simulato (isolate, file).
Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 250 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

Uint8List bytesOf(File file) => file.readAsBytesSync();
