# KeePassMobile

Password manager per Android e iOS compatibile con i database KeePass (KDBX), scritto in
Flutter. Ricrea in Flutter il comportamento di [Keepass2Android](https://github.com/PhilippC/keepass2android).

> **Stato:** in sviluppo (0.1.0), non ancora pubblicato sugli store. Usalo solo con copie di
> backup dei tuoi database.

## Funzioni

- Apertura e salvataggio di database KDBX 3.1, 4.0 e 4.1 nel file originale, tramite il
  selettore di sistema (Android Storage Access Framework, iOS Files)
- Cifrari AES-256, ChaCha20 e Twofish; KDF Argon2d/Argon2id (nativo) e AES-KDF
- Chiave principale con password, file chiave (anche XML v2 `.keyx`) o entrambi
- Gruppi e voci: dettaglio, modifica, ricerca, icone, scadenza, tag, campi personalizzati,
  cronologia, allegati
- Generatore di password e passphrase (EFF Large Wordlist), codici TOTP
- Creazione di nuovi database, cambio della chiave principale, export di una copia KDBX cifrata
- Sblocco biometrico con la chiave derivata nel Keystore/Keychain; dopo il blocco si torna subito allo sblocco dello stesso database
- Appunti cancellati automaticamente, schermo protetto da screenshot, blocco per inattività e a
  schermo spento, tastiera senza apprendimento
- Nelle build di release, blocco su dispositivi con root o jailbreak
- Rilevamento delle modifiche fatte da altre app e merge al salvataggio
- Apertura e salvataggio di database su server WebDAV tramite HTTPS e SFTP
- Cache locale KDBX cifrata per i database remoti, con uso offline e sincronizzazione al ritorno nell’app

Connessioni di rete solo verso lo storage scelto dall'utente; nessuna telemetria.

Il TOTP si configura scansionando un codice QR offline oppure inserendo manualmente l’indirizzo `otpauth://`.

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

Per iOS imposta il tuo team di sviluppo in Xcode (`ios/Runner.xcworkspace`). Le build di
release Android richiedono una chiave di firma configurata localmente in `android/local.properties` (`release.storeFile`, `release.storePassword`, `release.keyAlias`, `release.keyPassword`). Conserva la chiave e le credenziali in un luogo sicuro; non includerle nel repository.

Per prove su dispositivi di sviluppo è disponibile `--dart-define=KPM_DEVICE_TEST=true`: in
release disabilita la protezione dello schermo e ignora i controlli delle opzioni sviluppatore
e del debugger. Le build con questo flag non sono destinate alla distribuzione.

## Struttura

| Percorso | Contenuto |
|---|---|
| `lib/app/` | avvio, router, protezione della sessione e del dispositivo |
| `lib/features/` | schermate (MVVM con Riverpod) |
| `lib/shared/` | database, sicurezza, archiviazione, impostazioni, componenti grafici |
| `packages/` | plugin locali (`document_access`, `secure_clipboard`, `app_security`, `argon2_native`) e copie modificate di `kpasslib` e `flutter_secure_storage` |
| `test/`, `integration_test/` | test unitari, di widget e di integrazione |

## Sicurezza

Per segnalare una vulnerabilità leggi [SECURITY.md](SECURITY.md): non aprire una issue pubblica.

## Licenza

[GPLv3](LICENSE). Componenti di terze parti e relative licenze in [NOTICE](NOTICE).

KeePassMobile non è affiliato a KeePass né a Keepass2Android.
