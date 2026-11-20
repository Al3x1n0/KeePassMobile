# document_access

Plugin Flutter di KeePassMobile per leggere e scrivere **nel file originale** i
documenti scelti dall'utente, anche dopo il riavvio dell'app.

| Piattaforma | Scelta | Riferimento salvato | Lettura / scrittura |
|---|---|---|---|
| Android | `ACTION_OPEN_DOCUMENT` + `takePersistableUriPermission` (lettura e scrittura, o solo lettura se il provider non scrive) | URI `content://` | `ContentResolver`, scrittura con modalità `"wt"` (tronca) |
| iOS | `UIDocumentPickerViewController(asCopy: false)` | `bookmark:<base64>` (security-scoped bookmark) | `NSFileCoordinator`; bookmark obsoleti rigenerati e restituiti come `refreshedUri` |

Documenti nuovi (`create`, creazione del database e export):

| Piattaforma | Creazione |
|---|---|
| Android | `ACTION_CREATE_DOCUMENT` con nome proposto e tipo MIME dall'estensione (`MimeTypeMap`, altrimenti `application/octet-stream`): con un nome già presente il sistema propone `nome (1).ext`; permesso persistente come per la scelta; se la scrittura fallisce il documento vuoto viene eliminato |
| iOS | file temporaneo dell'app (contenuto cifrato) spostato con `UIDocumentPickerViewController(forExporting:asCopy: false)`, poi bookmark |

Anche gli URI `file://` sono accettati su entrambe le piattaforme.

Gli errori arrivano a Dart solo come codice (`unavailable`, `io`, `busy`,
`no_activity`), mai con URI o nomi di file.

Licenza GPLv3, come l'app.
