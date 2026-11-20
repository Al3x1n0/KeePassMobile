import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/field_references.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  late KdbxDatabase db;
  late KdbxEntry source, target;
  setUp(() {
    db = newTestDatabase();
    target = addTestEntry(
      db,
      db.root,
      {
        EntryFields.title: 'Destinazione',
        EntryFields.userName: 'demo',
        EntryFields.password: 'segreto sintetico',
        'custom': 'dato',
      },
      protectedKeys: {EntryFields.password},
    );
    source = addTestEntry(db, db.root, {EntryFields.title: 'Sorgente'});
  });
  ResolvedField resolve(String value) {
    source.fields[EntryFields.notes] = PlainTextField(value);
    return resolveEntryField(db, source, EntryFields.notes);
  }

  test('campi standard, custom e UUID, senza modificare il testo salvato', () {
    source.fields['custom'] = PlainTextField('{TITLE}');
    expect(resolve('{S:custom}/{uuid}').text, 'Sorgente/${itemIdOf(source)}');
    expect(source.fields['custom']!.text, '{TITLE}');
    expect(source.fields[EntryFields.notes]!.text, '{S:custom}/{uuid}');
  });
  test('GROUP e GROUPPATH seguono il gruppo della voce risolta', () {
    // SprEngine: GetFullPath esclude la radice tranne per la radice stessa.
    final bank = db.createGroup(parent: db.root, name: 'Banca');
    final cards = db.createGroup(parent: bank, name: 'Carte');
    final nested = addTestEntry(db, cards, {
      EntryFields.title: 'Carta',
      EntryFields.userName: '{group}/{grouppath}',
    });
    expect(
      resolve('{GROUP}/{GROUPPATH}').text,
      '${db.root.name}/${db.root.name}',
    );
    expect(resolve('{REF:U@I:${itemIdOf(nested)}}').text, 'Carte/Banca.Carte');
    expect(nested.fields[EntryFields.userName]!.text, '{group}/{grouppath}');
  });
  test('segnaposto temporali usano lo stesso istante locale e UTC', () {
    // SprEngine: DT_SIMPLE e i singoli componenti sono a larghezza fissa.
    final now = DateTime.utc(2024, 2, 3, 4, 5, 6);
    source.fields[EntryFields.notes] = PlainTextField(
      '{DT_UTC_YEAR}-{DT_UTC_MONTH}-{DT_UTC_DAY} '
      '{DT_UTC_HOUR}:{DT_UTC_MINUTE}:{DT_UTC_SECOND} '
      '{dt_utc_simple} {DT_SIMPLE} {DT_UNKNOWN}',
    );
    final result = resolveEntryField(db, source, EntryFields.notes, now: now);
    final local = now.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final localSimple =
        '${local.year.toString().padLeft(4, '0')}'
        '${two(local.month)}${two(local.day)}${two(local.hour)}'
        '${two(local.minute)}${two(local.second)}';
    expect(
      result.text,
      '2024-02-03 04:05:06 20240203040506 $localSimple {DT_UNKNOWN}',
    );
    expect(result.protected, isFalse);
  });
  test('commenti rimossi prima di risolvere i segnaposto', () {
    // SprEngine.RemoveComments: delimitatori incompleti restano letterali.
    expect(resolve('prima{C:nota}dopo{C:altra}').text, 'primadopo');
    expect(resolve('{C:{PASSWORD}}').text, '}');
    expect(resolve('{C:senza chiusura').text, '{C:senza chiusura');
    expect(resolve('{c:minuscolo}').text, '{c:minuscolo}');
    expect(
      resolve(List.filled(257, '{C:x}').join()).issue,
      FieldReferenceIssue.limit,
    );
  });
  test('URL:RMVSCM rimuove lo schema e propaga protezione e cicli', () {
    // UrlUtil.RemoveScheme mantiene una barra singola e gli URL senza schema.
    source.fields[EntryFields.url] = PlainTextField('https://example.org/a');
    expect(resolve('{url:rmvscm}').text, 'example.org/a');
    source.fields[EntryFields.url] = PlainTextField('file:/tmp/file');
    expect(resolve('{URL:RMVSCM}').text, '/tmp/file');
    source.fields[EntryFields.url] = PlainTextField('example.org');
    expect(resolve('{URL:RMVSCM}').text, 'example.org');
    source.fields[EntryFields.url] = KdbxTextField.fromText(
      text: 'https://example.org',
      protected: true,
    );
    expect(resolve('{URL:RMVSCM}').protected, isTrue);
    source.fields[EntryFields.url] = PlainTextField('{URL:RMVSCM}');
    expect(resolve('{URL:RMVSCM}').issue, FieldReferenceIssue.cycle);
  });
  test('componenti URL passivi mantengono protezione e URL non validi', () {
    source.fields[EntryFields.url] = PlainTextField(
      'https://Example.org:8443/a%20b?q=x#frag',
    );
    const parts = '{URL:SCM}|{URL:HOST}|{URL:PORT}|{URL:PATH}|{URL:QUERY}';
    expect(resolve(parts).text, 'https|example.org|8443|/a%20b|?q=x');
    source.fields[EntryFields.url] = PlainTextField('https://example.org');
    expect(resolve(parts).text, 'https|example.org|443|/|');
    source.fields[EntryFields.url] = KdbxTextField.fromText(
      text: 'invalid',
      protected: true,
    );
    expect(resolve(parts).text, parts);
    expect(resolve(parts).protected, isTrue);
    source.fields[EntryFields.url] = PlainTextField('{URL:HOST}');
    expect(resolve(parts).issue, FieldReferenceIssue.cycle);
  });
  test(
    'REF compatibile: UUID e ricerca case insensitive sul valore grezzo',
    () {
      expect(
        resolve('{REF:U@I:${itemIdOf(target).toUpperCase()}}').text,
        'demo',
      );
      expect(resolve('{ref:U@T:destinazione}').text, 'demo');
      expect(resolve('{REF:I@O:dato}').text, itemIdOf(target));
    },
  );
  test('propaga protezione di password e campi custom su più passaggi', () {
    source.fields['custom'] = PlainTextField('{REF:P@T:Destinazione}');
    final result = resolve('prefisso {S:custom}');
    expect(result.text, 'prefisso segreto sintetico');
    expect(result.protected, isTrue);
    expect(resolve('{REF:T@P:segreto}').protected, isTrue);
  });
  test('cicli locali e fra voci restituiscono errore senza testo parziale', () {
    expect(resolve('prefisso {NOTES}').issue, FieldReferenceIssue.cycle);
    target.fields[EntryFields.userName] = PlainTextField('{REF:N@T:Sorgente}');
    expect(resolve('{REF:U@T:Destinazione}').issue, FieldReferenceIssue.cycle);
    expect(resolve('{REF:U@T:Destinazione}').text, isEmpty);
  });
  test('mancante e malformato non si copiano come valori risolti', () {
    expect(resolve('{S:assente}').issue, FieldReferenceIssue.missing);
    expect(resolve('{REF:P@T:assente}').issue, FieldReferenceIssue.missing);
    expect(resolve('{REF:bad}').issue, FieldReferenceIssue.malformed);
    expect(resolve('{REF:P@T:').issue, FieldReferenceIssue.malformed);
  });
  test('limiti di ricorsione, espansioni e dimensione', () {
    for (var i = 0; i < 20; i++) {
      source.fields['f$i'] = PlainTextField('{S:f${i + 1}}');
    }
    expect(resolve('{S:f0}').issue, FieldReferenceIssue.limit);
    expect(
      resolve(List.filled(257, '{TITLE}').join()).issue,
      FieldReferenceIssue.limit,
    );
    expect(resolve('x' * 65537).issue, FieldReferenceIssue.limit);
  });
  test('placeholder attivi non eseguiti; nessuna ricerca nel cestino', () {
    const raw = '{ENV:HOME} {CMD:qualcosa} {NEWPASSWORD}';
    expect(resolve(raw).text, raw);
    db.remove(target);
    expect(
      resolve('{REF:P@T:Destinazione}').issue,
      FieldReferenceIssue.missing,
    );
  });
  test('riferimenti annidati risolti nel contesto della voce destinazione', () {
    target.fields[EntryFields.userName] = PlainTextField('{TITLE}/{S:custom}');
    expect(resolve('{REF:U@T:Destinazione}').text, 'Destinazione/dato');
  });
}
