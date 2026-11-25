import 'package:kpasslib/kpasslib.dart';

import '../../shared/database/entry_templates.dart';
import '../../shared/database/kdbx_items.dart';
import '../totp/totp.dart';
import 'password_strength.dart';

class DuplicatePasswordGroup {
  DuplicatePasswordGroup(Iterable<String> ids)
    : entryIds = List.unmodifiable(ids);
  final List<String> entryIds;
}

class WeakPasswordEntry {
  const WeakPasswordEntry(this.entryId, this.strength);
  final String entryId;
  final PasswordStrength strength;
}

class ProtectedFieldNotice {
  const ProtectedFieldNotice(
    this.entryId,
    this.fieldName,
    this.strength,
    this.reused,
  );
  final String entryId;
  final String fieldName;
  final PasswordStrength strength;
  final bool reused;
}

/// Metadata only: no plaintext values or database objects are retained.
class PasswordCheckReport {
  PasswordCheckReport({
    required this.analyzedPasswordEntriesCount,
    required Iterable<DuplicatePasswordGroup> duplicateGroups,
    required Iterable<WeakPasswordEntry> weakEntries,
    required Iterable<ProtectedFieldNotice> protectedFieldNotices,
  }) : duplicateGroups = List.unmodifiable(duplicateGroups),
       weakEntries = List.unmodifiable(weakEntries),
       protectedFieldNotices = List.unmodifiable(protectedFieldNotices);
  final int analyzedPasswordEntriesCount;
  final List<DuplicatePasswordGroup> duplicateGroups;
  final List<WeakPasswordEntry> weakEntries;
  final List<ProtectedFieldNotice> protectedFieldNotices;
}

PasswordCheckReport auditPasswords(KdbxDatabase database) {
  final templates = entryTemplates(database).toSet();
  final passwords = <String, List<String>>{};
  final allValues = <String, int>{};
  final secondary =
      <({String id, String key, String value, PasswordStrength strength})>[];
  final weak = <WeakPasswordEntry>[];
  final titles = <String, String>{};
  var count = 0;
  final reference = RegExp(r'\{(?:REF|S):[^}]*\}', caseSensitive: false);
  for (final entry in database.root.allEntries) {
    if (isInRecycleBin(database, entry) ||
        templates.contains(entry) ||
        isInTemplatesGroup(database, entry) ||
        isStructuredTemplate(entry)) {
      continue;
    }
    final id = itemIdOf(entry);
    titles[id] = entryTitle(entry).toLowerCase();
    for (final field in entry.fields.entries) {
      final key = field.key;
      if (isTotpField(key) || key.toLowerCase().startsWith('_etm_')) continue;
      final main = key == EntryFields.password;
      if (!main && field.value is! ProtectedTextField) continue;
      final value = field.value.text;
      if (value.isEmpty || reference.hasMatch(value)) continue;
      allValues.update(value, (n) => n + 1, ifAbsent: () => 1);
      final strength = evaluatePasswordStrength(value);
      if (main) {
        count++;
        passwords.putIfAbsent(value, () => []).add(id);
        if (strength.isWeak) weak.add(WeakPasswordEntry(id, strength));
      } else {
        secondary.add((id: id, key: key, value: value, strength: strength));
      }
    }
  }
  int byTitle(String a, String b) {
    final result = titles[a]!.compareTo(titles[b]!);
    return result != 0 ? result : a.compareTo(b);
  }

  final groups = [
    for (final ids in passwords.values)
      if (ids.length > 1) DuplicatePasswordGroup([...ids]..sort(byTitle)),
  ];
  groups.sort((a, b) {
    final n = b.entryIds.length.compareTo(a.entryIds.length);
    return n != 0 ? n : byTitle(a.entryIds.first, b.entryIds.first);
  });
  weak.sort((a, b) {
    final n = a.strength.level.index.compareTo(b.strength.level.index);
    return n != 0 ? n : byTitle(a.entryId, b.entryId);
  });
  final notices = [
    for (final field in secondary)
      if (field.strength.isWeak || allValues[field.value]! > 1)
        ProtectedFieldNotice(
          field.id,
          field.key,
          field.strength,
          allValues[field.value]! > 1,
        ),
  ];
  notices.sort((a, b) {
    final n = byTitle(a.entryId, b.entryId);
    return n != 0
        ? n
        : a.fieldName.toLowerCase().compareTo(b.fieldName.toLowerCase());
  });
  return PasswordCheckReport(
    analyzedPasswordEntriesCount: count,
    duplicateGroups: groups,
    weakEntries: weak,
    protectedFieldNotices: notices,
  );
}
