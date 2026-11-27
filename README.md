# KeePassMobile

[English](#english)

KeePassMobile è un gestore di password per database KeePass, sviluppato in Flutter,
con un’interfaccia rinnovata e strumenti integrati per generare, organizzare e
controllare le proprie credenziali.

I tuoi dati restano in un database KDBX cifrato, compatibile con KeePass, KeePassXC e
Keepass2Android. Puoi lavorare con file locali oppure collegarti al tuo server
WebDAV o SFTP, con disponibilità offline e sincronizzazione.

La prima distribuzione è prevista su Android. Il progetto include anche l’app iOS;
la distribuzione iOS e la relativa compilazione automatica delle credenziali sono
previste in una fase successiva.

## In evidenza

- **Genera password senza aprire una voce.** La scheda Genera, raggiungibile dalla
  barra di navigazione inferiore, permette di creare password e passphrase,
  copiarle oppure salvarle come nuova credenziale nel gruppo scelto.
- **Controlla le tue credenziali.** La scheda Controllo individua password deboli e
  riutilizzate e permette di aprire le voci da aggiornare. I campi protetti
  aggiuntivi sono analizzati in una sezione separata. Il controllo è locale:
  valuta le password senza inviarle a servizi esterni e non consulta archivi di
  credenziali compromesse.
- **Ritrova rapidamente ciò che ti serve.** Preferiti, ricerca e password recenti
  consentono di accedere alle credenziali usate di frequente.
- **Organizza le voci a modo tuo.** Gruppi, tag, colori, campi personalizzati,
  modelli riutilizzabili e operazioni su più elementi aiutano a gestire il database.
- **Un’interfaccia pensata per l’uso quotidiano.** Navigazione inferiore fra Home,
  Genera, Controllo e Impostazioni, con temi chiaro e scuro e interfaccia in italiano
  e inglese.
- **Esplora subito l’app.** Un database dimostrativo incluso permette di provare
  le funzionalità con dati di esempio.

## Database e funzionalità

- Apertura e salvataggio di database KDBX 3.1, 4.0 e 4.1 nel file originale tramite
  il selettore di sistema (Android Storage Access Framework, iOS Files)
- Cifrari AES-256, ChaCha20 e Twofish; KDF Argon2d/Argon2id e AES-KDF
- Chiave principale con password, file chiave (anche XML v2 `.keyx`) o entrambi
- Creazione di database, cambio della chiave principale ed esportazione di una
  copia KDBX cifrata
- Gestione di gruppi e voci, scadenza, icone, cronologia, allegati e cestino
- Generatore configurabile di password e passphrase basato sulla EFF Large Wordlist
- Codici TOTP, configurabili tramite scansione QR offline o inserimento manuale
  dell’indirizzo `otpauth://`
- Compilazione automatica delle credenziali su Android
- Apertura e salvataggio su server WebDAV tramite HTTPS e su server SFTP
- Cache locale KDBX cifrata per i database remoti, uso offline e sincronizzazione
  al ritorno nell’app
- Rilevamento delle modifiche effettuate da altre app e merge al salvataggio

## Privacy e protezione

[Informativa sulla privacy](https://al3x1n0.github.io/KeePassMobile/privacy/).

Nessuna telemetria. Le connessioni di rete sono limitate allo storage scelto
dall’utente.

- Sblocco biometrico con la chiave derivata custodita nel Keystore/Keychain
- Cancellazione automatica degli appunti dopo il timeout configurato
- Protezione dello schermo da screenshot e registrazioni, configurabile
- Blocco per inattività e a schermo spento, con opzione di blocco in background
- Tastiera configurata senza apprendimento dei dati inseriti
- Nelle build di release, blocco su dispositivi con root o jailbreak

Per segnalare una vulnerabilità leggi [SECURITY.md](SECURITY.md): non aprire una
issue pubblica.

## Compilazione

Serve [FVM](https://fvm.app): la versione di Flutter è fissata in `.fvmrc`.

```sh
fvm install
fvm flutter pub get
fvm flutter analyze
fvm flutter test
fvm flutter build apk --release      # Android
fvm flutter build ios --release      # iOS (serve un team Apple per la firma)
```

Per iOS imposta il tuo team di sviluppo in Xcode (`ios/Runner.xcworkspace`). Le build
di release Android richiedono una chiave di firma configurata localmente in
`android/local.properties` (`release.storeFile`, `release.storePassword`,
`release.keyAlias`, `release.keyPassword`). Conserva la chiave e le credenziali in
un luogo sicuro; non includerle nel repository.

Per prove su dispositivi di sviluppo è disponibile
`--dart-define=KPM_DEVICE_TEST=true`: in release disabilita la protezione dello
schermo e ignora i controlli delle opzioni sviluppatore e del debugger. Le build
con questo flag non sono destinate alla distribuzione.

## Struttura

| Percorso | Contenuto |
|---|---|
| `lib/app/` | Avvio, router, protezione della sessione e del dispositivo |
| `lib/features/` | Schermate e funzionalità (MVVM con Riverpod) |
| `lib/shared/` | Database, sicurezza, archiviazione, impostazioni, componenti grafici |
| `packages/` | Plugin locali (`document_access`, `secure_clipboard`, `app_security`, `argon2_native`) e copie modificate di `kpasslib` e `flutter_secure_storage` |
| `test/`, `integration_test/` | Test unitari, di widget e di integrazione |

## Origini e riconoscimenti

Il progetto nasce dal lavoro su [Keepass2Android](https://github.com/PhilippC/keepass2android),
di Philipp Crocoll e contributori, da cui derivano parte del codice e dei
comportamenti. KeePassMobile ne prosegue lo sviluppo con un’interfaccia
riprogettata e funzionalità proprie.

KeePassMobile non è affiliato a KeePass né a Keepass2Android.

## Licenza

[GPLv3](LICENSE). Componenti di terze parti e relative attribuzioni e licenze in
[NOTICE](NOTICE).

---

## English

KeePassMobile is a password manager for KeePass databases, built with Flutter,
with a redesigned interface and integrated tools to generate, organize and check
your credentials.

Your data stays in an encrypted KDBX database, compatible with KeePass, KeePassXC
and Keepass2Android. Work with local files or connect to your own WebDAV or SFTP
server, with offline access and synchronization.

The first distribution is planned for Android. The project also includes the iOS
app; iOS distribution and credential autofill are planned for a later phase.

## Highlights

- **Generate passwords without opening an entry.** The Generate tab in the bottom
  navigation bar lets you create passwords and passphrases, copy them or save
  them as a new credential in the group of your choice.
- **Check your credentials.** The Check tab identifies weak and reused passwords
  and lets you open entries to update them. Additional protected fields are
  analyzed in a separate section. All checks run locally: passwords are evaluated
  without sending them to external services or querying breached credential
  databases.
- **Quick access to what you need.** Favorites, search and recent passwords help
  you find frequently used credentials.
- **Organize entries your way.** Groups, tags, colors, custom fields, reusable
  templates and operations on multiple items help you manage your database.
- **An interface designed for everyday use.** Bottom navigation connects Home,
  Generate, Check and Settings, with light and dark themes and an interface
  available in Italian and English.
- **Explore the app right away.** An included demo database lets you try its
  features with sample data.

## Databases and features

- Open and save KDBX 3.1, 4.0 and 4.1 databases in the original file through the
  system file picker (Android Storage Access Framework, iOS Files)
- AES-256, ChaCha20 and Twofish ciphers; Argon2d/Argon2id and AES-KDF key derivation
- Master key using a password, a key file (including XML v2 `.keyx`) or both
- Database creation, master key changes and export of an encrypted KDBX copy
- Group and entry management, expiry dates, icons, history, attachments and
  recycle bin
- Configurable password and passphrase generator using the EFF Large Wordlist
- TOTP codes, set up through offline QR scanning or manual entry of an
  `otpauth://` URI
- Credential autofill on Android
- Open and save databases on WebDAV servers over HTTPS and on SFTP servers
- Encrypted local KDBX cache for remote databases, offline use and synchronization
  when returning to the app
- Detection of changes made by other apps and merging on save

## Privacy and protection

[Privacy policy](https://al3x1n0.github.io/KeePassMobile/privacy/).

No telemetry. Network connections are limited to storage chosen by the user.

- Biometric unlock with the derived key held in the Keystore/Keychain
- Automatic clipboard clearing after the configured timeout
- Configurable screen protection against screenshots and recordings
- Lock on inactivity and when the screen turns off, with an option to lock in
  the background
- Keyboard configured not to learn from entered data
- Release builds block use on rooted or jailbroken devices

To report a vulnerability, read [SECURITY.md](SECURITY.md); do not open a public
issue.

## Building

[FVM](https://fvm.app) is required: the Flutter version is pinned in `.fvmrc`.

```sh
fvm install
fvm flutter pub get
fvm flutter analyze
fvm flutter test
fvm flutter build apk --release      # Android
fvm flutter build ios --release      # iOS (an Apple team is required for signing)
```

For iOS, set your development team in Xcode (`ios/Runner.xcworkspace`). Android
release builds require a signing key configured locally in
`android/local.properties` (`release.storeFile`, `release.storePassword`,
`release.keyAlias`, `release.keyPassword`). Keep the key and credentials in a safe
place; do not include them in the repository.

For testing on development devices, `--dart-define=KPM_DEVICE_TEST=true` disables
screen protection and skips developer options and debugger checks in release
builds. Builds using this flag are not intended for distribution.

## Repository structure

| Path | Contents |
|---|---|
| `lib/app/` | Startup, routing, session and device protection |
| `lib/features/` | Screens and features (MVVM with Riverpod) |
| `lib/shared/` | Database, security, storage, settings and UI components |
| `packages/` | Local plugins (`document_access`, `secure_clipboard`, `app_security`, `argon2_native`) and modified copies of `kpasslib` and `flutter_secure_storage` |
| `test/`, `integration_test/` | Unit, widget and integration tests |

## Origins and acknowledgments

The project grew out of work on [Keepass2Android](https://github.com/PhilippC/keepass2android),
by Philipp Crocoll and contributors, from which parts of the code and behavior
are derived. KeePassMobile builds on that foundation with a redesigned interface
and features of its own.

KeePassMobile is not affiliated with KeePass or Keepass2Android.

## License

[GPLv3](LICENSE). Third-party components, attributions and licenses are listed in
[NOTICE](NOTICE).
