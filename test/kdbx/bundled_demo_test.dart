import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/totp/totp.dart';
import 'package:keepass_mobile/shared/database/field_references.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('il database demo incluso espone esempi utilizzabili', () async {
    final asset = await rootBundle.load('assets/demo/Rifugio-Aurora.kdbx');
    final db = await KdbxDatabase.fromBytes(
      data: Uint8List.sublistView(asset),
      credentials: KdbxCredentials(
        password: ProtectedData.fromString('demo1234'),
      ),
    );
    KdbxEntry named(String title) =>
        db.root.allEntries.singleWhere((e) => entryTitle(e) == title);

    final login = named('Portale Aurora');
    final linked = named('Calendario camere');
    for (final key in [EntryFields.userName, EntryFields.password]) {
      final field = resolveEntryField(db, linked, key);
      expect(field.valid, isTrue);
      expect(field.text, entryField(login, key));
      expect(field.protected, key == EntryFields.password);
    }
    final config = parseTotp(login.fields.map((k, v) => MapEntry(k, v.text)));
    expect(config!.codeAt(DateTime.utc(1970)), '282760');

    final icon = db.meta.customIcons[login.customIcon]!;
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(icon.data));
    addTearDown(codec.dispose);
    final frame = await codec.getNextFrame();
    addTearDown(frame.image.dispose);
    expect(frame.image.width, 32);
    final keys = named('Consegna chiavi');
    final attachment = db.binaries.getByRef(keys.binaries['inventario.txt']!)!;
    expect(utf8.decode(attachment.data), contains('2 chiavi blu'));
    expect(keys.fields['PIN'], isA<ProtectedTextField>());
    expect(
      entryField(keys.history.single, EntryFields.notes),
      isNot(entryField(keys, EntryFields.notes)),
    );
    expect(isExpired(named('Pass stagionale'), DateTime.utc(2026)), isTrue);
    expect(named('Tessera rifugio').parent?.uuid, db.meta.entryTemplatesGroup);
    expect(named('Bozza da ripristinare').parent?.uuid, db.meta.recycleBinUuid);
  });
}
