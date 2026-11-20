import 'dart:convert';

import 'package:document_access/document_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Scelta reale con il selettore di sistema (Storage Access Framework) e
/// scrittura nel documento `content://` scelto.
///
/// Richiede che il file `kpm_picker_test.kdbx` con il contenuto
/// [initialContent] sia in Download e che qualcuno lo tocchi nel selettore
/// (a mano o con adb). Per questo parte solo con
/// `--dart-define=KPM_PICKER_TEST=true`.
const initialContent = 'contenuto iniziale piuttosto lungo';
const _enabled = bool.fromEnvironment('KPM_PICKER_TEST');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const documents = DocumentAccess();

  testWidgets(
    'Android: selettore di sistema, lettura e scrittura nel documento originale',
    (tester) async {
      final picked = await documents.pick();
      if (picked == null) fail('Nessun documento scelto');

      expect(picked.uri, startsWith('content://'));
      expect(picked.name, 'kpm_picker_test.kdbx');
      expect(utf8.decode(picked.bytes), initialContent);
      // Permesso persistente ottenuto (flutter test disinstalla l'app alla
      // fine, quindi la sopravvivenza al riavvio va provata a mano).
      expect(picked.persistent, isTrue);

      await documents.write(picked.uri, utf8.encode('corto'));

      expect(utf8.decode((await documents.read(picked.uri)).bytes), 'corto');
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
