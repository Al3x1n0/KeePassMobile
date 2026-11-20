// Simula una modifica fatta da un'altra app (prove di sincronizzazione sul
// telefono): apre il database con la password, aggiunge una voce e salva.
//
//   fvm dart run tool/device_test/kpm_external_edit.dart <in> <out> <password> <titolo>
import 'dart:io';

import 'package:kpasslib/kpasslib.dart';

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    stderr.writeln('uso: <in> <out> <password> <titolo>');
    exit(64);
  }
  final [input, output, secret, title] = args;
  final db = await KdbxDatabase.fromBytes(
    data: File(input).readAsBytesSync(),
    credentials: KdbxCredentials(password: ProtectedData.fromString(secret)),
  );
  db.createEntry(parent: db.root).fields['Title'] = KdbxTextField.fromText(
    text: title,
  );
  File(output).writeAsBytesSync(await db.save());
  stdout.writeln('voci: ${db.root.allEntries.length}');
}
