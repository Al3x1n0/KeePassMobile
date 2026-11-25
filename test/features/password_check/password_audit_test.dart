import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/password_check/password_audit.dart';
import 'package:keepass_mobile/features/password_check/password_check_view_model.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/entry_templates.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'duplicate e deboli indipendenti, ordinamento e report senza valori',
    () {
      final db = newTestDatabase();
      final z = addTestEntry(db, db.root, {
        'Title': 'Zeta',
        'Password': 'tiny',
      });
      final a = addTestEntry(db, db.root, {
        'Title': 'Alfa',
        'Password': 'tiny',
      });
      addTestEntry(db, db.root, {'Title': 'Buona', 'Password': 'vK9!tR4?mZ'});
      final report = auditPasswords(db);
      expect(report.analyzedPasswordEntriesCount, 3);
      expect(report.duplicateGroups.single.entryIds, [
        itemIdOf(a),
        itemIdOf(z),
      ]);
      expect(report.weakEntries.map((e) => e.entryId), [
        itemIdOf(a),
        itemIdOf(z),
      ]);
      expect(report.toString(), isNot(contains('tiny')));
      expect(report.duplicateGroups.single.toString(), isNot(contains('tiny')));
      expect(() => report.duplicateGroups.clear(), throwsUnsupportedError);
    },
  );

  test(
    'esclude cestino, modelli, vuoti, TOTP, marker e riferimenti grezzi',
    () {
      final db = newTestDatabase();
      final bin = db.createGroup(parent: db.root, name: 'Cestino');
      db.meta.recycleBinUuid = bin.uuid;
      final templates = db.createGroup(parent: db.root, name: 'Modelli');
      db.meta.entryTemplatesGroup = templates.uuid;
      for (final group in [bin, templates]) {
        addTestEntry(db, group, {'Title': 'Esclusa', 'Password': 'tiny'});
      }
      addTestEntry(db, db.root, {
        'Password': 'tiny',
        structuredTemplateMarker: '1',
      });
      for (final value in [
        '',
        '{REF:P@T:Alfa}',
        'prefix {ref:P@T:Alfa}',
        '{s:PIN}',
      ]) {
        addTestEntry(
          db,
          db.root,
          {'Password': value, 'PIN': value},
          protectedKeys: {'PIN'},
        );
      }
      addTestEntry(
        db,
        db.root,
        {'otp': 'tiny', '_etm_type_PIN': 'tiny'},
        protectedKeys: {'otp', '_etm_type_PIN'},
      );
      final report = auditPasswords(db);
      expect(report.analyzedPasswordEntriesCount, 0);
      expect(report.duplicateGroups, isEmpty);
      expect(report.weakEntries, isEmpty);
      expect(report.protectedFieldNotices, isEmpty);
      addTestEntry(db, db.root, {'Password': '{C:hi}'});
      expect(auditPasswords(db).analyzedPasswordEntriesCount, 1);
    },
  );

  test('campi secondari deboli e riutilizzo tra campi o con Password', () {
    final db = newTestDatabase();
    const strong = 'vK9!tR4?mZ';
    addTestEntry(
      db,
      db.root,
      {'Title': 'Alfa', 'Password': strong, 'PIN': '9876', 'Token': strong},
      protectedKeys: {'PIN', 'Token'},
    );
    addTestEntry(
      db,
      db.root,
      {'Title': 'Beta', 'CVV': '9876', 'Pubblico': '9876'},
      protectedKeys: {'CVV'},
    );
    final report = auditPasswords(db);
    expect(report.weakEntries, isEmpty);
    expect(report.duplicateGroups, isEmpty);
    expect(report.protectedFieldNotices.map((n) => n.fieldName), [
      'PIN',
      'Token',
      'CVV',
    ]);
    expect(report.protectedFieldNotices.every((n) => n.reused), isTrue);
    expect(report.protectedFieldNotices.first.strength.isWeak, isTrue);
    expect(report.protectedFieldNotices[1].strength.isWeak, isFalse);
  });

  test('ordina gruppi per occorrenze, poi titolo; forza per severità', () {
    final db = newTestDatabase();
    final ids = <String>[];
    for (final (title, value) in [
      ('Zeta', 'hvrnktps'),
      ('Alfa', 'hvrnktps'),
      ('Delta', 'tiny'),
      ('Gamma', 'tiny'),
      ('Omega', 'tiny'),
      ('Beta', 'short'),
      ('Eta', 'short'),
    ]) {
      ids.add(
        itemIdOf(
          addTestEntry(db, db.root, {'Title': title, 'Password': value}),
        ),
      );
    }
    final report = auditPasswords(db);
    expect(report.duplicateGroups.map((g) => g.entryIds), [
      [ids[2], ids[3], ids[4]],
      [ids[1], ids[0]],
      [ids[5], ids[6]],
    ]);
    expect(report.weakEntries.map((e) => e.entryId), [
      ids[5],
      ids[2],
      ids[6],
      ids[3],
      ids[4],
      ids[1],
      ids[0],
    ]);
  });

  test('confronto esatto distingue maiuscole e ignora campi non protetti', () {
    final db = newTestDatabase();
    addTestEntry(db, db.root, {
      'Password': 'vK9!tR4?mZ',
      'Visibile': 'vK9!tR4?mZ',
    });
    addTestEntry(
      db,
      db.root,
      {'Password': 'Vk9!tR4?mZ', 'Token': 'vK9!tR4?mZ!'},
      protectedKeys: {'Token'},
    );
    final report = auditPasswords(db);
    expect(report.duplicateGroups, isEmpty);
    expect(report.protectedFieldNotices, isEmpty);
  });

  test(
    'provider reattivo, nessuna scrittura preferenze e pulizia al blocco',
    () async {
      final container = await newTestContainer();
      const file = FileRef(uri: 'content://test/check', name: 'check.kdbx');
      final sessions = container.read(databaseSessionProvider.notifier);
      final sub = container.listen(passwordCheckReportProvider, (_, _) {});
      addTearDown(sub.close);
      final prefs = container.read(sharedPreferencesProvider);
      final before = prefs.getKeys();
      final db = newTestDatabase();
      addTestEntry(db, db.root, {'Password': 'tiny'});
      sessions.open(DatabaseSession(file: file, database: db));
      expect(
        container.read(passwordCheckReportProvider)!.weakEntries,
        hasLength(1),
      );
      sessions.open(DatabaseSession(file: file, database: newTestDatabase()));
      expect(container.read(passwordCheckReportProvider)!.weakEntries, isEmpty);
      sessions.lock();
      expect(container.read(passwordCheckReportProvider), isNull);
      expect(prefs.getKeys(), before);
    },
  );
}
