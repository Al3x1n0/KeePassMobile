import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_clipboard/secure_clipboard.dart';

import '../settings/app_settings.dart';

/// Copia negli appunti con pulizia automatica (CopyToClipboardService di
/// Keepass2Android).
///
/// La pulizia è affidata al sistema operativo tramite il plugin
/// `secure_clipboard`, perché avviene anche con l'app in background, sospesa o
/// chiusa (ADR-004). Su Android il valore è marcato come sensibile, su iOS la
/// copia è solo locale.
class ClipboardService {
  ClipboardService({
    this._clearAfter = defaultClearAfter,
    this.clipboard = const SecureClipboard(),
    this._readClearAfter,
  });

  static const defaultClearAfter = AppSettings.defaultClipboardTimeout;

  final Duration _clearAfter;
  final Duration Function()? _readClearAfter;

  /// Timeout selezionato al momento della copia.
  Duration get clearAfter => _readClearAfter?.call() ?? _clearAfter;
  final SecureClipboard clipboard;
  bool _generatedCopy = false;
  int _copyGeneration = 0;
  Future<void> _pendingOperation = Future.value();

  // Un blocco accodato a una copia ancora in corso deve svuotarla anche se
  // il plugin completa la copia dopo che la sessione è già stata chiusa.
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final operation = _pendingOperation.then((_) => action());
    _pendingOperation = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  /// [generated] identifica solo la copia della tab Genera, senza conservarne
  /// il testo: un blocco automatico può lasciarla scadere al timeout nativo.
  Future<void> copy(String text, {bool generated = false}) async {
    final generation = ++_copyGeneration;
    final timeout = clearAfter;
    _generatedCopy = generated;
    try {
      await _enqueue(() => clipboard.copy(text, clearAfter: timeout));
    } on Object {
      if (_copyGeneration == generation) _generatedCopy = false;
      rethrow;
    }
  }

  /// Svuota subito gli appunti se contengono ancora la copia dell'app (blocco
  /// del database). `true` se li ha svuotati.
  ///
  /// Non fallisce mai: il blocco la chiama senza attenderla, quindi un errore
  /// del codice nativo resterebbe non gestito. In quel caso gli appunti si
  /// svuotano comunque alla scadenza programmata con la copia.
  Future<bool> clear({bool preserveGenerated = false}) async {
    if (preserveGenerated && _generatedCopy) return false;
    _generatedCopy = false;
    _copyGeneration++;
    try {
      return await _enqueue(clipboard.clearOwnCopy);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Servizio con il tempo di pulizia scelto nelle impostazioni.
final clipboardServiceProvider = Provider<ClipboardService>(
  (ref) => ClipboardService(
    readClearAfter: () => ref.read(appSettingsProvider).clipboardTimeout,
  ),
);
