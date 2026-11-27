# KeePassMobile — Privacy Policy / Informativa sulla privacy

[Italiano](#italiano) · [English](#english)

## Italiano

Ultimo aggiornamento: 27 novembre 2026. Sviluppatore: Alex.

### Dati e finalità

KeePassMobile è un gestore di password per database KeePass (`.kdbx`). Non richiede un account presso lo sviluppatore. Lo sviluppatore non gestisce server centrali, non riceve i database o le password e non ha accesso ai loro contenuti. L'app non include telemetria, analytics, pubblicità, tracking o servizi remoti di segnalazione degli arresti anomali. Non vende dati personali.

I database sono conservati cifrati su disco; i contenuti vengono decifrati in memoria durante l'uso. I file chiave sono quelli scelti dall'utente. Le preferenze, i riferimenti ai file recenti e le impronte dei server attendibili restano sul dispositivo. Se abilitata, la cache remota conserva copie cifrate dei database per l'uso offline e modifiche in attesa di sincronizzazione. Le credenziali WebDAV/SFTP vengono conservate nell'archivio sicuro del sistema solo scegliendo di ricordarle; altrimenti restano nella sessione. La chiave derivata per lo sblocco biometrico è protetta dall'archivio sicuro del sistema. Se abilitata, la cronologia delle password copiate conserva soltanto gli identificatori delle voci, non copie delle password, localmente nell'archivio sicuro del sistema e può essere cancellata dall'app.

### Rete e condivisione su richiesta

Il permesso Android `INTERNET` serve alle operazioni sui server WebDAV (HTTPS) e SFTP configurati dall'utente: esplorazione, apertura, salvataggio e sincronizzazione dei file. Queste operazioni possono avvenire nel corso di apertura e salvataggio, senza richiedere ogni volta il comando «Sincronizza ora». Database e file chiave remoti vengono scambiati direttamente con il server scelto; il server riceve anche i dati di connessione necessari, come indirizzo IP e credenziali di autenticazione. La conservazione sul server dipende dal servizio scelto dall'utente.

L'app non contatta servizi di telemetria o pubblicità. Su richiesta può aprire nel browser esterno gli URL delle voci e il repository GitHub: tali siti e il browser applicano le proprie politiche. I file selezionati tramite il sistema possono essere forniti da un provider di archiviazione scelto dall'utente. La compilazione automatica Android, se abilitata, consegna le credenziali selezionate all'app o al sito destinatario attraverso il sistema operativo. La copia negli appunti e l'esportazione di allegati sono azioni dell'utente; gli allegati esportati possono restare fuori dal database cifrato.

### Fotocamera, biometria e altri permessi

- `CAMERA`: esclusivamente scansione locale dei QR code dei segreti TOTP. Le immagini della fotocamera sono elaborate in memoria; nessuna foto o registrazione video viene salvata o inviata all'esterno. Il segreto riconosciuto può essere salvato dall'utente nella voce del database. Il microfono non è usato.
- `USE_BIOMETRIC` e funzionalità biometriche del sistema: autenticazione locale per proteggere la chiave di sblocco tramite Android Keystore o iOS Keychain. L'app riceve l'esito dell'autenticazione, non i dati biometrici; questi restano gestiti dal sistema sul dispositivo e non vengono inviati dallo sviluppatore.
- `ACCESS_NETWORK_STATE` su Android: verifica dello stato della connessione da parte dei componenti di rete.
- `POST_NOTIFICATIONS` su Android: notifica locale del database aperto e relative azioni di blocco, senza contenuti delle voci.
- `HIDE_OVERLAY_WINDOWS` su Android: protezione delle schermate da finestre sovrapposte di altre app. Il servizio Autofill usa l'autorizzazione di sistema `BIND_AUTOFILL_SERVICE` e deve essere abilitato dall'utente.

### Conservazione e cancellazione

I dati privati dell'app restano sul dispositivo fino alla rimozione o alla disinstallazione. È possibile disattivare lo sblocco biometrico, rimuovere i recenti e gestire la cache dalle funzioni dell'app. Rimuovere un database ordinario dai recenti non cancella il file originale né le copie remote; il database demo privato viene invece eliminato alla rimozione. Per eliminare definitivamente database, file chiave, allegati esportati o backup esterni, usare anche il gestore file o il server interessato. La disinstallazione rimuove lo spazio privato Android, ma non i file esterni, le copie remote o eventuali elementi che il sistema conserva nel Keychain iOS. Lo sviluppatore non può cancellare file sui dispositivi o sui server degli utenti.

### Contatti

Per richieste sulla privacy: [repository pubblico](https://github.com/Al3x1n0/KeePassMobile), [Issue tracker](https://github.com/Al3x1n0/KeePassMobile/issues) oppure [alexdev479@gmail.com](mailto:alexdev479@gmail.com). Le issue sono pubbliche: non inserirvi password, database, segreti TOTP o altri dati riservati. I dati inviati volontariamente tramite GitHub o email sono trattati dal servizio utilizzato per consentire la risposta alla richiesta.

## English

Last updated: November 27, 2026. Developer: Alex.

### Data and purposes

KeePassMobile is a password manager for KeePass databases (`.kdbx`). It does not require an account with the developer. The developer operates no central servers, receives no databases or passwords and has no access to their contents. The app includes no telemetry, analytics, advertising, tracking or remote crash reporting services. It does not sell personal data.

Databases are stored encrypted on disk; their contents are decrypted in memory during use. Key files are selected by the user. Preferences, recent file references and trusted server fingerprints stay on the device. If enabled, the remote cache stores encrypted database copies for offline use and changes awaiting synchronization. WebDAV/SFTP credentials are kept in the operating system's secure storage only when the user chooses to remember them; otherwise they remain in the session. The derived key for biometric unlocking is protected by the operating system's secure storage. If enabled, copied password history stores only entry identifiers, not password copies, locally in the operating system's secure storage and can be cleared in the app.

### Network access and sharing at your request

The Android `INTERNET` permission supports operations on user-configured WebDAV (HTTPS) and SFTP servers: browsing, opening, saving and synchronizing files. These operations may occur during opening and saving without requiring the “Sync now” command each time. Remote databases and key files are exchanged directly with the selected server; that server also receives necessary connection data, such as IP address and authentication credentials. Server-side retention depends on the service selected by the user.

The app does not contact telemetry or advertising services. At your request, it can open entry URLs and the GitHub repository in an external browser: those websites and the browser apply their own policies. Files selected through the operating system may be supplied by a storage provider chosen by the user. Android Autofill, if enabled, delivers selected credentials to the receiving app or website through the operating system. Copying to the clipboard and exporting attachments are user actions; exported attachments may remain outside the encrypted database.

### Camera, biometrics and other permissions

- `CAMERA`: solely local scanning of QR codes containing TOTP secrets. Camera images are processed in memory; no photos or video recordings are saved or transmitted externally. The recognized secret can be saved by the user in a database entry. The microphone is not used.
- `USE_BIOMETRIC` and system biometric features: local authentication to protect the unlock key through Android Keystore or iOS Keychain. The app receives the authentication result, not biometric data; the operating system manages that data on the device and the developer does not transmit it.
- Android `ACCESS_NETWORK_STATE`: connection status checks by networking components.
- Android `POST_NOTIFICATIONS`: a local notification for an open database and locking actions, without entry contents.
- Android `HIDE_OVERLAY_WINDOWS`: protects screens against overlays from other apps. The Autofill service uses the system `BIND_AUTOFILL_SERVICE` authorization and must be enabled by the user.

### Retention and deletion

Private app data stays on the device until removal or uninstallation. App features allow you to disable biometric unlocking, remove recent files and manage the cache. Removing an ordinary database from recents does not delete its original file or remote copies; the private demo database is deleted when removed. To permanently delete databases, key files, exported attachments or external backups, also use the relevant file manager or server. Uninstallation removes Android private app storage, but does not remove external files, remote copies or items the system may retain in iOS Keychain. The developer cannot delete files on users' devices or servers.

### Contact

For privacy requests: [public repository](https://github.com/Al3x1n0/KeePassMobile), [Issue tracker](https://github.com/Al3x1n0/KeePassMobile/issues) or [alexdev479@gmail.com](mailto:alexdev479@gmail.com). Issues are public: do not include passwords, databases, TOTP secrets or other confidential data. Information voluntarily sent through GitHub or email is handled by the service used to allow a response to your request.
