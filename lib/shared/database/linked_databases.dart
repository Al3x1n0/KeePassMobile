import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/file_storage.dart';
import '../crypto/app_crypto_engine.dart';
import '../storage/preferences.dart';
import '../storage/recent_passwords_store.dart';
import 'database_session.dart';
import 'external_change.dart';
import 'field_references.dart';
import 'kdbx_items.dart';

class LinkedDatabase {
  const LinkedDatabase({
    required this.entryId,
    required this.file,
    this.keyFile,
    this.deviceRule = '',
  });
  final String entryId;
  final FileRef file;
  final FileRef? keyFile;
  final String deviceRule;
}

FileRef? _resolveFile(FileRef parent, String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final parentUri = Uri.tryParse(parent.uri);
  if (parentUri == null) return null;
  final relative = text.replaceAll(
    RegExp(r'\{DB_DIR\}\{ENV_DIRSEP\}', caseSensitive: false),
    '',
  );
  Uri? uri;
  if (relative != text) {
    if (!{'file', 'https', 'sftp'}.contains(parentUri.scheme)) return null;
    uri = parentUri.resolve(relative);
  } else if (text.startsWith('/')) {
    uri = Uri.file(text);
  } else {
    uri = Uri.tryParse(text);
  }
  if (uri == null ||
      !{'file', 'https', 'sftp', 'content', 'bookmark'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      ((uri.scheme == 'https' || uri.scheme == 'sftp') && uri.host.isEmpty)) {
    return null;
  }
  final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
  return FileRef(uri: uri.toString(), name: name.isEmpty ? uri.host : name);
}

/// KeeAutoExec: entries under groups called AutoOpen, without executing commands.
List<LinkedDatabase> linkedDatabases(DatabaseSession session) {
  final db = session.database;
  final result = <(int, int, LinkedDatabase)>[];
  var order = 0;
  void visit(KdbxGroup group, bool inAutoOpen) {
    if (isInRecycleBin(db, group)) return;
    final autoOpen = inAutoOpen || group.name.toLowerCase() == 'autoopen';
    if (autoOpen) {
      for (final entry in group.entries) {
        final enabled = entry.fields['Enabled']?.text.toLowerCase();
        if ((isExpired(entry, DateTime.now()) && enabled != 'true') ||
            enabled == 'false') {
          continue;
        }
        final url = resolveEntryField(db, entry, EntryFields.url);
        if (!url.valid) continue;
        final file = _resolveFile(session.file, url.text);
        if (file == null) continue;
        final key = resolveEntryField(db, entry, EntryFields.userName);
        if (!key.valid) continue;
        final keyFile = key.text.isEmpty
            ? null
            : _resolveFile(session.file, key.text);
        if (key.text.isNotEmpty && keyFile == null) continue;
        result.add((
          int.tryParse(entry.fields['Priority']?.text ?? '') ?? order,
          order++,
          LinkedDatabase(
            entryId: itemIdOf(entry),
            file: file,
            keyFile: keyFile,
            deviceRule: entry.fields['IfDevice']?.text.trim() ?? '',
          ),
        ));
      }
    }
    for (final child in group.groups) {
      visit(child, autoOpen);
    }
  }

  visit(db.root, false);
  result.sort((a, b) {
    final priority = a.$1.compareTo(b.$1);
    return priority != 0 ? priority : a.$2.compareTo(b.$2);
  });
  return [for (final item in result) item.$3];
}

String linkedDatabaseApprovalId(FileRef parent, LinkedDatabase link) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          parent.uri,
          link.entryId,
          link.file.uri,
          link.keyFile?.uri,
          link.deviceRule,
        ]),
      ),
    )
    .toString();

final linkedDatabaseApprovalsProvider = Provider<LinkedDatabaseApprovals>(
  (ref) => LinkedDatabaseApprovals(ref.watch(sharedPreferencesProvider)),
);

class LinkedDatabaseApprovals {
  LinkedDatabaseApprovals(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'linked_database_approvals';
  bool contains(String id) =>
      (_prefs.getStringList(_key) ?? const []).contains(id);
  Future<void> add(String id) async {
    final values = <String>{...?_prefs.getStringList(_key), id};
    if (!await _prefs.setStringList(_key, values.toList())) {
      throw StateError('Unable to save approval');
    }
  }
}

/// Cancellable open; no parent database is retained while waiting for I/O.
class LinkedOpenOperation {
  LinkedOpenOperation(
    this.storage,
    this.lookupParent,
    this.link, {
    RecentPasswordsStore? recentPasswordsStore,
  }) : _recentPasswordsStore = recentPasswordsStore ?? RecentPasswordsStore();
  final FileStorage storage;
  final DatabaseSession? Function() lookupParent;
  final LinkedDatabase link;
  final RecentPasswordsStore _recentPasswordsStore;
  bool _canceled = false;
  Isolate? _isolate;
  ReceivePort? _port;
  Uint8List? _keyBytes;
  RestrictedFileRead? _readOperation;
  KdbxDatabase? _openingDatabase;

