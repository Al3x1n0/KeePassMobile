import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:kpasslib/kpasslib.dart';

import 'features/autofill/autofill_matcher.dart';
import 'features/file_select/demo_database.dart';
import 'features/file_select/recent_files.dart';
import 'l10n/app_localizations.dart';
import 'shared/crypto/app_crypto_engine.dart';
import 'shared/database/database_session.dart';
import 'shared/database/kdbx_items.dart';

/// Prova tecnica D21: interfaccia minima dell'estensione di compilazione
/// automatica di iOS, attiva solo in debug e profile come i controlli che la
/// rendono sicura (`DeviceIntegrity`, `ScreenProtection`): nelle build di
/// release la richiesta si annulla subito (SEC-06, SEC-07).
///
/// Misura memoria e tempi dello sblocco (G3), legge il database dal bookmark
/// dell'app (G4), la chiave di prova dal portachiavi condiviso (G5) e risponde
/// a Safari (G6). Nei risultati solo numeri ed esiti, mai dati del database.
const _channel = MethodChannel('io.github.al3x1n0.keepassmobile/autofill_ios');

Future<void> runAutofillIosSpike() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!autofillIosEnabled) {
    await _channel.invokeMethod<void>('cancel');
    return;
  }
  AppCryptoEngine.install();
  runApp(const _SpikeApp());
}

/// `false` nelle build di release: l'estensione non ha ancora controllo di
/// integrità e schermo protetto.
const autofillIosEnabled = !kReleaseMode;

/// Configurazione dei test automatici (sblocco e risposta senza tocchi) letta
/// solo in debug.
const _autoRunAllowed = kDebugMode;

class _SpikeApp extends StatelessWidget {
  const _SpikeApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'KeePassMobile',
    localizationsDelegates: [
      ...GlobalMaterialLocalizations.delegates,
      ...AppLocalizations.localizationsDelegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF2E7D32),
      appBarTheme: const AppBarTheme(centerTitle: false),
    ),
    home: const _SpikeView(),
  );
}

class _SpikeView extends StatefulWidget {
  const _SpikeView();

  @override
  State<_SpikeView> createState() => _SpikeViewState();
}

class _SpikeViewState extends State<_SpikeView> {
  final _steps = <String>[];
  final _report = <String, Object?>{};
  final _key = TextEditingController();
  List<RecentFile> _recents = const [];
  String _query = '';
  KdbxDatabase? _database;
  List<KdbxEntry> _entries = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _key
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _log(String step) {
    if (mounted) setState(() => _steps.add(step));
  }

  Future<Map<String, Object?>> _memory() async =>
      await _channel.invokeMapMethod<String, Object?>('memory') ?? const {};

  Future<void> _start() async {
    final request =
        await _channel.invokeMapMethod<String, Object?>('request') ?? const {};
    final services = (request['services'] as List? ?? const []).cast<Map>();
    _query = services.isEmpty
        ? ''
        : hostOf(services.first['identifier'] as String? ?? '');
    _report['service_types'] = [for (final s in services) s['type']];
    _report['start_memory_mb'] = request['startMemoryMb'];
    _report['available_mb_at_start'] = request['availableMb'];
    _report['engine_ready_memory_mb'] = (await _memory())['footprintMb'];
    final raw = await _channel.invokeListMethod<String>('recents') ?? const [];
    final recents = [for (final r in raw) ?RecentFile.fromJson(_decode(r))];
    _report['recents'] = recents.length;
    if (mounted) setState(() => _recents = recents);
    _log(
      'Richiesta per ${_query.isEmpty ? '?' : _query}: '
      '${recents.length} database recenti',
    );
    await _channel.invokeMethod<void>('report', _report);
    if (!_autoRunAllowed) return;
    final config = await _channel.invokeMapMethod<String, Object?>('config');
    if (config?['autoRun'] == true && recents.isNotEmpty) {
      _report['mode'] = 'auto';
      await _unlock(
        recents.first,
        config?['masterKey'] as String? ?? '',
        autoComplete: config?['autoComplete'] == true,
      );
    }
  }

