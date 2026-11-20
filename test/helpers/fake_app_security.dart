import 'dart:async';

import 'package:app_security/app_security.dart';

/// Biometria registrata ([biometrics]), eventi di schermo spento e notifica
/// del database aperto simulati.
class FakeAppSecurity extends AppSecurity {
  FakeAppSecurity({this.biometrics = false});

  bool biometrics;
  final events = StreamController<void>.broadcast();

  /// Permesso concesso e notifiche attive nel sistema.
  bool notificationsAllowed = true;
  var permissionRequests = 0;

  /// Testi della notifica visibile; `null` se non c'è.
  OpenNotificationTexts? notification;

  /// Tocchi di "Blocca" nella notifica.
  final lockEvents = StreamController<void>.broadcast();

  @override
  Future<bool> hasStrongBiometrics() async => biometrics;

  @override
  Stream<void> screenOff() => events.stream;

  @override
  bool get supportsOpenNotification => true;

  @override
  Future<bool> requestNotificationPermission() async {
    permissionRequests++;
    return notificationsAllowed;
  }

  @override
  Future<bool> showOpenNotification(OpenNotificationTexts texts) async {
    if (!notificationsAllowed) return false;
    notification = texts;
    return true;
  }

  @override
  Future<void> hideOpenNotification() async => notification = null;

  @override
  Stream<void> notificationLock() => lockEvents.stream;
}
