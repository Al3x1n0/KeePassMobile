import 'dart:convert';
import 'dart:io';
import 'package:kpasslib/kpasslib.dart';
/// Stampa in JSON la struttura del database [a.first]; i valori protetti sono
/// mascherati. Chiave: variabile KPM_DB_KEY (predefinita quella del demo).
Future<void> main(List<String> a) async {
  final key = Platform.environment['KPM_DB_KEY'] ?? 'demo1234';
  final db = await KdbxDatabase.fromBytes(data: File(a.first).readAsBytesSync(), credentials: KdbxCredentials(password: ProtectedData.fromString(key)));
  final bin = db.meta.recycleBinUuid;
  Map<String, Object?> entry(KdbxEntry e) => {
    'title': e.fields['Title']?.text,
    'fields': {for (final f in e.fields.entries) if (f.value.text.isNotEmpty) f.key: f.value is ProtectedTextField ? '<protetto:${f.value.text.length}>' : f.value.text},
    'history': e.history.map((h) => h.fields['Title']?.text).toList(),
  };
  Map<String, Object?> group(KdbxGroup g) => {
    'name': g.name, 'bin': g.uuid == bin,
    'entries': g.entries.map(entry).toList(), 'groups': g.groups.map(group).toList(),
  };
  print(jsonEncode({'kdf': db.header.kdfParameters?.get('M'), 'root': group(db.root)}));
}
