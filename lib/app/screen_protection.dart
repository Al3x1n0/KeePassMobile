import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:no_screenshot/no_screenshot.dart';

/// Schermo protetto (`ViewDatabaseSecure` di Keepass2Android) con il
/// pacchetto `no_screenshot` (decisione D3).
///
/// - Android: `FLAG_SECURE`, quindi niente screenshot, registrazioni e
///   anteprima tra le app recenti.
/// - iOS: contenuto nero in screenshot e registrazioni (tecnica non
///   documentata da Apple: da riverificare a ogni versione di iOS) e
///   copertura a tinta unita nel selettore delle app.
///
/// Attiva nelle release ordinarie; resta spenta in debug, profile e nelle
/// release di prova con `KPM_DEVICE_TEST=true`.
class ScreenProtection {
  const ScreenProtection({
    this.enforce = kReleaseMode,
    this.deviceTest = const bool.fromEnvironment('KPM_DEVICE_TEST'),
  });

  /// `false`: la protezione non si attiva mai (build di debug e profile).
  final bool enforce;

  /// Build di prova esplicita, mai abilitata nelle release distribuite.
  final bool deviceTest;

  /// Nero opaco (0xFF000000) come intero a 32 bit con segno: il valore
  /// positivo supera `Int` e il plugin Android lo riceve come `Long`, che non
  /// sa leggere (ClassCastException visto nel logcat del 2026-11-04).
  static const coverColor = -0x1000000;

  bool get availableInBuild => enforce && !deviceTest;

  Future<bool> apply({required bool enabled}) async {
    final plugin = NoScreenshot.instance;
    final protect = enabled && availableInBuild;
    try {
      // Nelle build senza protezione si spegne sempre: il plugin ricorda lo stato tra
      // un avvio e l'altro.
      if (protect) {
        // Prima il blocco, poi la copertura: la protezione non si interrompe
        // mai tra le due chiamate (ordine indicato dal pacchetto).
        final blocked = await plugin.screenshotOff();
        final covered = await plugin.screenshotWithColor(color: coverColor);
        return blocked && covered;
      } else {
        await plugin.overlayOff();
        await plugin.screenshotOn();
      }
    } on MissingPluginException {
      // Nessun codice nativo (test): niente da proteggere.
    } on PlatformException catch (e) {
      if (kDebugMode) log('protezione dello schermo non applicata: ${e.code}');
    }
    return !protect;
  }
}

final screenProtectionProvider = Provider<ScreenProtection>(
  (_) => const ScreenProtection(),
);

enum ScreenProtectionStatus { checking, ready, warning, acknowledged }

final screenProtectionStatusProvider =
    NotifierProvider<ScreenProtectionStatusNotifier, ScreenProtectionStatus>(
      ScreenProtectionStatusNotifier.new,
    );

class ScreenProtectionStatusNotifier extends Notifier<ScreenProtectionStatus> {
  Future<void> _pending = Future.value();
  int _revision = 0;

  @override
  ScreenProtectionStatus build() =>
      ref.read(screenProtectionProvider).availableInBuild
      ? ScreenProtectionStatus.checking
      : ScreenProtectionStatus.ready;

  Future<bool> apply({required bool enabled}) async {
    final revision = ++_revision;
    final protection = ref.read(screenProtectionProvider);
    final next = _pending.then((_) => protection.apply(enabled: enabled));
    _pending = next.then<void>((_) {});
    final success = await next;
    if (!ref.mounted || revision != _revision) return true;
    if (success) {
      state = ScreenProtectionStatus.ready;
    } else if (state != ScreenProtectionStatus.acknowledged) {
      state = ScreenProtectionStatus.warning;
      return false;
    }
    return true;
  }

  void acknowledge() {
    if (state == ScreenProtectionStatus.warning) {
      state = ScreenProtectionStatus.acknowledged;
    }
  }
}
