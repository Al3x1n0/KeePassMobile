import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../shared/database/database_session.dart';
import '../../shared/database/kdbx_items.dart';

/// Voce trovata, con il nome del gruppo che la contiene.
@immutable
class SearchResult {
  const SearchResult({
    required this.entry,
    required this.groupName,
    required this.groupPath,
  });

  final KdbxEntry entry;
  final String groupName;
  final String groupPath;
}

/// Opzioni valide solo per la ricerca corrente.
@immutable
class SearchOptions {
  const SearchOptions({
    this.title = true,
    this.userName = true,
    this.url = true,
    this.notes = true,
    this.other = true,
    this.tags = true,
    this.password = false,
    this.group = false,
    this.caseSensitive = false,
    this.excludeExpired = false,
    this.regex = false,
  });
  final bool title, userName, url, notes, other, tags, password, group;
  final bool caseSensitive, excludeExpired, regex;
}

/// Ricerca come i parametri predefiniti di KeePass (SearchParameters):
/// titolo, nome utente, URL, note, altri campi e tag, senza password né
/// cronologia, senza distinzione tra maiuscole e minuscole. Ogni parola della
/// ricerca deve comparire in almeno un campo.
///
/// Esclusi i gruppi con ricerca disattivata (impostazione ereditata dal
/// gruppo padre) e il cestino.
List<SearchResult> searchEntries(
  KdbxDatabase database,
  String query, {
  SearchOptions options = const SearchOptions(),
}) {
  final terms = _splitTerms(
    options.caseSensitive ? query : query.toLowerCase(),
  );
  if (terms.isEmpty) return const [];
  final results = [
    for (final result in searchableEntries(database))
      if ((!options.excludeExpired ||
              !isExpired(result.entry, DateTime.now())) &&
          _matches(result, terms, options))
        result,
  ];
  results.sort(
    (a, b) =>
        entryTitle(a.entry)
            .toLowerCase()
            .compareTo(entryTitle(b.entry).toLowerCase()),
  );
  return List.unmodifiable(results);
}

/// Voci in cui si cerca, con il gruppo che le contiene, nell'ordine del
/// database: esclusi il cestino e i gruppi con ricerca disattivata.
Iterable<SearchResult> searchableEntries(KdbxDatabase database) {
  final bin = existingRecycleBin(database);
  Iterable<SearchResult> visit(KdbxGroup group, bool searchable) sync* {
    if (group == bin) return;
    final enabled = group.isSearchingEnabled ?? searchable;
    if (enabled) {
      for (final entry in group.entries) {
        yield SearchResult(
          entry: entry,
          groupName: group.name,
          groupPath: groupFullPath(group),
        );
      }
    }
    for (final child in group.groups) {
      yield* visit(child, enabled);
    }
  }

  return visit(database.root, true);
}

// StrUtil.SplitSearchTerms: le virgolette raggruppano una frase.
List<String> _splitTerms(String query) {
  final terms = <String>[];
  var buffer = StringBuffer();
  var quoted = false;
  for (final rune in query.runes) {
    final char = String.fromCharCode(rune);
    if (char == '"') {
      quoted = !quoted;
    } else if (!quoted &&
        (char == ' ' || char == '\t' || char == '\n' || char == '\r')) {
      if (buffer.isNotEmpty) {
        terms.add(buffer.toString());
        buffer = StringBuffer();
      }
    } else {
      buffer.write(char);
    }
  }
  if (buffer.isNotEmpty) terms.add(buffer.toString());
  return terms;
}

List<String> _searchableValues(SearchResult result, SearchOptions options) {
  final entry = result.entry;
  return [
    for (final MapEntry(:key, :value) in entry.fields.entries)
      if (switch (key) {
        EntryFields.title => options.title,
        EntryFields.userName => options.userName,
        EntryFields.password => options.password,
        EntryFields.url => options.url,
        EntryFields.notes => options.notes,
        _ => options.other,
      })
        value.text,
    if (options.tags) ...?entry.tags,
    if (options.group) result.groupName,
  ];
}

bool _matches(SearchResult result, List<String> terms, SearchOptions options) {
  final haystack = _searchableValues(result, options);
  final values = options.caseSensitive
      ? haystack
      : haystack.map((s) => s.toLowerCase());
  return terms.every((term) {
    final negate = terms.length > 1 && term.startsWith('-') && term.length > 1;
    final text = negate ? term.substring(1) : term;
    final found = values.any((value) => value.contains(text));
    return negate ? !found : found;
  });
}

/// Esegue una regex in un isolate terminabile: una regex patologica non deve
/// bloccare l'interfaccia o proseguire dopo la chiusura della ricerca.
class RegexSearch {
  Isolate? _isolate;
  ReceivePort? _port;

  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port?.sendPort.send(null);
    _port = null;
  }

  Future<List<SearchResult>> run(
    KdbxDatabase db,
    String query,
    SearchOptions options,
  ) async {
    final candidates = [
      for (final result in searchableEntries(db))
        if (!options.excludeExpired || !isExpired(result.entry, DateTime.now()))
          result,
    ];
    final port = ReceivePort();
    _port = port;
    final isolate = await Isolate.spawn(_regexWorker, (
      port.sendPort,
      query,
      options.caseSensitive,
      candidates.map((result) => _searchableValues(result, options)).toList(),
    ));
    if (_port != port) {
      isolate.kill(priority: Isolate.immediate);
      port.close();
      return const [];
    }
    _isolate = isolate;
    try {
      final reply = await port.first.timeout(const Duration(seconds: 2));
      if (reply is! List<int>) throw const FormatException();
      final results = [for (final i in reply) candidates[i]];
      results.sort(
        (a, b) =>
            entryTitle(a.entry)
                .toLowerCase()
                .compareTo(entryTitle(b.entry).toLowerCase()),
      );
      return results;
    } finally {
      if (_port == port) _port = null;
      isolate.kill(priority: Isolate.immediate);
      port.close();
    }
  }
}

void _regexWorker((SendPort, String, bool, List<List<String>>) message) {
  final (port, pattern, caseSensitive, candidates) = message;
  try {
    final expression = RegExp(pattern, caseSensitive: caseSensitive);
    port.send(<int>[
      for (var i = 0; i < candidates.length; i++)
        if (candidates[i].any(expression.hasMatch)) i,
    ]);
  } on FormatException {
    port.send(null);
  }
}

/// Risultati per [query]; `null` se il database è chiuso.
final searchResultsProvider = Provider.autoDispose
    .family<List<SearchResult>?, String>((ref, query) {
      final session = ref.watch(databaseSessionProvider);
      if (session == null) return null;
      return searchEntries(session.database, query);
    });
