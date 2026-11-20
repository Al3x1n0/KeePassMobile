import 'dart:io';
import 'dart:typed_data';

import 'package:document_access/document_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keepass_mobile/shared/crypto/app_crypto_engine.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:kpasslib/kpasslib.dart';

/// Verifiche su emulatore Android e simulatore iOS del codice nativo:
/// plugin document_access (lettura, scrittura, errori) e Argon2 via FFI.
///
/// La scelta interattiva del documento (selettore di sistema, permesso
/// persistente, bookmark) richiede una prova manuale.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const documents = DocumentAccess();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('document_access'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('legge e riscrive un file nel codice nativo, troncandolo', (
    tester,
  ) async {
    final file = File('${dir.path}/prova.kdbx')
      ..writeAsBytesSync(List.generate(4096, (i) => i % 256));
    final uri = file.uri.toString();

    expect((await documents.read(uri)).bytes, file.readAsBytesSync());

    await documents.write(uri, Uint8List.fromList([1, 2, 3]));

    expect(file.readAsBytesSync(), [1, 2, 3]);
    expect((await documents.read(uri)).bytes, [1, 2, 3]);
  });

  testWidgets('file inesistente: DocumentUnavailableException', (tester) async {
    await expectLater(
      documents.read(File('${dir.path}/manca.kdbx').uri.toString()),
      throwsA(isA<DocumentUnavailableException>()),
    );
  });

  testWidgets('riferimento non valido: DocumentUnavailableException', (
    tester,
  ) async {
    await expectLater(
      documents.read('bookmark:non-base64!'),
      throwsA(isA<DocumentUnavailableException>()),
    );
  });

  testWidgets('release di un documento senza permesso: nessun errore', (
    tester,
  ) async {
    await documents.release(File('${dir.path}/x.kdbx').uri.toString());
  });

  testWidgets('Argon2 nativo: disponibile e tempo con i parametri di KP2A', (
    tester,
  ) async {
    final engine = AppCryptoEngine();
    expect(engine.useNativeArgon2, isTrue);

    // Parametri predefiniti di Keepass2Android: 64 MiB, 2 iterazioni, p = 2.
    final watch = Stopwatch()..start();
    final key = engine
        .createArgon2(
          type: Argon2Type.argon2d,
          parallelism: 2,
          memorySizeKB: 64 * 1024,
          iterations: 2,
          salt: List.filled(32, 1),
        )
        .convert(List.filled(32, 2));
    watch.stop();

    expect(key, hasLength(32));
    // ignore: avoid_print
    print('ARGON2_KP2A_MS=${watch.elapsedMilliseconds}');
  });

  testWidgets('apre in un isolate un database salvato con il plugin', (
    tester,
  ) async {
    final db = KdbxDatabase.create(
      credentials: KdbxCredentials(password: ProtectedData.fromString('pw')),
      name: 'prova',
    );
    db.createEntry(parent: db.root).fields['Title'] = KdbxTextField.fromText(
      text: 'voce',
    );
    final uri = File('${dir.path}/db.kdbx').uri.toString();
    await documents.write(uri, Uint8List.fromList(await db.save()));

    final reopened = await openDatabase(
      data: (await documents.read(uri)).bytes,
      password: 'pw',
    );

    expect(reopened.root.allEntries.single.fields['Title']?.text, 'voce');
  });
}
