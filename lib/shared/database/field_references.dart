import 'package:kpasslib/kpasslib.dart';

import 'kdbx_items.dart';

/// Errore senza nomi di campi, criteri di ricerca o valori sensibili.
enum FieldReferenceIssue { missing, cycle, limit, malformed }

final class FieldReferenceException implements Exception {
  const FieldReferenceException(this.issue);
  final FieldReferenceIssue issue;
}

/// Valore calcolato soltanto in memoria. La protezione si propaga attraverso
/// tutti i riferimenti, anche quando il campo che li contiene non è protetto.
class ResolvedField {
  const ResolvedField({
    required this.text,
    required this.protected,
    this.issue,
  });
  final String text;
  final bool protected;
  final FieldReferenceIssue? issue;
  bool get valid => issue == null;
}

/// Sottoinsieme passivo di SprEngine: campi standard, gruppo, S e REF. Nessun comando,
/// variabile d'ambiente, trasformazione o modifica del database viene eseguito.
/// Placeholder estranei al sottoinsieme restano letterali.
ResolvedField resolveEntryField(
  KdbxDatabase db,
  KdbxEntry entry,
  String key, {
  DateTime? now,
}) {
  try {
    return _Resolver(db, now ?? DateTime.now()).field(entry, key, 0);
  } on FieldReferenceException catch (error) {
    return ResolvedField(text: '', protected: true, issue: error.issue);
  }
}

/// Titolo adatto a schermate pubbliche: non mostra valori protetti o invalidi.
String visibleEntryTitle(KdbxDatabase? database, KdbxEntry entry) {
  if (database == null) {
    return entry.fields[EntryFields.title] is ProtectedTextField
        ? ''
        : entryTitle(entry);
  }
  final title = resolveEntryField(database, entry, EntryFields.title);
  return title.valid && !title.protected ? title.text : '';
}

class _Resolver {
  _Resolver(this.database, this.now);
  final KdbxDatabase database;
  final DateTime now;
  static final _placeholder = RegExp(r'\{([^{}]*)\}');
  static const _standard = {
    'TITLE': EntryFields.title,
    'USERNAME': EntryFields.userName,
    'PASSWORD': EntryFields.password,
    'URL': EntryFields.url,
    'NOTES': EntryFields.notes,
  };
  static const _reference = {
    'T': EntryFields.title,
    'U': EntryFields.userName,
    'P': EntryFields.password,
    'A': EntryFields.url,
    'N': EntryFields.notes,
  };
  static const _maxLength = 65536;
  final _path = <(KdbxEntry, String)>{};
  int _expansions = 0;
  int _scanned = 0;

  ResolvedField field(KdbxEntry entry, String key, int depth) {
    if (depth > 16) {
      throw const FieldReferenceException(FieldReferenceIssue.limit);
    }
    if (!_path.add((entry, key))) {
      throw const FieldReferenceException(FieldReferenceIssue.cycle);
    }
    try {
      final raw = entry.fields[key];
      final original = raw?.text ?? '';
      if (original.length > _maxLength) {
        throw const FieldReferenceException(FieldReferenceIssue.limit);
      }
      final text = _removeComments(original);
      var sensitive = key == EntryFields.password || raw is ProtectedTextField;
      final output = StringBuffer();
      var offset = 0;
      for (final match in _placeholder.allMatches(text)) {
        output.write(text.substring(offset, match.start));
        final token = match.group(1)!;
        final upper = token.toUpperCase();
        ResolvedField? replacement;
        if (_standard[upper] case final name?) {
          _budget();
          replacement = field(entry, name, depth + 1);
        } else if (upper == 'UUID') {
          _budget();
          replacement = ResolvedField(text: itemIdOf(entry), protected: false);
        } else if ((upper == 'GROUP' || upper == 'GROUPPATH') &&
            entry.parent != null) {
          _budget();
          final group = entry.parent!;
          replacement = ResolvedField(
            text: upper == 'GROUP' ? group.name : groupFullPath(group),
            protected: false,
          );
        } else if (upper == 'URL:RMVSCM') {
          _budget();
          final url = field(entry, EntryFields.url, depth + 1);
          final colon = url.text.indexOf(':');
          var start = colon + 1;
          if (colon >= 0 && url.text.startsWith('//', start)) start += 2;
          replacement = ResolvedField(
            text: colon < 0 ? url.text : url.text.substring(start),
            protected: url.protected,
          );
        } else if (const {
          'URL:SCM',
          'URL:HOST',
          'URL:PORT',
          'URL:PATH',
          'URL:QUERY',
        }.contains(upper)) {
          _budget();
          final url = field(entry, EntryFields.url, depth + 1);
          final uri = Uri.tryParse(url.text);
          String? value;
          if (uri != null && uri.hasScheme) {
            value = switch (upper) {
              'URL:SCM' => uri.scheme,
              'URL:HOST' => uri.host,
              'URL:PORT' =>
                (uri.hasPort || uri.port != 0 ? uri.port : -1).toString(),
              'URL:PATH' =>
                uri.hasAuthority && uri.path.isEmpty ? '/' : uri.path,
              'URL:QUERY' => uri.hasQuery ? '?${uri.query}' : '',
              _ => null,
            };
          }
          replacement = ResolvedField(
            text: value ?? match.group(0)!,
            protected: url.protected,
          );
        } else if (_dateTime(upper) case final value?) {
          _budget();
          replacement = ResolvedField(text: value, protected: false);
        } else if (upper.startsWith('S:')) {
          _budget();
          final name = token.substring(2);
          if (!entry.fields.containsKey(name)) {
            throw const FieldReferenceException(FieldReferenceIssue.missing);
          }
          replacement = field(entry, name, depth + 1);
        } else if (upper.startsWith('REF:')) {
          _budget();
          replacement = reference(token.substring(4), depth + 1);
        }
        output.write(replacement?.text ?? match.group(0));
        sensitive |= replacement?.protected ?? false;
        if (output.length > _maxLength) {
          throw const FieldReferenceException(FieldReferenceIssue.limit);
        }
        offset = match.end;
      }
      output.write(text.substring(offset));
      if (output.length > _maxLength) {
        throw const FieldReferenceException(FieldReferenceIssue.limit);
      }
      // Un riferimento troncato non deve finire negli appunti o nell'autofill.
      if (RegExp(
        r'\{(?:REF:|S:)',
        caseSensitive: false,
      ).hasMatch(output.toString())) {
        throw const FieldReferenceException(FieldReferenceIssue.malformed);
      }
      return ResolvedField(text: output.toString(), protected: sensitive);
    } finally {
      _path.remove((entry, key));
    }
  }

