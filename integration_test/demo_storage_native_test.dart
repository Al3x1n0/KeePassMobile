import 'dart:typed_data';

import 'package:document_access/document_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Verifica distruttiva riservata a un'installazione dedicata e pulita.
///
/// Eseguire solo su emulatore o simulatore con `KPM_DEMO_STORAGE_TEST=true`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo privata: copia idempotente e rimozione definitiva', (
    tester,
  ) async {
    expect(
      const bool.fromEnvironment('KPM_DEMO_STORAGE_TEST'),
      isTrue,
      reason:
          'Richiede un’installazione isolata su emulatore o simulatore e '
          '--dart-define=KPM_DEMO_STORAGE_TEST=true.',
    );
    const documents = DocumentAccess();
    var existingDemo = false;
    try {
      await documents.read(DocumentAccess.demoDatabaseUri);
      existingDemo = true;
    } on DocumentUnavailableException {
      // Il test non deve modificare una copia già presente nell'installazione.
    }
    expect(existingDemo, isFalse, reason: 'La demo deve essere assente.');
    final original = Uint8List.fromList([1, 2, 3]);
    final changed = Uint8List.fromList([4, 5]);

    final installed = await Future.wait([
      documents.ensureDemoDatabase(original),
      documents.ensureDemoDatabase(original),
    ]);
    expect(installed, everyElement(isTrue));
    expect(
      (await documents.read(DocumentAccess.demoDatabaseUri)).bytes,
      original,
    );

    await documents.write(DocumentAccess.demoDatabaseUri, changed);
    expect(await documents.ensureDemoDatabase(original), isTrue);
    expect(
      (await documents.read(DocumentAccess.demoDatabaseUri)).bytes,
      changed,
    );

    expect(await documents.isDemoDatabaseRemoved(), isFalse);
    expect(await documents.retainDemoDatabase(), isTrue);
    expect(await documents.retainDemoDatabase(), isTrue);

    await documents.deleteDemoDatabase(keepFile: true);
    await documents.deleteDemoDatabase();
    expect(await documents.isDemoDatabaseRemoved(), isTrue);
    expect(await documents.retainDemoDatabase(), isFalse);
    expect(await documents.ensureDemoDatabase(original), isFalse);
    expect(
      (await documents.read(DocumentAccess.demoDatabaseUri)).bytes,
      changed,
    );
    await documents.write(DocumentAccess.demoDatabaseUri, original);

    await documents.releaseDemoDatabase();
    expect(
      (await documents.read(DocumentAccess.demoDatabaseUri)).bytes,
      original,
    );
    await documents.releaseDemoDatabase();
    await expectLater(
      documents.read(DocumentAccess.demoDatabaseUri),
      throwsA(isA<DocumentUnavailableException>()),
    );
    expect(await documents.ensureDemoDatabase(original), isFalse);
    expect(await documents.retainDemoDatabase(), isFalse);
    await expectLater(
      documents.write(DocumentAccess.demoDatabaseUri, changed),
      throwsA(isA<DocumentUnavailableException>()),
    );
  });
}
