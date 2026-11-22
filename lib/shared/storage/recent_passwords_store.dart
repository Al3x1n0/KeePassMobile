import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'file_storage.dart';

/// Conserva nell'archivio sicuro locale gli identificatori delle voci recenti.
class RecentPasswordsStore {
  /// Usa il Keystore su Android e il Keychain su iOS.
  RecentPasswordsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _namespace = 'kpm_recent_passwords';
  static const _prefix = 'recent-passwords:';
  static const _limit = 15;
  static final _historyKey = RegExp(
    '^$_prefix'
    r'[0-9a-f]{64}$',
  );
  static final _entryId = RegExp(r'^[0-9a-f]{32}$');
  static const _android = AndroidOptions(
    storageNamespace: _namespace,
    resetOnError: false,
    migrateOnAlgorithmChange: false,
  );
  static const _ios = IOSOptions(
    accountName: _namespace,
    accessibility: KeychainAccessibility.unlocked_this_device,
  );

  final FlutterSecureStorage _storage;
  Future<void> _pending = Future<void>.value();

  /// Deriva la chiave della cronologia dal riferimento e dall'identità KDBX.
  static String databaseKey(FileRef file, String rootId) =>
      '$_prefix${sha256.convert(utf8.encode(jsonEncode([file.uri, rootId])))}';

  /// Legge gli identificatori, dal più recente, per la chiave del database.
  Future<List<String>> read(String databaseKey) async {
    if (!_historyKey.hasMatch(databaseKey)) return const [];
    await _pending;
    try {
      return await _read(databaseKey);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Sposta [entryId] in testa alla cronologia, mantenendo fino a 15 voci.
  Future<void> record(String databaseKey, String entryId) {
    if (!_historyKey.hasMatch(databaseKey) || !_entryId.hasMatch(entryId)) {
      return Future<void>.value();
    }
    return _mutate(() async {
      final previous = await _read(databaseKey);
      if (previous.firstOrNull == entryId) return;
      final entries = [entryId, ...previous.where((id) => id != entryId)];
      await _storage.write(
        key: databaseKey,
        value: jsonEncode(entries.take(_limit).toList()),
        aOptions: _android,
        iOptions: _ios,
      );
    });
  }

  /// Cancella le cronologie delle password recenti.
  Future<void> clear() => _mutate(() async {
    final stored = await _storage.readAll(aOptions: _android, iOptions: _ios);
    final keys = stored.keys.where(_historyKey.hasMatch).toList();
    await Future.wait([
      for (final key in keys)
        _storage.delete(key: key, aOptions: _android, iOptions: _ios),
    ]);
  });

  Future<List<String>> _read(String databaseKey) async {
    final raw = await _storage.read(
      key: databaseKey,
      aOptions: _android,
      iOptions: _ios,
    );
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) return const [];
      final valid = decoded.whereType<String>().where(_entryId.hasMatch);
      return List.unmodifiable(valid.toSet().take(_limit));
    } on FormatException {
      return const [];
    }
  }

  Future<void> _mutate(Future<void> Function() action) {
    final next = _pending.then((_) async {
      try {
        await action();
      } on PlatformException {
        // La cronologia resta un supporto alla copia riuscita.
      } on MissingPluginException {
        // Archivio sicuro non disponibile sulla piattaforma.
      }
    });
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

/// Istanza condivisa per serializzare gli aggiornamenti della cronologia.
final recentPasswordsStoreProvider = Provider<RecentPasswordsStore>(
  (_) => RecentPasswordsStore(),
);
