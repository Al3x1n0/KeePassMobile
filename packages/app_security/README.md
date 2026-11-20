# app_security

Plugin Flutter di KeePassMobile con gli eventi di sistema usati per bloccare
il database (impostazione "Blocca a schermo spento", `LockWhenScreenOff` di
Keepass2Android).

| Piattaforma | Evento | Note |
|---|---|---|
| Android | `ACTION_SCREEN_OFF` | Receiver registrato a runtime solo mentre Dart ascolta |
| iOS | `protectedDataWillBecomeUnavailableNotification` | Solo con un codice di sblocco impostato; iOS non notifica lo spegnimento dello schermo |

Solo Android, notifica del database aperto (`OngoingNotificationsService` di
Keepass2Android, senza servizio in primo piano):

| Metodo | Note |
|---|---|
| `requestNotificationPermission` | `POST_NOTIFICATIONS` da Android 13, chiesto dall'activity |
| `showOpenNotification` / `hideOpenNotification` | Notifica fissa a bassa importanza, testi senza dati del database, azione "Blocca" |
| `notificationLock` | Un evento per ogni "Blocca"; senza ascolto il codice nativo toglie solo la notifica |

La notifica rimasta da un processo chiuso dal sistema si toglie al nuovo
avvio; si toglie anche alla chiusura del motore Flutter. Icona: "lock" di
Material Icons (Apache-2.0).

La protezione da screenshot e registrazione dello schermo non è qui: la
fornisce il pacchetto `no_screenshot` (decisione D3).

Licenza GPLv3, come l'app.
