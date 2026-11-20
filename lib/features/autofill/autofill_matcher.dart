import 'package:kpasslib/kpasslib.dart';

import '../../shared/database/database_session.dart';
import '../../shared/database/kdbx_items.dart';
import '../entry_edit/entry_edit_view_model.dart';
import '../search/search_view_model.dart';
import 'autofill_channel.dart';

/// Prefissi dei campi con cui Keepass2Android associa una voce a un'app
/// (`AndroidApp1`, …) o a un sito (`KP2A_URL_1`, …): `SetNextFreeUrlField`.
const autofillAppFieldPrefix = 'AndroidApp';
const autofillUrlFieldPrefix = 'KP2A_URL_';

/// Host di [url] come `UrlUtil.GetHost` di KeePass: senza schema, utente,
/// porta e percorso, in minuscolo; vuoto se non c'è.
String hostOf(String url) {
  var rest = url.trim();
  final scheme = rest.indexOf('://');
  if (scheme >= 0) {
    rest = rest.substring(scheme + 3);
  } else if (rest.toLowerCase().startsWith('mailto:')) {
    rest = rest.substring('mailto:'.length);
  }
  final end = rest.indexOf(RegExp('[/?#]'));
  if (end >= 0) rest = rest.substring(0, end);
  final at = rest.lastIndexOf('@');
  if (at >= 0) rest = rest.substring(at + 1);
  if (rest.startsWith('[')) {
    final close = rest.indexOf(']');
    if (close > 0) return rest.substring(0, close + 1).toLowerCase();
  }
  final port = rest.indexOf(':');
  if (port >= 0) rest = rest.substring(0, port);
  return rest.toLowerCase();
}

/// Voci da proporre per [query] (dominio di un sito o
/// `androidapp://<pacchetto>`), come `GetSearchResultsForUrl` di
/// Keepass2Android: la prima ricerca che trova qualcosa tra
/// 1. URL della voce, o campo associato da Keepass2Android, uguale alla
///    richiesta;
/// 2. host della voce uguale a quello della richiesta o di cui la richiesta è
///    un sottodominio (solo siti);
/// 3. come 2, ignorando `www.` nella voce;
/// 4. testo della richiesta in un campo, come la ricerca;
/// 5. testo dell'host della richiesta.
///
/// Esclusi cestino e gruppi con ricerca disattivata; ordine per titolo.
List<KdbxEntry> autofillMatches(KdbxDatabase database, String query) {
  final wanted = query.trim().toLowerCase();
  if (wanted.isEmpty) return const [];
  final entries = [for (final r in searchableEntries(database)) r.entry];
  List<KdbxEntry> sorted(Iterable<KdbxEntry> found) => List.unmodifiable(
    found.toList()..sort(
      (a, b) =>
          entryTitle(a).toLowerCase().compareTo(entryTitle(b).toLowerCase()),
    ),
  );

  final exact = entries.where((e) => _associated(e).contains(wanted));
  if (exact.isNotEmpty) return sorted(exact);

  final host = hostOf(wanted);
  if (!wanted.startsWith(androidAppScheme) && host.isNotEmpty) {
    for (final ignoreWww in [false, true]) {
      final found = entries.where(
        (e) => _sameHost(host, entryField(e, EntryFields.url), ignoreWww),
      );
      if (found.isNotEmpty) return sorted(found);
    }
  }

  for (final text in {wanted, if (host.isNotEmpty) host}) {
    final found = [for (final r in searchEntries(database, text)) r.entry];
    if (found.isNotEmpty) return sorted(found);
  }
  return const [];
}

/// URL della voce e campi di Keepass2Android, in minuscolo; per i siti anche
/// senza `https://`.
Set<String> _associated(KdbxEntry entry) => {
  for (final MapEntry(:key, :value) in entry.fields.entries)
    if (key == EntryFields.url ||
        key.startsWith(autofillAppFieldPrefix) ||
        key.startsWith(autofillUrlFieldPrefix))
      for (final v in _variants(value.text.trim().toLowerCase())) v,
};

Iterable<String> _variants(String value) sync* {
  if (value.isEmpty) return;
  yield value;
  for (final scheme in ['https://', 'http://']) {
    if (value.startsWith(scheme)) {
      final rest = value.substring(scheme.length);
      yield rest.endsWith('/') ? rest.substring(0, rest.length - 1) : rest;
    }
  }
}

/// `SearchForHost` di Keepass2Android: stesso host o sottodominio.
bool _sameHost(String host, String url, bool ignoreWww) {
  var other = hostOf(url);
  if (ignoreWww && other.startsWith('www.')) other = other.substring(4);
  if (other.isEmpty) return false;
  return host == other || host.endsWith('.$other');
}

/// Primo campo libero per associare [entry] a [query] (D28).
String nextAutofillField(KdbxEntry entry, String query) {
  final prefix = query.startsWith(androidAppScheme)
      ? autofillAppFieldPrefix
      : autofillUrlFieldPrefix;
  var n = 1;
  while (entry.fields.containsKey('$prefix$n')) {
    n++;
  }
  return '$prefix$n';
}

/// Valore del campo: `androidapp://<pacchetto>` o `https://<dominio>`.
String autofillFieldValue(String query) =>
    query.startsWith(androidAppScheme) ? query : 'https://$query';

/// Associa la voce [uuid] a [query] (D28): campo non protetto, versione
/// precedente nella cronologia come per ogni modifica.
DatabaseEdit rememberAutofillEdit(KdbxUuid uuid, String query) => (database) {
  final entry = findEntryByUuid(database, uuid);
  if (entry == null) throw StateError('voce non trovata');
  entry.pushHistory();
  entry.fields[nextAutofillField(entry, query)] = KdbxTextField.fromText(
    text: autofillFieldValue(query),
    protected: false,
  );
  entry.times.touch();
  trimHistory(database, entry);
};