  void cancel() {
    _canceled = true;
    _readOperation?.cancel();
    _isolate?.kill(priority: Isolate.immediate);
    _port?.close();
    _keyBytes?.fillRange(0, _keyBytes!.length, 0);
    _openingDatabase?.clearSensitiveData();
  }

  Future<StoredFile> _read(FileRef file) async {
    final operation = RestrictedFileRead(storage, file);
    _readOperation = operation;
    try {
      return await operation.run();
    } finally {
      if (identical(_readOperation, operation)) _readOperation = null;
    }
  }

  Future<DatabaseSession> run() async {
    final read = await _read(link.file);
    if (_canceled) throw const DatabaseLockedException();
    try {
      if (link.keyFile case final key?) {
        _keyBytes = (await _read(key)).bytes;
      }
      if (_canceled) throw const DatabaseLockedException();
      var parent = lookupParent();
      if (parent == null ||
          !linkedDatabases(parent).any(
            (item) =>
                item.entryId == link.entryId &&
                item.file == link.file &&
                item.keyFile == link.keyFile &&
                item.deviceRule == link.deviceRule,
          )) {
        throw const DatabaseLockedException();
      }
      var entry = findEntry(parent.database, link.entryId);
      if (entry == null) throw const FileUnavailableException();
      if (link.keyFile == null) {
        if (entry.binaries['KeyFile.bin'] case final binary?) {
          final data = parent.database.binaries.getByRef(binary);
          if (data == null) throw const FileUnavailableException();
          _keyBytes = Uint8List.fromList(data.data);
        }
      }
      var resolved = resolveEntryField(
        parent.database,
        entry,
        EntryFields.password,
      );
      if (!resolved.valid) throw const FileUnavailableException();
      var password = resolved.text;
      resolved = const ResolvedField(text: '', protected: true);
      final port = ReceivePort();
      _port = port;
      final spawning = Isolate.spawn(_linkedOpenWorker, (
        port.sendPort,
        read.bytes,
        password,
        _keyBytes,
      ));
      password = '';
      parent = null;
      entry = null;
      final isolate = await spawning;
      _isolate = isolate;
      if (_canceled) {
        isolate.kill(priority: Isolate.immediate);
        throw const DatabaseLockedException();
      }
      final result = await port.first;
      if (result is! KdbxDatabase) throw const FileUnavailableException();
      _openingDatabase = result;
      try {
        if (_canceled) throw const DatabaseLockedException();
        final ids = await _recentPasswordsStore.read(
          RecentPasswordsStore.databaseKey(
            read.ref,
            idOfUuid(result.root.uuid),
          ),
        );
        if (_canceled) throw const DatabaseLockedException();
        return DatabaseSession(
          file: read.ref,
          keyFile: link.keyFile,
          database: result,
          fileHash: fileHashOf(read.bytes),
          restrictRedirects: true,
          recentPasswordIds: ids,
        );
      } on Object {
        result.clearSensitiveData();
        rethrow;
      }
    } finally {
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _port?.close();
      _port = null;
      _keyBytes?.fillRange(0, _keyBytes!.length, 0);
      _keyBytes = null;
      _openingDatabase = null;
    }
  }
}

Future<void> _linkedOpenWorker(
  (SendPort, Uint8List, String, Uint8List?) args,
) async {
  final (port, data, password, key) = args;
  try {
    AppCryptoEngine.install();
    Future<KdbxDatabase> attempt(String? value) => KdbxDatabase.fromBytes(
      data: data,
      credentials: KdbxCredentials(
        password: value == null ? null : ProtectedData.fromString(value),
        keyData: key,
      ),
    );
    KdbxDatabase database;
    try {
      database = await attempt(password);
    } on InvalidCredentialsError {
      if (password.isNotEmpty || key == null) rethrow;
      database = await attempt(null);
    }
    port.send(database);
  } catch (_) {
    port.send(null);
  } finally {
    key?.fillRange(0, key.length, 0);
  }
}

/// Adds a KeePass-compatible AutoOpen entry to the current database.
DatabaseEdit addLinkedDatabaseEdit({
  required FileRef parent,
  required FileRef child,
  required FileRef? keyFile,
  required String password,
}) => (database) {
  if (_resolveFile(parent, child.uri) == null ||
      (keyFile != null && _resolveFile(parent, keyFile.uri) == null)) {
    throw const FileUnavailableException();
  }
  final group =
      database.root.groups
          .where((group) => group.name.toLowerCase() == 'autoopen')
          .firstOrNull ??
      database.createGroup(parent: database.root, name: 'AutoOpen');
  final entry = database.createEntry(parent: group, icon: KdbxIcon.key);
  entry.fields[EntryFields.title] = PlainTextField(child.name);
  entry.fields[EntryFields.url] = PlainTextField(child.uri);
  entry.fields[EntryFields.userName] = PlainTextField(keyFile?.uri ?? '');
  entry.fields[EntryFields.password] = KdbxTextField.fromText(
    text: password,
    protected: true,
  );
};
