import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/search/search_view_model.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  late KdbxDatabase db;

  setUp(() {
    db = newTestDatabase();
    final bank = db.createGroup(parent: db.root, name: 'Banca');
    final hidden = db.createGroup(parent: db.root, name: 'Nascosto')
      ..isSearchingEnabled = false;
    final hiddenChild = db.createGroup(parent: hidden, name: 'Figlio');
    addTestEntry(db, bank, {
      EntryFields.title: 'Conto Corrente',
      EntryFields.userName: 'mario',
      EntryFields.password: 'segretissima',
      EntryFields.url: 'https://banca.example',
      EntryFields.notes: 'filiale centro',
      'IBAN': 'IT60X0542811101000000123456',
    });
    addTestEntry(db, db.root, {
      EntryFields.title: 'Email',
      'Codice': 'zeta',
    }).tags = [
      'lavoro',
    ];
    addTestEntry(db, hidden, {EntryFields.title: 'Conto nascosto'});
    addTestEntry(db, hiddenChild, {EntryFields.title: 'Conto figlio'});
  });

  List<String> titles(String query) =>
      searchEntries(db, query).map((r) => entryTitle(r.entry)).toList();

  test('cerca in titolo, nome utente, URL, note, altri campi e tag', () {
    expect(titles('corrente'), ['Conto Corrente']);
    expect(titles('mario'), ['Conto Corrente']);
    expect(titles('banca.example'), ['Conto Corrente']);
    expect(titles('filiale'), ['Conto Corrente']);
    expect(titles('IT60X'), ['Conto Corrente']);
    expect(titles('zeta'), ['Email']);
    expect(titles('lavoro'), ['Email']);
  });

  test('non cerca nella password', () {
    expect(titles('segretissima'), isEmpty);
  });

  test('senza distinzione tra maiuscole e minuscole', () {
    expect(titles('CONTO corrente'), ['Conto Corrente']);
  });

  test('tutte le parole devono comparire, anche in campi diversi', () {
    expect(titles('mario filiale'), ['Conto Corrente']);
    expect(titles('mario lavoro'), isEmpty);
  });

  test('esclude i gruppi con ricerca disattivata e i loro sottogruppi', () {
    expect(titles('conto'), ['Conto Corrente']);
  });

  test('esclude il cestino', () {
    db.remove(db.root.allEntries.firstWhere((e) => entryTitle(e) == 'Email'));
    expect(titles('email'), isEmpty);
  });

  test('ricerca vuota: nessun risultato', () {
    expect(titles('   '), isEmpty);
  });

  test('riporta il gruppo della voce', () {
    expect(searchEntries(db, 'corrente').single.groupName, 'Banca');
  });
  test(
    'riporta il percorso completo escludendo la radice, come GetFullPath',
    () {
      final bank = db.root.groups.firstWhere((group) => group.name == 'Banca');
      final child = db.createGroup(parent: bank, name: 'Carte');
      addTestEntry(db, child, {EntryFields.title: 'Carta'});
      final result = searchEntries(db, 'Carta').single;
      expect(result.groupName, 'Carte');
      expect(result.groupPath, 'Banca.Carte');
      expect(searchEntries(db, 'Email').single.groupPath, db.root.name);
    },
  );
  test(
    'i filtri selezionano i campi, inclusa la password solo su richiesta',
    () {
      const onlyPassword = SearchOptions(
        title: false,
        userName: false,
        url: false,
        notes: false,
        other: false,
        tags: false,
        password: true,
      );
      expect(
        searchEntries(db, 'segretissima', options: onlyPassword),
        hasLength(1),
      );
      expect(searchEntries(db, 'corrente', options: onlyPassword), isEmpty);
      const groupOnly = SearchOptions(
        title: false,
        userName: false,
        url: false,
        notes: false,
        other: false,
        tags: false,
        group: true,
      );
      expect(searchEntries(db, 'banca', options: groupOnly), hasLength(1));
    },
  );

  test('maiuscole e voci scadute sono filtrate solo su richiesta', () {
    final entry = db.root.allEntries.firstWhere(
      (e) => entryTitle(e) == 'Email',
    );
    entry.times.expires = true;
    entry.times.expiry = KdbxTime(DateTime.utc(2000));
    expect(
      searchEntries(
        db,
        'email',
        options: const SearchOptions(caseSensitive: true),
      ),
      isEmpty,
    );
    expect(
      searchEntries(
        db,
        'Email',
        options: const SearchOptions(excludeExpired: true),
      ),
      isEmpty,
    );
    expect(searchEntries(db, 'Email'), hasLength(1));
  });

  test('ricerca frasi e termini esclusi come SplitSearchTerms', () {
    expect(titles('"conto corrente"'), ['Conto Corrente']);
    expect(titles('"conto mario"'), isEmpty);
    expect(titles('conto -mario'), isEmpty);
    expect(titles('conto -lavoro'), ['Conto Corrente']);
  });
  test('regex seleziona i campi e rispetta maiuscole e errori', () async {
    final search = RegexSearch();
    expect(
      (await search.run(
        db,
        r'^Conto.*ente$',
        const SearchOptions(),
      )).map((r) => entryTitle(r.entry)),
      ['Conto Corrente'],
    );
    expect(
      await search.run(db, r'^conto', const SearchOptions(caseSensitive: true)),
      isEmpty,
    );
    await expectLater(
      search.run(db, '[', const SearchOptions()),
      throwsFormatException,
    );
    search.cancel();
  });
}
