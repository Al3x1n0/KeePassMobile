import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/autofill/autofill_matcher.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  late KdbxDatabase db;

  KdbxEntry add(String title, Map<String, String> fields, {KdbxGroup? group}) =>
      addTestEntry(db, group ?? db.root, {EntryFields.title: title, ...fields});

  List<String> matches(String query) =>
      autofillMatches(db, query).map(entryTitle).toList();

  setUp(() => db = newTestDatabase());

  group('hostOf', () {
    test('senza schema, utente, porta e percorso, in minuscolo', () {
      expect(
        hostOf('https://bob@Accounts.Example.com:8443/login?x=1#y'),
        'accounts.example.com',
      );
      expect(hostOf('example.org'), 'example.org');
      expect(hostOf('mailto:bob@example.com'), 'example.com');
      expect(hostOf('androidapp://com.example.app'), 'com.example.app');
      expect(hostOf('  '), '');
    });
  });

  test('URL uguale alla richiesta: solo quella voce', () {
    add('Sito', {EntryFields.url: 'https://www.example.org/'});
    add('Dominio', {EntryFields.url: 'https://example.org'});

    expect(matches('www.example.org'), ['Sito']);
  });

  test(
    'host: la voce del dominio vale per i sottodomini, non il contrario',
    () {
      add('Login', {EntryFields.url: 'https://accounts.example.com/login'});
      add('Dominio', {EntryFields.url: 'https://example.com'});

      expect(matches('accounts.example.com'), ['Dominio', 'Login']);
      expect(matches('example.com'), ['Dominio']);
    },
  );

  test('www. della voce ignorato solo se non c\'è altro', () {
    add('Negozio', {EntryFields.url: 'https://www.negozio.it'});

    expect(matches('login.negozio.it'), ['Negozio']);
  });

  test('un dominio che contiene quello della voce non basta', () {
    add('Banca', {EntryFields.url: 'https://banca.example'});

    expect(matches('banca.example.evil.net'), isEmpty);
  });

  test('app: campo AndroidApp di Keepass2Android prima del testo', () {
    add('App', {'AndroidApp1': 'androidapp://com.example.app'});
    add('Nota', {EntryFields.notes: 'vedi com.example.app'});

    expect(matches('androidapp://com.example.app'), ['App']);
  });

  test('app senza campi associati: testo del pacchetto nelle voci', () {
    add('Nota', {EntryFields.notes: 'vedi com.example.app'});

    expect(matches('androidapp://com.example.app'), ['Nota']);
  });

  test('sito: campo KP2A_URL di Keepass2Android', () {
    add('Amazon', {'KP2A_URL_1': 'https://www.amazon.it'});

    expect(matches('www.amazon.it'), ['Amazon']);
  });

  test('esclusi cestino e gruppi con ricerca disattivata', () {
    final hidden = db.createGroup(parent: db.root, name: 'Nascosto')
      ..isSearchingEnabled = false;
    add('Nascosta', {EntryFields.url: 'https://example.net'}, group: hidden);
    add('Eliminata', {
      EntryFields.url: 'https://example.net',
    }, group: db.recycleBin);

    expect(matches('example.net'), isEmpty);
  });

  test('associazione: primo campo libero, AndroidApp o KP2A_URL_', () {
    final entry = add('App', {'AndroidApp1': 'androidapp://com.altra'});

    expect(nextAutofillField(entry, 'androidapp://com.example'), 'AndroidApp2');
    expect(nextAutofillField(entry, 'www.example.com'), 'KP2A_URL_1');
    expect(autofillFieldValue('www.example.com'), 'https://www.example.com');
    expect(
      autofillFieldValue('androidapp://com.example'),
      'androidapp://com.example',
    );
  });

  test('ricorda: campo aggiunto, versione precedente nella cronologia', () {
    final entry = add('Conto', {EntryFields.url: 'https://banca.example'});

    rememberAutofillEdit(entry.uuid, 'androidapp://com.banca')(db);

    expect(entry.fields['AndroidApp1']?.text, 'androidapp://com.banca');
    expect(entry.fields['AndroidApp1'], isNot(isA<ProtectedTextField>()));
    expect(entry.history, hasLength(1));
    expect(matches('androidapp://com.banca'), ['Conto']);
  });
}