  String _removeComments(String text) {
    final output = StringBuffer();
    var offset = 0;
    while (true) {
      final start = text.indexOf('{C:', offset);
      if (start < 0) break;
      final end = text.indexOf('}', start + 3);
      if (end < 0) break;
      _budget();
      output.write(text.substring(offset, start));
      offset = end + 1;
    }
    output.write(text.substring(offset));
    return output.toString();
  }

  String? _dateTime(String token) {
    if (!token.startsWith('DT_')) return null;
    var part = token.substring(3);
    final utc = part.startsWith('UTC_');
    if (utc) part = part.substring(4);
    final time = utc ? now.toUtc() : now.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final year = time.year.toString().padLeft(4, '0');
    return switch (part) {
      'YEAR' => year,
      'MONTH' => two(time.month),
      'DAY' => two(time.day),
      'HOUR' => two(time.hour),
      'MINUTE' => two(time.minute),
      'SECOND' => two(time.second),
      'SIMPLE' =>
        '$year${two(time.month)}${two(time.day)}'
            '${two(time.hour)}${two(time.minute)}${two(time.second)}',
      _ => null,
    };
  }

  void _budget() {
    if (++_expansions > 256) {
      throw const FieldReferenceException(FieldReferenceIssue.limit);
    }
  }

  ResolvedField reference(String spec, int depth) {
    if (spec.length < 5 || spec[1] != '@' || spec[3] != ':') {
      throw const FieldReferenceException(FieldReferenceIssue.malformed);
    }
    final wanted = spec[0].toUpperCase();
    final scan = spec[2].toUpperCase();
    final query = spec.substring(4).toLowerCase();
    if ((!_reference.containsKey(wanted) && wanted != 'I') ||
        (!_reference.containsKey(scan) && scan != 'I' && scan != 'O') ||
        query.isEmpty) {
      throw const FieldReferenceException(FieldReferenceIssue.malformed);
    }
    for (final entry in database.root.allEntries) {
      if (++_scanned > 100000) {
        throw const FieldReferenceException(FieldReferenceIssue.limit);
      }
      if (isInRecycleBin(database, entry)) continue;
      var sensitiveSearch = scan == 'P';
      bool matches;
      if (scan == 'I') {
        matches = itemIdOf(entry).toLowerCase() == query;
      } else {
        final fields = scan == 'O'
            ? entry.fields.entries.where(
                (item) => !EntryFields.standard.contains(item.key),
              )
            : entry.fields.entries.where(
                (item) => item.key == _reference[scan],
              );
        matches = false;
        for (final candidate in fields) {
          if (candidate.value.text.toLowerCase().contains(query)) {
            matches = true;
            sensitiveSearch |= candidate.value is ProtectedTextField;
            break;
          }
        }
      }
      if (!matches) continue;
      final result = wanted == 'I'
          ? ResolvedField(text: itemIdOf(entry), protected: false)
          : field(entry, _reference[wanted]!, depth);
      return ResolvedField(
        text: result.text,
        protected: result.protected || sensitiveSearch,
      );
    }
    throw const FieldReferenceException(FieldReferenceIssue.missing);
  }
}