  static Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<void> _unlock(
    RecentFile recent,
    String masterKey, {
    bool autoComplete = false,
  }) async {
    setState(() => _busy = true);
    try {
      final Uint8List bytes;
      try {
        bytes = (await _channel.invokeMethod<Uint8List>('readFile', {
          'uri': recent.database.uri,
        }))!;
      } on PlatformException catch (e) {
        _report['g4_read'] = e.code;
        _log('G4: file non leggibile (${e.code})');
        return;
      }
      _report['g4_read'] = 'ok';
      _report['file_kb'] = bytes.length ~/ 1024;
      _report['after_read_memory_mb'] = (await _memory())['footprintMb'];
      _log('G4: database letto dal bookmark dell\'app');

      await _channel.invokeMethod<void>('startSampling');
      final watch = Stopwatch()..start();
      final KdbxDatabase database;
      try {
        database = await openDatabase(data: bytes, password: masterKey);
      } on Object catch (e) {
        await _channel.invokeMethod<double>('stopSampling');
        _report['unlock'] = e.runtimeType.toString();
        _log('Sblocco non riuscito');
        return;
      }
      _report['unlock_password_ms'] = watch.elapsedMilliseconds;
      _report['g3_peak_unlock_password_mb'] = await _channel
          .invokeMethod<double>('stopSampling');
      _report['after_unlock_memory_mb'] = (await _memory())['footprintMb'];
      _log('G3: sblocco con la password in ${watch.elapsedMilliseconds} ms');

      final key = database.header.transformedKey;
      if (key != null) {
        await _channel.invokeMethod<void>('startSampling');
        final keyWatch = Stopwatch()..start();
        await openDatabaseWithKey(data: bytes, key: key);
        _report['unlock_key_ms'] = keyWatch.elapsedMilliseconds;
        _report['g3_peak_unlock_key_mb'] = await _channel.invokeMethod<double>(
          'stopSampling',
        );
        _log(
          'G3: sblocco con la chiave derivata in '
          '${keyWatch.elapsedMilliseconds} ms',
        );
      }

      final shared =
          await _channel.invokeMapMethod<String, Object?>('readSharedKey') ??
          const {};
      _report['g5_status'] = shared['status'];
      _report['g5_length'] = shared['length'];
      _log('G5: portachiavi condiviso, stato ${shared['status']}');

      final matches = autofillMatches(database, _query);
      _report['matches'] = matches.length;
      final memory = await _memory();
      _report['overall_peak_mb'] = memory['overallPeakMb'];
      _report['available_mb_after'] = memory['availableMb'];
      await _channel.invokeMethod<void>('report', _report);
      final entries = matches.isNotEmpty
          ? matches
          : [
              for (final e in database.root.allEntries)
                if (entryUserName(e).isNotEmpty) e,
            ];
      if (mounted) {
        setState(() {
          _database = database;
          _entries = entries;
        });
      }
      if (autoComplete && entries.isNotEmpty) await _complete(entries.first);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete(KdbxEntry entry) async {
    _report['g6'] = 'complete_sent';
    await _channel.invokeMethod<void>('report', _report);
    await _channel.invokeMethod<void>('complete', {
      'user': entryUserName(entry),
      'password': entryField(entry, EntryFields.password),
    });
  }

  Future<void> _ask(RecentFile recent) async {
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(recent.database.name),
        content: TextField(
          controller: _key,
          obscureText: true,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          inputFormatters: [LengthLimitingTextInputFormatter(1024)],
          decoration: InputDecoration(
            helperText: recent.database == DemoDatabaseRepository.file
                ? AppLocalizations.of(context).demoDatabasePassword
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_key.text),
            child: const Text('Sblocca'),
          ),
        ],
      ),
    );
    _key.clear();
    if (key != null && mounted) await _unlock(recent, key);
  }

  @override
  Widget build(BuildContext context) {
    final database = _database;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KeePassMobile (prova)'),
        leading: IconButton(
          tooltip: 'Chiudi',
          icon: const Icon(Icons.close),
          onPressed: () => _channel.invokeMethod<void>('cancel'),
        ),
      ),
      body: ListView(
        children: [
          if (_busy) const LinearProgressIndicator(),
          for (final step in _steps) ListTile(dense: true, title: Text(step)),
          const Divider(),
          if (database == null)
            for (final recent in _recents)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(recent.database.name),
                subtitle: recent.database == DemoDatabaseRepository.file
                    ? Text(AppLocalizations.of(context).demoDatabaseSubtitle)
                    : null,
                onTap: _busy ? null : () => _ask(recent),
              )
          else
            for (final entry in _entries)
              ListTile(
                leading: const Icon(Icons.key),
                title: Text(entryTitle(entry)),
                subtitle: Text(entryUserName(entry)),
                onTap: () => _complete(entry),
              ),
        ],
      ),
    );
  }
}
