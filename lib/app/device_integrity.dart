import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jailbreak_root_detection/jailbreak_root_detection.dart';

import '../features/unlock/relock.dart';
import '../shared/database/database_session.dart';

/// Release di prova per il telefono di sviluppo (`--dart-define=KPM_DEVICE_TEST=true`),
/// mantenuta per compatibilità con le configurazioni di prova.
const _deviceTestBuild = bool.fromEnvironment('KPM_DEVICE_TEST');

/// Segnalazioni consentite: opzioni sviluppatore e debug USB/debugger.
const allowedIntegrityProblems = {
  IntegrityProblem.devMode,
  IntegrityProblem.debugged,
};

/// Bundle identifier iOS, per il controllo di app modificata.
const _iosBundleId = 'io.github.al3x1n0.keepassmobile';

/// Problema rilevato sul dispositivo.
enum IntegrityProblem {
  /// Root (RootBeer, Frida, Magisk) su Android, jailbreak su iOS.
  jailbreak,

  /// Emulatore o simulatore.
  notRealDevice,

  /// Debugger collegato; su Android anche il solo debug USB attivo.
  debugged,

  /// Opzioni sviluppatore attive (Android).
  devMode,

  /// App installata su memoria esterna (Android).
  externalStorage,

  /// App modificata (iOS).
  tampered,

  /// Proxy, strumenti di reverse engineering o problema non riconosciuto.
  other,

  /// Il controllo stesso non è riuscito: conta come problema.
  checkFailed,
}

/// Problema corrispondente a un risultato di `checkForIssues`.
IntegrityProblem problemOf(JailbreakIssue issue) => switch (issue) {
  JailbreakIssue.jailbreak ||
  JailbreakIssue.fridaFound ||
  JailbreakIssue.cydiaFound => IntegrityProblem.jailbreak,
  JailbreakIssue.notRealDevice => IntegrityProblem.notRealDevice,
  JailbreakIssue.debugged => IntegrityProblem.debugged,
  JailbreakIssue.devMode => IntegrityProblem.devMode,
  JailbreakIssue.onExternalStorage => IntegrityProblem.externalStorage,
  JailbreakIssue.tampered => IntegrityProblem.tampered,
  JailbreakIssue.proxied ||
  JailbreakIssue.reverseEngineered ||
  JailbreakIssue.unknown => IntegrityProblem.other,
};

/// Controlli di integrità del dispositivo con `jailbreak_root_detection`
/// (decisioni D9 e D10).
///
/// Solo nelle build di release ([enforce]); in debug e profile nessun
/// controllo, per lavorare con emulatori, simulatori e strumenti di sviluppo.
class DeviceIntegrity {
  const DeviceIntegrity({
    this.enforce = kReleaseMode,
    this.deviceTest = _deviceTestBuild,
  });

  /// `false`: nessun controllo (build di debug e profile).
  final bool enforce;

  /// Indicatore di build di prova; la policy è uguale alle release ordinarie.
  final bool deviceTest;

  /// Problemi rilevati; vuoto se il dispositivo è affidabile o se i controlli
  /// sono spenti. Un errore di un controllo dà [IntegrityProblem.checkFailed].
  Future<Set<IntegrityProblem>> check() async {
    if (!enforce) return const {};
    try {
      final problems = await probe();
      return problems.difference(allowedIntegrityProblems);
    } on Object {
      return const {IntegrityProblem.checkFailed};
    }
  }

  /// Tutti i controlli della libreria (sovrascritto nei test).
  @protected
  Future<Set<IntegrityProblem>> probe() async {
    final detector = JailbreakRootDetection.instance;
    final problems = <IntegrityProblem>{
      if (await detector.isJailBroken) IntegrityProblem.jailbreak,
      if (!await detector.isRealDevice) IntegrityProblem.notRealDevice,
    };
    // Controlli di una sola piattaforma: sull'altra il plugin non li conosce.
    if (Platform.isAndroid) {
      if (await detector.isOnExternalStorage) {
        problems.add(IntegrityProblem.externalStorage);
      }
    }
    if (Platform.isIOS && await detector.isTampered(_iosBundleId)) {
      problems.add(IntegrityProblem.tampered);
    }
    for (final issue in await detector.checkForIssues) {
      problems.add(problemOf(issue));
    }
    return problems;
  }
}

final deviceIntegrityProvider = Provider<DeviceIntegrity>(
  (_) => const DeviceIntegrity(),
);

/// Stato dell'app rispetto ai controlli del dispositivo.
enum IntegrityStatus { checking, trusted, compromised }

/// Esito dei controlli: all'avvio e a ogni ritorno in primo piano.
///
/// Una volta [IntegrityStatus.compromised] l'app resta bloccata fino al
/// riavvio (D9): un controllo successivo pulito non la sblocca.
final integrityStatusProvider =
    NotifierProvider<IntegrityStatusNotifier, IntegrityStatus>(
      IntegrityStatusNotifier.new,
    );

class IntegrityStatusNotifier extends Notifier<IntegrityStatus> {
  @override
  IntegrityStatus build() {
    if (!ref.read(deviceIntegrityProvider).enforce) {
      return IntegrityStatus.trusted;
    }
    // Lo stato non si può leggere durante `build`: si legge dopo il controllo.
    unawaited(_check());
    return IntegrityStatus.checking;
  }

  /// Ripete i controlli; se trova un problema chiude il database aperto e
  /// blocca l'app.
  Future<void> recheck() async {
    if (state == IntegrityStatus.compromised) return;
    await _check();
  }

  Future<void> _check() async {
    final problems = await ref.read(deviceIntegrityProvider).check();
    if (!ref.mounted || state == IntegrityStatus.compromised) return;
    if (problems.isEmpty) {
      state = IntegrityStatus.trusted;
      return;
    }
    if (ref.read(databaseSessionProvider) != null) {
      ref.read(databaseSessionProvider.notifier).lock();
    }
    // App bloccata (D9): nessuno sblocco da riproporre.
    ref.read(relockProvider.notifier).clear();
    state = IntegrityStatus.compromised;
  }
}
