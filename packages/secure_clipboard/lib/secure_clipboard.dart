/// Copia negli appunti per un password manager, con pulizia affidata al
/// sistema operativo.
///
/// - Android: contenuto marcato come sensibile; pulizia con un allarme di
///   sistema (funziona anche con l'app sospesa o chiusa). In background gli
///   appunti non sono leggibili, quindi alla scadenza si svuotano comunque.
/// - iOS: scadenza nativa (`expirationDate`) e copia solo locale.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SecureClipboard {
  const SecureClipboard();

  @visibleForTesting
  static const channel = MethodChannel(
    'io.github.al3x1n0.keepassmobile/secure_clipboard',
  );

  /// Copia [text] e programma la pulizia dopo [clearAfter].
  Future<void> copy(String text, {required Duration clearAfter}) =>
      channel.invokeMethod<void>('copy', {
        'text': text,
        'clearAfterMs': clearAfter.inMilliseconds,
      });

  /// Svuota subito gli appunti se contengono ancora l'ultima copia dell'app e
  /// annulla la pulizia programmata. `true` se li ha svuotati.
  Future<bool> clearOwnCopy() async =>
      await channel.invokeMethod<bool>('clearOwnCopy') ?? false;
}
