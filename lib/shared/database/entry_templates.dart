import 'package:kpasslib/kpasslib.dart';

import 'database_session.dart';
import 'kdbx_items.dart';

export 'kdbx_items.dart' show existingTemplatesGroup, isInTemplatesGroup;

const structuredTemplateMarker = '_etm_template';
const structuredTemplateReference = '_etm_template_uuid';

/// Etichette localizzate da memorizzare nei modelli predefiniti.
class BuiltInTemplateLabels {
  const BuiltInTemplateLabels({
    required this.group,
    required this.idCard,
    required this.wlan,
    required this.note,
    required this.creditCard,
    required this.membership,
    required this.number,
    required this.name,
    required this.place,
    required this.issueDate,
    required this.holder,
  });
  final String group, idCard, wlan, note, creditCard, membership;
  final String number, name, place, issueDate, holder;
}

/// Crea i modelli mancanti senza sovrascrivere voci o UUID esistenti.
DatabaseEdit addBuiltInTemplatesEdit(BuiltInTemplateLabels labels) =>
    (database) {
      final definitions = <(String, String, KdbxIcon, List<(String, String)>)>[
        (
          'A7B525BD0CECC84EB9F0CEDC0B49B5B8',
          labels.idCard,
          KdbxIcon.identity,
          [
            (labels.number, 'Inline'),
            (labels.name, 'Inline'),
            (labels.place, 'Inline'),
            (labels.issueDate, 'Inline'),
            ('@exp_date', 'Date Time'),
          ],
        ),
        (
          '46B56A7E90407545B646E8DC488A5FA2',
          labels.wlan,
          KdbxIcon.irCommunication,
          [('SSID', 'Inline'), (EntryFields.password, 'Protected Inline')],
        ),
        (
          '10F8C25C26AE9B49A47FDA7CDACACEE2',
          labels.note,
          KdbxIcon.notepad,
          [(EntryFields.notes, 'Inline')],
        ),
        (
          '49DD48DBFF149445B3392CE90EA75309',
          labels.creditCard,
          KdbxIcon.homebanking,
          [
            (labels.number, 'Inline'),
            ('CVV', 'Protected Inline'),
            ('PIN', 'Protected Inline'),
            (labels.holder, 'Inline'),
            ('@exp_date', 'Date Time'),
          ],
        ),
        (
          'DD5C627BC66C28498FDEC70740D29168',
          labels.membership,
          KdbxIcon.userKey,
          [
            (labels.number, 'Inline'),
            (EntryFields.url, 'Inline'),
            ('@exp_date', 'Date Time'),
          ],
        ),
      ];
      final existing = {
        itemIdOf(database.root),
        ...database.root.allItems.map(itemIdOf),
      };
      final entries = database.root.allEntries.toList();
      final missing = definitions
          .where(
            (definition) =>
                !existing.contains(definition.$1.toLowerCase()) &&
                !entries.any(
                  (entry) =>
                      entryField(entry, 'KP2A_TemplateId').toUpperCase() ==
                      definition.$1,
                ),
          )
          .toList();
      if (missing.isEmpty) return;
      var group = existingTemplatesGroup(database);
      if (group == null) {
        group = database.createGroup(parent: database.root, name: labels.group);
        database.meta.entryTemplatesGroup = group.uuid;
      }
      for (final (hex, title, icon, fields) in missing) {
        final entry = database.createEntry(parent: group, icon: icon);
        entry.uuid = KdbxUuid.fromBytes([
          for (var i = 0; i < hex.length; i += 2)
            int.parse(hex.substring(i, i + 2), radix: 16),
        ]);
        entry.fields[EntryFields.title] = PlainTextField(title);
        entry.fields[structuredTemplateMarker] = PlainTextField('1');
        for (var i = 0; i < fields.length; i++) {
          final (key, type) = fields[i];
          entry.fields['_etm_position_$key'] = PlainTextField('$i');
          entry.fields['_etm_title_$key'] = PlainTextField(key);
          entry.fields['_etm_type_$key'] = PlainTextField(type);
        }
      }
    };

bool isStructuredTemplate(KdbxEntry entry) =>
    entry.fields.containsKey(structuredTemplateMarker);

/// Restituisce il modello strutturato collegato, se ancora presente.
KdbxEntry? structuredTemplateOf(KdbxDatabase? database, KdbxEntry entry) {
  if (database == null) return null;
  final id = entry.fields[structuredTemplateReference]?.text.toLowerCase();
  if (id == null || !RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) return null;
  final template = findEntry(database, id);
  return template != null && isStructuredTemplate(template) ? template : null;
}

int compareTemplateFields(KdbxEntry? template, String a, String b) {
  int position(String key) =>
      int.tryParse(template?.fields['_etm_position_$key']?.text ?? '') ??
      0x7fffffff;
  final byPosition = position(a).compareTo(position(b));
  return byPosition != 0
      ? byPosition
      : a.toLowerCase().compareTo(b.toLowerCase());
}

List<KdbxEntry> entryTemplates(KdbxDatabase database) {
  final group = existingTemplatesGroup(database);
  if (group == null) return const [];
  final result = [...group.entries];
  result.sort(
    (a, b) =>
        entryTitle(a).toLowerCase().compareTo(entryTitle(b).toLowerCase()),
  );
  return result;
}
