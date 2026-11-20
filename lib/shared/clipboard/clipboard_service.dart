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
  const ClipboardService({
    this.clearAfter = defaultClearAfter,
    this.clipboard = const SecureClipboard(),
  });

  static const defaultClearAfter = AppSettings.defaultClipboardTimeout;

  final Duration clearAfter;
  final SecureClipboard clipboard;

  Future<void> copy(String text) =>
      clipboard.copy(text, clearAfter: clearAfter);

  /// Svuota subito gli appunti se contengono ancora la copia dell'app (blocco
  /// del database). `true` se li ha svuotati.
  ///
  /// Non fallisce mai: il blocco la chiama senza attenderla, quindi un errore
  /// del codice nativo resterebbe non gestito. In quel caso gli appunti si
  /// svuotano comunque alla scadenza programmata con la copia.
  Future<bool> clear() async {
    try {
      return await clipboard.clearOwnCopy();
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
    clearAfter: ref.watch(
      appSettingsProvider.select((s) => s.clipboardTimeout),
    ),
  ),
);
