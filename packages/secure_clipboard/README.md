# secure_clipboard

Plugin Flutter di KeePassMobile per copiare valori sensibili negli appunti.

| Piattaforma | Sensibile | Pulizia | Solo se è ancora la copia dell'app |
|---|---|---|---|
| Android | `EXTRA_IS_SENSITIVE` negli extra della descrizione (tastiere e anteprima di sistema non mostrano il valore) | `Handler` nel processo + allarme `AlarmManager` (`setExactAndAllowWhileIdle` se consentito, altrimenti `setAndAllowWhileIdle`), anche con l'app sospesa o chiusa | Sì se gli appunti sono leggibili (app in primo piano, identificativo casuale negli extra); in background no, si svuotano comunque |
| iOS | — | `expirationDate` di `UIPasteboard`, gestita dal sistema; `localOnly` esclude gli Appunti universali | Sì, tramite `changeCount` |

Il testo copiato non viene conservato. Una chiusura forzata dell'app su Android
annulla gli allarmi: in quel caso gli appunti restano finché non vengono
sovrascritti.

Licenza GPLv3, come l'app.
