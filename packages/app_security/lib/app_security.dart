/// Eventi di sistema per la sicurezza della sessione di KeePassMobile.
///
/// - Android: `ACTION_SCREEN_OFF`, ricevuto con un receiver registrato solo
///   mentre qualcuno ascolta (App.OnScreenOff di Keepass2Android).
/// - iOS: `protectedDataWillBecomeUnavailableNotification`, inviata quando il
///   dispositivo si blocca. Arriva solo se è impostato un codice di sblocco.
///
/// E se il dispositivo ha una biometria registrata (proposta dello sblocco
/// biometrico).
///
/// Solo Android: notifica del database aperto con l'azione "Blocca"
/// (`OngoingNotificationsService` di Keepass2Android, senza servizio in primo
/// piano) e permesso per le notifiche.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Testi della notifica del database aperto, nella lingua dell'app. Nessun
/// dato del database: la notifica si vede anche sulla schermata di blocco.
@immutable
class OpenNotificationTexts {
  const OpenNotificationTexts({
    required this.channel,
    required this.title,
    required this.text,
    required this.lock,
  });

  /// Nome del canale nelle impostazioni di sistema dell'app.
  final String channel;
  final String title;
  final String text;

  /// Etichetta dell'azione "Blocca".
  final String lock;

  Map<String, String> toMap() => {
    'channel': channel,
    'title': title,
    'text': text,
    'lock': lock,
  };
}

class AppSecurity {
  const AppSecurity();

  @visibleForTesting
  static const screenOffChannel = EventChannel(
    'io.github.al3x1n0.keepassmobile/app_security/screen_off',
  );

  @visibleForTesting
  static const notificationLockChannel = EventChannel(
    'io.github.al3x1n0.keepassmobile/app_security/notification_lock',
  );

  @visibleForTesting
  static const methodChannel = MethodChannel(
    'io.github.al3x1n0.keepassmobile/app_security',
  );

  /// Legge la versione dell'app come numero `x.x.x`, senza build o suffissi.
  ///
  /// Usa `versionName` su Android e `CFBundleShortVersionString` su iOS.
  /// Restituisce `null` se il dato non è disponibile o il plugin non è registrato.
  Future<String?> getAppVersion() async {
    try {
      final version = await methodChannel.invokeMethod<Object?>(
        'getAppVersion',
      );
      if (version is! String) return null;
      return RegExp(r'^(\d+\.\d+\.\d+)(?:[-+].+)?$')
          .firstMatch(version.trim())
          ?.group(1);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// `true` se c'è una biometria forte registrata (impronta o volto):
  /// Android `BiometricManager.canAuthenticate(BIOMETRIC_STRONG)` (da Android
  /// 10), iOS `LAContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`.
  /// `false` se il controllo non riesce.
  Future<bool> hasStrongBiometrics() => _flag('hasStrongBiometrics');

  /// `true` dove esiste la notifica del database aperto (Android).
  bool get supportsOpenNotification =>
      defaultTargetPlatform == TargetPlatform.android;

  /// Chiede il permesso di mostrare notifiche (`POST_NOTIFICATIONS`, Android
  /// 13+); prima di Android 13 risponde se le notifiche sono attive. `true` se
  /// le notifiche si possono mostrare.
  Future<bool> requestNotificationPermission() =>
      _flag('requestNotificationPermission');

  /// Mostra (o aggiorna) la notifica fissa del database aperto. `false` se non
  /// è stata mostrata: notifiche disattivate o permesso negato.
  Future<bool> showOpenNotification(OpenNotificationTexts texts) =>
      _flag('showOpenNotification', texts.toMap());

  /// Toglie la notifica del database aperto.
  Future<void> hideOpenNotification() => _flag('hideOpenNotification');

  Future<bool> _flag(String method, [Object? arguments]) async {
    try {
      return await methodChannel.invokeMethod<bool>(method, arguments) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Un evento a ogni spegnimento dello schermo (Android) o blocco del
  /// dispositivo (iOS). Il codice nativo resta in ascolto solo finché c'è
  /// almeno un abbonato.
  Stream<void> screenOff() =>
      screenOffChannel.receiveBroadcastStream().map((_) {});

  /// Un evento a ogni tocco di "Blocca" nella notifica del database aperto
  /// (solo Android). Senza abbonati il codice nativo toglie soltanto la
  /// notifica (app chiusa dal sistema: nessun database aperto).
  Stream<void> notificationLock() =>
      notificationLockChannel.receiveBroadcastStream().map((_) {});
}
