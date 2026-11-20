import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/entry/entry_view_model.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view_model.dart';
import 'package:keepass_mobile/shared/database/entry_templates.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  test(
    'installa modelli predefiniti una sola volta e conserva la compatibilità',
    () async {
      final db = newTestDatabase();
      const labels = BuiltInTemplateLabels(
        group: 'Templates',
        idCard: 'ID card',
        wlan: 'Wireless LAN',
        note: 'Secure note',
        creditCard: 'Credit card',
        membership: 'Membership',
        number: 'Number',
        name: 'Name',
        place: 'Place of issue',
        issueDate: 'Date of issue',
        holder: 'Card holder',
      );
      addBuiltInTemplatesEdit(labels)(db);
      final templates = entryTemplates(db);
      expect(templates, hasLength(5));
      final card = templates.singleWhere(
        (entry) => entryTitle(entry) == 'Credit card',
      );
      expect(itemIdOf(card), '49dd48dbff149445b3392ce90ea75309');
      expect(card.fields['_etm_type_CVV']?.text, 'Protected Inline');
      final draft = draftFromStructuredTemplate(card);
      expect(
        draft.custom.singleWhere((field) => field.key == 'CVV').protected,
        isTrue,
      );
      addBuiltInTemplatesEdit(labels)(db);
      final reopened = (await saveToTempFile(db)).$2;
      expect(entryTemplates(reopened), hasLength(5));
      expect(reopened.meta.entryTemplatesGroup, db.meta.entryTemplatesGroup);
    },
  );
  test(
    'crea i campi dichiarati e conserva il collegamento al modello',
    () async {
      final db = newTestDatabase();
      final group = db.createGroup(parent: db.root, name: 'Templates');
      db.meta.entryTemplatesGroup = group.uuid;
      final template = addTestEntry(db, group, {
        EntryFields.title: 'Sample template',
        '_etm_template': '1',
        '_etm_title_UserName': 'UserName',
        '_etm_type_UserName': 'Inline',
        EntryFields.userName: 'sample-user',
        '_etm_title_PIN': 'PIN',
        '_etm_type_PIN': 'Protected Inline',
        '_etm_position_PIN': '1',
        'PIN': '1234',
        '_etm_title_ignored': 'ignored',
        '_etm_type_ignored': 'Divider',
        '_etm_title_@override': '@override',
      });
      template.overrideUrl = 'https://example.org/override';
      final draft = draftFromStructuredTemplate(template);
      final id = KdbxUuid.random();
      createFromTemplateEdit(db.root.uuid, id, itemIdOf(template), draft)(db);
      final entry = db.root.entries.single;
      expect(entry.fields[EntryFields.userName]?.text, 'sample-user');
      expect(entry.overrideUrl, 'https://example.org/override');
      expect(entry.fields['PIN'], isA<ProtectedTextField>());
      expect(entry.fields['ignored'], isNull);
      expect(entry.fields[structuredTemplateMarker], isNull);
      expect(
        entry.fields[structuredTemplateReference]?.text,
        itemIdOf(template).toUpperCase(),
      );
      expect(structuredTemplateOf(db, entry), template);
      expect(
        visibleFields(entry, database: db).map((e) => e.key),
        isNot(contains(structuredTemplateReference)),
      );
      final reopened = (await saveToTempFile(db)).$2;
      final restored = reopened.root.entries.single;
      expect(structuredTemplateOf(reopened, restored), isNotNull);
      expect(restored.fields['PIN'], isA<ProtectedTextField>());
      expect(restored.overrideUrl, 'https://example.org/override');
    },
  );

  test(
    'un riferimento non valido rimane visibile e non viene interpretato',
    () {
      final db = newTestDatabase();
      final entry = addTestEntry(db, db.root, {
        structuredTemplateReference: 'sample',
      });
      expect(structuredTemplateOf(db, entry), isNull);
      expect(
        visibleFields(entry, database: db).map((e) => e.key),
        contains(structuredTemplateReference),
      );
    },
  );
}
