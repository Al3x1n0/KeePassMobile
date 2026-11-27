// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get templatesEmpty =>
      'Nessun modello. Creane uno con + oppure aggiungi i modelli predefiniti dalle Impostazioni.';

  @override
  String get generateKeyFile => 'Genera un file chiave';

  @override
  String get errorCreateKeyFile =>
      'Impossibile salvare e verificare il file chiave.';

  @override
  String get settingsLanguage => 'Lingua';

  @override
  String get settingsLanguageSystem => 'Sistema';

  @override
  String get appTitle => 'KeePassMobile';

  @override
  String get navigationHome => 'Home';

  @override
  String get navigationGenerate => 'Genera';

  @override
  String get navigationCheck => 'Controllo';

  @override
  String get demoDatabaseSubtitle => 'Database demo · Password: demo1234';

  @override
  String get demoDatabasePassword => 'Password demo: demo1234';

  @override
  String get demoDatabaseRemoveTitle => 'Rimuovi database demo';

  @override
  String get demoDatabaseRemoveMessage =>
      'Confermi di voler rimuovere il database d\'esempio? Una volta rimosso non potrà più essere ripristinato.';

  @override
  String get demoDatabaseRemoveWithRecents =>
      'Disattivando \"Ricorda file recenti\" verrà rimosso anche il database d\'esempio, che non potrà più essere ripristinato. Confermi di voler continuare?';

  @override
  String get demoDatabaseRemoveConfirm => 'Conferma';

  @override
  String get fileSelectTitle => 'Apri database';

  @override
  String get fileSelectOpenFile => 'Apri file';

  @override
  String get fileSelectNewDatabase => 'Nuovo DB';

  @override
  String get fileSelectRecentFiles => 'File recenti';

  @override
  String get fileSelectNoRecent =>
      'Nessun file recente. Apri un database KeePass (.kdbx) per iniziare.';

  @override
  String get fileSelectRemove => 'Rimuovi dai file recenti';

  @override
  String get remoteOpenTitle => 'Apri da server';

  @override
  String get remoteServerType => 'Tipo di server';

  @override
  String get remoteServerWebDav => 'WebDAV';

  @override
  String get remoteServerNextcloud => 'Nextcloud';

  @override
  String get remoteServerOwnCloud => 'ownCloud';

  @override
  String get remoteAddress => 'Indirizzo';

  @override
  String get remoteAddressHintWebDav => 'https://server/cartella/';

  @override
  String get remoteAddressHintCloud => 'https://server';

  @override
  String get remoteUserName => 'Nome utente';

  @override
  String get remotePassword => 'Password';

  @override
  String get remoteRemember => 'Ricorda le credenziali';

  @override
  String get remoteRememberHint =>
      'Salvate nell\'archivio sicuro del dispositivo. Altrimenti si chiedono a ogni apertura del file.';

  @override
  String get remoteConnect => 'Connetti';

  @override
  String get remoteUp => 'Cartella superiore';

  @override
  String get remoteEmptyFolder => 'Cartella vuota';

  @override
  String get remoteCancel => 'Annulla';

  @override
  String get remoteSignIn => 'Accedi';

  @override
  String remoteCredentialsTitle(String server) {
    return 'Accesso a $server';
  }

  @override
  String get remoteCredentialsFailed =>
      'Il server ha rifiutato nome utente o password.';

  @override
  String get remoteCertificateTitle => 'Certificato non riconosciuto';

  @override
  String remoteCertificateBody(String server) {
    return 'Il certificato di $server non è riconosciuto dal sistema. Accettalo solo se questa impronta SHA-256 è quella del tuo server:';
  }

  @override
  String get remoteCertificateAccept => 'Accetta';

  @override
  String get errorRemoteAuth =>
      'Il server ha rifiutato nome utente o password.';

  @override
  String get errorRemoteUnreachable =>
      'Server non raggiungibile. Controlla la connessione e l\'indirizzo.';

  @override
  String get errorRemoteNotFound => 'File o cartella non trovati sul server.';

  @override
  String errorRemoteServer(int status) {
    return 'Il server ha risposto con un errore ($status).';
  }

  @override
  String get errorRemoteInsecure =>
      'Usa un indirizzo https://: la connessione deve essere cifrata.';

  @override
  String get errorRemoteCanceled => 'Accesso al server annullato.';

  @override
  String get errorRemoteAddress => 'Indirizzo non valido.';

  @override
  String get unlockPassword => 'Password principale';

  @override
  String get unlockShowPassword => 'Mostra password';

  @override
  String get unlockHidePassword => 'Nascondi password';

  @override
  String get unlockKeyFile => 'File chiave';

  @override
  String get unlockNoKeyFile => 'Nessun file chiave';

  @override
  String get unlockChooseKeyFile => 'Scegli file chiave';

  @override
  String get unlockRemoveKeyFile => 'Rimuovi file chiave';

  @override
  String get unlockButton => 'Sblocca';

  @override
  String get unlockInProgress => 'Sblocco in corso…';

  @override
  String get errorInvalidCredentials => 'Password o file chiave errati.';

  @override
  String get errorFileCorrupted =>
      'Il file è danneggiato o non è un database KeePass.';

  @override
  String get errorUnsupported =>
      'Formato o algoritmo del database non supportato.';

  @override
  String get errorFileTooLarge => 'Il file supera il limite di 128 MiB.';

  @override
  String get errorDatabasePayloadTooLarge =>
      'Il database supera il limite di dimensione dopo la decompressione.';

  @override
  String get errorDatabaseKdfTooCostly =>
      'Le impostazioni di derivazione della chiave superano i limiti di memoria o di calcolo supportati.';

  @override
  String get errorKeyFileUnavailable =>
      'Impossibile leggere il file chiave. Sceglilo di nuovo.';

  @override
  String get errorFileUnavailable =>
      'Impossibile leggere il database. Apri di nuovo il file.';

  @override
  String get errorGeneric => 'Impossibile aprire il database.';

  @override
  String get groupLock => 'Blocca database';

  @override
  String get groupEmpty => 'Questo gruppo è vuoto.';

  @override
  String get entryUntitled => '(senza titolo)';

  @override
  String get cancel => 'Annulla';

  @override
  String get saving => 'Salvataggio in corso…';

  @override
  String get searchTitle => 'Cerca';

  @override
  String get searchHint => 'Cerca nelle voci';

  @override
  String get searchClear => 'Cancella ricerca';

  @override
  String get searchNoResults => 'Nessuna voce trovata.';

  @override
  String get favoritesTitle => 'Preferiti';

  @override
  String get recentPasswordsTitle => 'Password recenti';

  @override
  String get settingsRecentPasswordsHint =>
      'Mostra in Home le voci da cui copi un campo o un codice OTP.';

  @override
  String get settingsRecentPasswordLimit => 'Numero di password recenti';

  @override
  String get favoritesEmpty => 'Nessuna voce preferita.';

  @override
  String get entryFavoriteAdd => 'Aggiungi ai preferiti';

  @override
  String get entryFavoriteRemove => 'Rimuovi dai preferiti';

  @override
  String get groupAddEntry => 'Aggiungi voce o gruppo';

  @override
  String get entryTitle => 'Titolo';

  @override
  String get entryUserName => 'Nome utente';

  @override
  String get entryPassword => 'Password';

  @override
  String get entryUrl => 'URL';

  @override
  String get entryOverrideUrl => 'URL sostitutivo';

  @override
  String get entryNotes => 'Note';

  @override
  String entryCopy(String field) {
    return 'Copia $field';
  }

  @override
  String get entryShow => 'Mostra';

  @override
  String get entryHide => 'Nascondi';

  @override
  String get entryHiddenValue => 'Valore nascosto';

  @override
  String entryCopied(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Copiato. Gli appunti verranno svuotati tra $seconds secondi.',
      one: 'Copiato. Gli appunti verranno svuotati tra 1 secondo.',
    );
    return '$_temp0';
  }

  @override
  String get entryEdit => 'Modifica';

  @override
  String get entryDelete => 'Elimina';

  @override
  String itemsSelected(int count) {
    return '$count selezionati';
  }

  @override
  String get itemsSelectAll => 'Seleziona tutto';

  @override
  String get itemsSelectAllShort => 'Selez. tutti';

  @override
  String get itemsDeleteRecycle =>
      'Spostare gli elementi selezionati e il loro contenuto nel cestino?';

  @override
  String get itemsDeletePermanent =>
      'Eliminare definitivamente gli elementi selezionati e il loro contenuto? L\'operazione non può essere annullata.';

  @override
  String get entryDeleteConfirmRecycle =>
      'Vuoi eliminare questa voce? Verrà spostata nel cestino.';

  @override
  String get entryDeleteConfirmPermanent =>
      'Eliminare definitivamente la voce? L\'operazione non si può annullare.';

  @override
  String get entryEditTitleNew => 'Nuova voce';

  @override
  String get entryEditTitle => 'Modifica voce';

  @override
  String get entryEditSave => 'Salva';

  @override
  String get entryEditAddField => 'Aggiungi campo';

  @override
  String get entryEditFieldName => 'Nome del campo';

  @override
  String get entryEditFieldValue => 'Valore';

  @override
  String get entryEditFieldProtected => 'Protetto';

  @override
  String get entryEditRemoveField => 'Rimuovi campo';

  @override
  String get entryEditFieldNameRequired => 'Inserisci un nome';

  @override
  String get entryEditFieldNameDuplicate => 'Nome già usato';

  @override
  String get entryEditFieldNameReserved => 'Nome riservato a un campo standard';

  @override
  String get entryEditDiscardTitle => 'Scartare le modifiche?';

  @override
  String get entryEditDiscard => 'Scarta';

  @override
  String get entryEditKeepEditing => 'Continua';

  @override
  String get errorSaveUnavailable =>
      'Impossibile salvare: il file non è più raggiungibile. Le modifiche non sono state salvate.';

  @override
  String get errorSaveFailed =>
      'Salvataggio non riuscito. Le modifiche non sono state salvate.';

  @override
  String get errorSaveBusy => 'Un salvataggio è già in corso.';

  @override
  String get errorSaveLocked => 'Il database è stato bloccato.';

  @override
  String get entryEditGenerate => 'Genera password';

  @override
  String get entryTotp => 'TOTP';

  @override
  String entryTotpRemaining(int seconds) {
    return '$seconds s';
  }

  @override
  String get entryTotpInvalid => 'Configurazione TOTP non valida.';

  @override
  String get generatorTitle => 'Generatore di password';

  @override
  String get generatorUse => 'Usa';

  @override
  String get generatorRegenerate => 'Genera di nuovo';

  @override
  String generatorEntropy(int bits) {
    return '$bits bit di entropia';
  }

  @override
  String get generatorInvalid =>
      'Scegli almeno un tipo di carattere o un numero di parole.';

  @override
  String get generatorNoValue => 'Genera una nuova password';

  @override
  String get generatorProfile => 'Profilo';

  @override
  String get generatorProfileCustom => 'Personalizzato';

  @override
  String get generatorCharacters => 'Caratteri';

  @override
  String get generatorLength => 'Lunghezza';

  @override
  String get generatorUpperCase => 'Maiuscole (A-Z)';

  @override
  String get generatorLowerCase => 'Minuscole (a-z)';

  @override
  String get generatorDigits => 'Cifre (0-9)';

  @override
  String get generatorMinus => 'Trattino (-)';

  @override
  String get generatorUnderline => 'Trattino basso (_)';

  @override
  String get generatorSpace => 'Spazio';

  @override
  String get generatorSpecials => 'Speciali (!, \$, %, &, …)';

  @override
  String get generatorSpecialsExtended => 'Speciali estesi (§, ©, ®, …)';

  @override
  String generatorBrackets(String chars) {
    return 'Parentesi ($chars)';
  }

  @override
  String generatorExcludeLookAlike(String chars) {
    return 'Escludi caratteri simili ($chars)';
  }

  @override
  String get generatorAtLeastOne => 'Almeno un carattere per gruppo';

  @override
  String get generatorPassphrase => 'Passphrase';

  @override
  String get generatorWordCount => 'Numero di parole';

  @override
  String get generatorSeparator => 'Separatore';

  @override
  String get generatorCaseLower => 'minuscole';

  @override
  String get generatorCaseUpper => 'MAIUSCOLE';

  @override
  String get generatorCasePascal => 'Iniziali';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get settingsDatabase => 'Database';

  @override
  String get settingsSecurity => 'Sicurezza';

  @override
  String get settingsDisplay => 'Aspetto';

  @override
  String get settingsFiles => 'File';

  @override
  String get settingsSourceCode => 'Codice sorgente';

  @override
  String get settingsSourceCodeHost => 'GitHub';

  @override
  String get settingsPrivacyPolicy => 'Informativa sulla privacy';

  @override
  String get settingsAbout => 'Informazioni';

  @override
  String get settingsAppVersion => 'Versione app';

  @override
  String get settingsClipboardTimeout => 'Pulizia degli appunti';

  @override
  String get settingsLockTimeout => 'Blocco per inattività';

  @override
  String get settingsLockNever => 'Mai';

  @override
  String settingsSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds secondi',
      one: '1 secondo',
    );
    return '$_temp0';
  }

  @override
  String settingsMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minuti',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get settingsLockOnScreenOff => 'Blocca a schermo spento';

  @override
  String get settingsLockOnScreenOffHint =>
      'Su iOS il database si blocca quando si blocca il dispositivo, solo se è impostato un codice di sblocco.';

  @override
  String get settingsSecureScreen => 'Schermo protetto';

  @override
  String get screenProtectionWarning =>
      'Impossibile applicare la protezione dello schermo. Se continui, screenshot o registrazioni potrebbero catturare il contenuto del database.';

  @override
  String get screenProtectionContinue => 'Continua accettando il rischio';

  @override
  String get settingsSecureScreenHint =>
      'Impedisce screenshot e registrazioni dello schermo e nasconde l\'anteprima tra le app recenti.';

  @override
  String get settingsOpenNotification => 'Notifica del database aperto';

  @override
  String get settingsOpenNotificationHint =>
      'Mentre un database è aperto mostra una notifica con l\'azione Blocca.';

  @override
  String get settingsAutofill => 'Compilazione automatica';

  @override
  String get settingsAutofillOn =>
      'KeePassMobile è il servizio di compilazione automatica';

  @override
  String get settingsAutofillOff =>
      'Tocca per scegliere KeePassMobile nelle impostazioni di sistema';

  @override
  String get autofillChooseDatabase => 'Scegli il database';

  @override
  String get autofillNoRecentFiles =>
      'Nessun database recente. Apri prima il database in KeePassMobile.';

  @override
  String get autofillClose => 'Chiudi';

  @override
  String get autofillPickTitle => 'Scegli la voce';

  @override
  String autofillFor(String target) {
    return 'Per $target';
  }

  @override
  String get autofillMatches => 'Voci per questa app o sito';

  @override
  String autofillSiteInApp(String domain, String app) {
    return '$domain in $app';
  }

  @override
  String get autofillApproximateTitle => 'Conferma il destinatario';

  @override
  String autofillApproximateBody(String entry, String target) {
    return '“$entry” corrisponde per un dominio simile o per il testo della ricerca. Vuoi usare le sue credenziali in $target?';
  }

  @override
  String autofillAppIdentityWarning(String entry, String app) {
    return '“$entry” è associata a $app. Prima di compilare le credenziali, conferma che riconosci l’app installata.';
  }

  @override
  String get autofillFillAndRememberApp => 'Ricorda';

  @override
  String get autofillSaveAndRememberApp => 'Crea voce e ricorda l’app';

  @override
  String get autofillRememberAppSignature =>
      'Scegliendo “Ricorda”, compili e salvi la firma dell’app sul dispositivo per le prossime compilazioni.';

  @override
  String get autofillNoMatches =>
      'Nessuna voce trovata: cerca nel database qui sotto.';

  @override
  String get autofillSearchAll => 'Cerca nel database';

  @override
  String get autofillSearchHint => 'Cerca';

  @override
  String autofillDomainWarning(String app, String domain) {
    return 'L\'app $app dichiara di mostrare il sito $domain. Un\'altra app potrebbe dichiararlo per ottenere le credenziali del sito: usa le voci del sito solo se ti fidi dell\'app.';
  }

  @override
  String get autofillUseDomainOnce => 'Usa il sito questa volta';

  @override
  String get autofillUseDomainAlways => 'Usa sempre il sito in questa app';

  @override
  String get autofillRememberTitle => 'Ricordare la voce?';

  @override
  String autofillRememberBody(String target, String entry, String field) {
    return 'Stai per compilare con “$entry” e ricordare l’associazione a $target. Il campo $field verrà aggiunto alla voce e il database salvato.';
  }

  @override
  String get autofillFillOnly => 'Solo ora';

  @override
  String get autofillFillAndRemember => 'Ricorda';

  @override
  String get openNotificationChannel => 'Database aperto';

  @override
  String get openNotificationText => 'Database aperto';

  @override
  String get openNotificationLock => 'Blocca';

  @override
  String get settingsMaskPassword => 'Nascondi le password';

  @override
  String get settingsMaskTotp => 'Nascondi i codici TOTP';

  @override
  String get settingsShowGroupNameInSearch =>
      'Nome del gruppo nei risultati di ricerca';

  @override
  String get settingsShowGroupInEntry =>
      'Mostra il gruppo nel dettaglio della voce';

  @override
  String get settingsListTextSize => 'Dimensione del testo negli elenchi';

  @override
  String get settingsSizeSmall => 'Piccolo';

  @override
  String get settingsSizeMedium => 'Medio';

  @override
  String get settingsSizeLarge => 'Grande';

  @override
  String get entryGroup => 'Gruppo';

  @override
  String get entryCreated => 'Creata';

  @override
  String get entryModified => 'Ultima modifica';

  @override
  String get settingsShowUserName => 'Nome utente negli elenchi';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeSystem => 'Come il sistema';

  @override
  String get settingsThemeLight => 'Chiaro';

  @override
  String get settingsThemeDark => 'Scuro';

  @override
  String get settingsRememberRecentFiles => 'Ricorda i file recenti';

  @override
  String get settingsRememberKeyFile => 'Ricorda il file chiave';

  @override
  String get createDatabaseTitle => 'Nuovo database';

  @override
  String get createDatabaseConfirm => 'Conferma la password';

  @override
  String get createDatabaseButton => 'Crea database';

  @override
  String get createDatabaseInProgress => 'Creazione in corso…';

  @override
  String get createDatabaseKeyRequired =>
      'Inserisci una password o scegli un file chiave.';

  @override
  String get createDatabaseMismatch => 'Le password non coincidono.';

  @override
  String get createDatabaseInfo =>
      'Il database usa KDBX 4, AES-256 e Argon2id (64 MiB). Al passo successivo scegli dove salvarlo.';

  @override
  String get errorCreateFailed =>
      'Impossibile creare il database. Nessun file è stato aperto.';

  @override
  String get groupMore => 'Altre azioni';

  @override
  String get groupSort => 'Ordina';

  @override
  String get groupSortAscending => 'Nome: A–Z';

  @override
  String get groupSortDescending => 'Nome: Z–A';

  @override
  String get groupSortDatabase => 'Ordine del database';

  @override
  String get groupSortModification => 'Ultima modifica: più recenti';

  @override
  String get groupSortCreation => 'Creazione: meno recenti';

  @override
  String get dbSettingsTitle => 'Impostazioni del database';

  @override
  String get dbSettingsTemplatesGroup => 'Gruppo dei modelli di voci';

  @override
  String get dbSettingsTemplatesNone => 'Nessuno';

  @override
  String get dbSettingsName => 'Nome del database';

  @override
  String get dbSettingsRootGroupName => 'Nome del gruppo radice';

  @override
  String get dbSettingsDefaultUserName => 'Nome utente predefinito';

  @override
  String get dbSettingsRecycleBin => 'Cestino';

  @override
  String get dbSettingsHistoryMaxItems =>
      'Versioni nella cronologia di una voce';

  @override
  String get dbSettingsHistoryMaxSize =>
      'Dimensione massima della cronologia di una voce (MiB)';

  @override
  String get dbSettingsEmptyUnlimited => 'Vuoto: senza limite';

  @override
  String dbSettingsEncryption(int version) {
    return 'Cifratura (KDBX $version)';
  }

  @override
  String get dbSettingsCipher => 'Cifrario';

  @override
  String get dbSettingsKdf => 'Derivazione della chiave';

  @override
  String get dbSettingsRounds => 'Round di trasformazione';

  @override
  String get dbSettingsMemory => 'Memoria (MiB)';

  @override
  String get dbSettingsIterations => 'Iterazioni';

  @override
  String get dbSettingsParallelism => 'Parallelismo (thread)';

  @override
  String get dbSettingsMeasure => 'Misura il tempo di apertura';

  @override
  String dbSettingsMeasured(String seconds) {
    return 'Apertura in circa $seconds s su questo dispositivo.';
  }

  @override
  String dbSettingsRange(int min, int max) {
    return 'Inserisci un valore da $min a $max.';
  }

  @override
  String get dbSettingsSaved => 'Impostazioni del database salvate.';

  @override
  String get cipherAes => 'AES-256';

  @override
  String get cipherChaCha20 => 'ChaCha20';

  @override
  String get cipherTwofish => 'Twofish';

  @override
  String get kdfAes => 'AES-KDF';

  @override
  String get kdfArgon2d => 'Argon2d';

  @override
  String get kdfArgon2id => 'Argon2id';

  @override
  String get changeKeyTitle => 'Cambia chiave principale';

  @override
  String get changeKeyNewPassword => 'Nuova password principale';

  @override
  String get changeKeyButton => 'Cambia chiave';

  @override
  String get changeKeyInProgress => 'Cambio della chiave in corso…';

  @override
  String get changeKeyInfo =>
      'Dopo il cambio il database si apre solo con la nuova chiave.';

  @override
  String get changeKeyDone => 'Chiave principale cambiata.';

  @override
  String get exportTitle => 'Esporta una copia';

  @override
  String exportDone(String name) {
    return 'Copia cifrata esportata: $name';
  }

  @override
  String get entryEditTotpSetup => 'Configura TOTP';

  @override
  String get entryEditTotpUri => 'URI otpauth://';

  @override
  String get entryEditTotpHint =>
      'Incolla l\'indirizzo otpauth:// fornito dal servizio (spesso indicato accanto al codice QR). Sostituisce la configurazione TOTP della voce.';

  @override
  String get entryEditTotpInvalid => 'URI otpauth:// non valido.';

  @override
  String get entryEditTotpApply => 'Applica';

  @override
  String get generatorSaveProfile => 'Salva come profilo';

  @override
  String get generatorRemoveProfile => 'Rimuovi il profilo';

  @override
  String get generatorProfileName => 'Nome del profilo';

  @override
  String get generatorProfileReserved =>
      'Nome riservato a un profilo predefinito.';

  @override
  String get fileSelectNotPersistent =>
      'Questo file resta accessibile solo finché l\'app è aperta: dopo andrà scelto di nuovo.';

  @override
  String get deviceBlockedTitle => 'Dispositivo non sicuro';

  @override
  String get deviceBlockedBody =>
      'KeePassMobile non è utilizzabile su dispositivi con root o jailbreak, né su dispositivi configurati in modo non sicuro. Per proteggere i tuoi database l\'app resta bloccata.';

  @override
  String get entryIcon => 'Icona';

  @override
  String get entryEditChooseIcon => 'Scegli l\'icona';

  @override
  String entryEditIconNumber(int number) {
    return 'Icona $number';
  }

  @override
  String get entryExpires => 'Scade';

  @override
  String entryExpiresOn(String date) {
    return 'Scade il $date';
  }

  @override
  String entryExpiredOn(String date) {
    return 'Scaduta il $date';
  }

  @override
  String get entryEditExpiryDate => 'Data di scadenza';

  @override
  String get entryTags => 'Tag';

  @override
  String get entryEditTagsHint => 'Separati da virgola o punto e virgola';

  @override
  String get entryHistory => 'Cronologia';

  @override
  String entryHistoryVersion(String date) {
    return 'Versione del $date';
  }

  @override
  String entryHistoryReadOnly(String version) {
    return '$version, in sola lettura.';
  }

  @override
  String get entryHistoryRestore => 'Ripristina';

  @override
  String get entryHistoryDelete => 'Elimina versione';

  @override
  String get entryHistoryRestoreConfirm =>
      'Ripristinare questa versione? La versione attuale resta nella cronologia.';

  @override
  String get entryHistoryDeleteConfirm =>
      'Eliminare questa versione dalla cronologia? L\'operazione non si può annullare.';

  @override
  String get entryHistoryUndated => 'Versione senza data';

  @override
  String get close => 'Chiudi';

  @override
  String get entryAttachments => 'Allegati';

  @override
  String get entryEditAttachmentAdd => 'Aggiungi allegato';

  @override
  String get entryEditAttachmentRemove => 'Rimuovi allegato';

  @override
  String get entryEditAttachmentUnreadable =>
      'Impossibile leggere il file scelto.';

  @override
  String entryEditAttachmentTooLarge(String size) {
    return 'Il file supera la dimensione massima di $size.';
  }

  @override
  String get entryEditAttachmentExistsTitle => 'Allegato già presente';

  @override
  String entryEditAttachmentExists(String name) {
    return 'La voce ha già un allegato \"$name\". Vuoi sostituirlo o tenerli entrambi?';
  }

  @override
  String get entryEditAttachmentReplace => 'Sostituisci';

  @override
  String get entryEditAttachmentRename => 'Tieni entrambi';

  @override
  String get entryAttachmentNoPreview =>
      'Anteprima non disponibile per questo tipo di file.';

  @override
  String entryAttachmentSave(String name) {
    return 'Salva $name';
  }

  @override
  String entryAttachmentSaveWarning(String name) {
    return '\"$name\" verrà salvato in chiaro, senza la cifratura del database: chiunque abbia accesso al file potrà leggerlo. Continuare?';
  }

  @override
  String get entryAttachmentSaveConfirm => 'Salva';

  @override
  String entryAttachmentSaved(String name) {
    return 'Allegato salvato: $name';
  }

  @override
  String get entryAttachmentSaveFailed => 'Impossibile salvare l\'allegato.';

  @override
  String get entryUrlOpen => 'Apri nel browser';

  @override
  String get entryUrlNotSupported =>
      'Si possono aprire solo indirizzi http e https.';

  @override
  String get entryUrlNoApp => 'Nessuna app può aprire questo indirizzo.';

  @override
  String get unlockBiometric => 'Sblocca con biometria';

  @override
  String get biometricPromptTitle => 'Sblocca il database';

  @override
  String get biometricPromptCancel => 'Usa la password';

  @override
  String get biometricEnableTitle => 'Attiva lo sblocco biometrico';

  @override
  String get biometricUpdateTitle => 'Aggiorna lo sblocco biometrico';

  @override
  String get errorBiometricUnavailable =>
      'Biometria non disponibile: registra un\'impronta o il volto e imposta il blocco schermo del dispositivo.';

  @override
  String get errorBiometricFailed =>
      'Sblocco biometrico non riuscito. Usa la password.';

  @override
  String get errorBiometricInvalidated =>
      'Sblocco biometrico disattivato perché la biometria del dispositivo è cambiata. Sblocca con la password e riattivalo nelle impostazioni del database.';

  @override
  String get errorBiometricStale =>
      'Il database è stato modificato altrove o la sua chiave è cambiata: sblocca con la password e lo sblocco biometrico verrà aggiornato.';

  @override
  String get dbSettingsBiometric => 'Sblocco biometrico';

  @override
  String get dbSettingsBiometricInfo =>
      'Apri questo database con impronta o volto. Sul dispositivo resta solo la chiave derivata, protetta dalla biometria.';

  @override
  String get dbSettingsKdfLocked =>
      'Con lo sblocco biometrico la derivazione della chiave resta fissa. Per cambiarla disattiva lo sblocco biometrico, blocca il database e riaprilo con la password.';

  @override
  String get errorSaveKdfLocked =>
      'La derivazione della chiave non si può cambiare in questa sessione: riapri il database con la password.';

  @override
  String get changeKeyDoneBiometricOff =>
      'Chiave principale cambiata. Lo sblocco biometrico è stato disattivato: riattivalo nelle impostazioni del database.';

  @override
  String get biometricOfferTitle => 'Sblocco biometrico';

  @override
  String get biometricOfferBody =>
      'Vuoi aprire questo database con impronta o volto? La chiave derivata resta sul dispositivo, protetta dalla biometria. Con “Mai” questa proposta non verrà più mostrata per questo database. Puoi attivarla da Impostazioni → Impostazioni del database.';

  @override
  String get biometricOfferEnable => 'Attiva';

  @override
  String get biometricOfferNever => 'Mai';

  @override
  String get biometricOfferEnabled => 'Sblocco biometrico attivato.';

  @override
  String get externalChangeTitle => 'File modificato altrove';

  @override
  String externalChangeBody(String name) {
    return '«$name» è stato modificato da un\'altra app o da un altro dispositivo dopo l\'apertura. Sincronizza unisce le due versioni; Sovrascrivi lo sostituisce con questa versione e le modifiche fatte altrove vanno perse.';
  }

  @override
  String get externalChangeSynchronize => 'Sincronizza';

  @override
  String get externalChangeOverwrite => 'Sovrascrivi';

  @override
  String get externalChangeCancel => 'Annulla';

  @override
  String get errorSaveExternalCanceled =>
      'Salvataggio annullato: il file è stato modificato altrove. Le modifiche non sono state salvate.';

  @override
  String get errorSyncKeyMismatch =>
      'Sincronizzazione non possibile: il file modificato altrove ha un\'altra chiave principale. Nessuna modifica scritta.';

  @override
  String get errorSyncNeedsPassword =>
      'Sincronizzazione non possibile senza la password: blocca il database e riaprilo con la password principale. Nessuna modifica scritta.';

  @override
  String get errorSyncDifferentDatabase =>
      'Sincronizzazione non possibile: il file è stato sostituito con un altro database. Nessuna modifica scritta.';

  @override
  String get syncNow => 'Sincronizza ora';

  @override
  String get syncInProgress => 'Sincronizzazione in corso…';

  @override
  String get syncUnchanged =>
      'Il file non è cambiato: niente da sincronizzare.';

  @override
  String get syncDone =>
      'Database sincronizzato con le modifiche fatte altrove.';

  @override
  String get remoteServerSftp => 'SFTP';

  @override
  String get remoteAddressHintSftp => 'sftp://server:22/cartella/';

  @override
  String get sshUseKey => 'Usa una chiave privata SSH';

  @override
  String get sshPrivateKey => 'Chiave privata OpenSSH';

  @override
  String get sshChooseKey => 'Scegli il file della chiave privata';

  @override
  String get sshPassphrase => 'Passphrase della chiave privata';

  @override
  String get sshHostTitle => 'Verifica il server SSH';

  @override
  String sshHostBody(String server) {
    return 'Prima connessione a $server. Confronta questa impronta con quella fornita dal gestore del server prima di accettare.';
  }

  @override
  String get errorSshHostChanged =>
      'La chiave SSH del server è cambiata. Connessione bloccata. Verifica il server con il suo gestore.';

  @override
  String get errorSshKey => 'Chiave privata non valida o passphrase errata.';

  @override
  String get errorSftp =>
      'Operazione SFTP non riuscita. Verifica i permessi e il supporto alla rinomina del server.';

  @override
  String get errorRemoteConflict =>
      'Il file sul server è cambiato durante il salvataggio. Nessuna scrittura sul server. Sincronizza e riprova.';

  @override
  String get settingsRemoteCache => 'Cache locale dei database remoti';

  @override
  String get settingsRemoteCacheHint =>
      'Conserva una copia KDBX cifrata, esclusa dai backup. Disattivare non cancella le modifiche ancora da caricare.';

  @override
  String get settingsRemoteCacheClear => 'Elimina copie locali sincronizzate';

  @override
  String get settingsRemoteCacheClearConfirm =>
      'Le modifiche in attesa di caricamento vengono conservate. Per ricreare le copie locali serve una connessione al server.';

  @override
  String get settingsRemoteCacheClearDone =>
      'Pulizia delle copie sincronizzate completata.';

  @override
  String get settingsRemoteCacheClearIncomplete =>
      'Alcune copie non erano verificabili o sono cambiate durante la pulizia.';

  @override
  String get cacheOffline =>
      'Modalità offline: stai usando la copia locale cifrata.';

  @override
  String get cachePending =>
      'Modifiche salvate sul dispositivo, non ancora caricate sul server.';

  @override
  String get cacheUnavailable =>
      'Cache locale non disponibile. La copia offline non è garantita.';

  @override
  String get cacheChanged =>
      'La copia locale è cambiata in un’altra sessione. Riapri il database prima di sincronizzare. Nessuna copia è stata sovrascritta.';

  @override
  String get unlockFromCache =>
      'Apri la copia locale senza contattare il server';

  @override
  String get cacheSyncFailed =>
      'Sincronizzazione non riuscita. La copia locale è conservata.';

  @override
  String get unlockChooseAgain => 'Scegli di nuovo il file';

  @override
  String get groupCreate => 'Nuovo gruppo';

  @override
  String get groupEdit => 'Modifica gruppo';

  @override
  String get iconImport => 'Importa immagine';

  @override
  String get iconCustom => 'Icona personalizzata';

  @override
  String get iconImportError => 'Impossibile leggere l’immagine.';

  @override
  String get databasesClose => 'Chiudi database';

  @override
  String get databasesMove => 'Sposta in un altro database';

  @override
  String get databasesMoveIncomplete =>
      'Copia salvata, ma non è stato possibile rimuovere l’originale.';

  @override
  String get databasesCopy => 'Copia in un altro database';

  @override
  String get linkedDatabaseFailure =>
      'Impossibile aprire un database collegato. Per un server, aprilo prima manualmente e salva le credenziali.';

  @override
  String get linkedDatabaseAdd => 'Aggiungi database collegato';

  @override
  String get linkedDatabaseAddHint =>
      'Collega un altro database aperto per aprirlo automaticamente con questo.';

  @override
  String get linkedDatabasePassword =>
      'Password del database collegato (salvata in questo database)';

  @override
  String get linkedDatabaseDeviceWarning =>
      'Questo collegamento contiene regole per dispositivi specifici. Consentendolo, lo abiliti su questo dispositivo.';

  @override
  String get linkedDatabaseTitle => 'Aprire il database collegato?';

  @override
  String linkedDatabaseBody(String database, String keyFile) {
    return 'Consentire l’accesso a $database? File chiave: $keyFile. La conferma sarà ricordata per questo collegamento.';
  }

  @override
  String get linkedDatabaseAllow => 'Consenti';

  @override
  String get databasesTitle => 'Database aperti';

  @override
  String get databasesOpenAnother => 'Apri un altro database';

  @override
  String get searchGoToGroup => 'Vai al gruppo';

  @override
  String get groupName => 'Nome del gruppo';

  @override
  String get groupNameRequired => 'Inserisci il nome del gruppo.';

  @override
  String get groupDelete => 'Elimina gruppo';

  @override
  String get groupDeleteToBin =>
      'Spostare il gruppo e tutto il suo contenuto nel cestino?';

  @override
  String get groupDeletePermanent =>
      'Eliminare definitivamente il gruppo e tutto il suo contenuto? L’operazione non è reversibile.';

  @override
  String get itemMoveTitle => 'Sposta';

  @override
  String get itemNoDestination => 'Nessun gruppo di destinazione disponibile.';

  @override
  String get itemRestore => 'Ripristina';

  @override
  String get itemDuplicate => 'Duplica';

  @override
  String get itemDuplicateSuffix => 'copia';

  @override
  String get errorItemOperation =>
      'Operazione non consentita per questo elemento o gruppo di destinazione.';

  @override
  String get errorFieldReference =>
      'Impossibile risolvere il riferimento al campo.';

  @override
  String get searchOptions => 'Opzioni di ricerca';

  @override
  String get searchFieldTitle => 'Titolo';

  @override
  String get searchFieldUserName => 'Nome utente';

  @override
  String get searchFieldUrl => 'URL';

  @override
  String get searchFieldPassword => 'Password';

  @override
  String get searchFieldNotes => 'Note';

  @override
  String get searchFieldOther => 'Altri campi';

  @override
  String get searchFieldTags => 'Tag';

  @override
  String get searchFieldGroup => 'Nome del gruppo';

  @override
  String get searchCaseSensitive => 'Distingui maiuscole e minuscole';

  @override
  String get searchExcludeExpired => 'Escludi voci scadute';

  @override
  String get searchRegex => 'Espressione regolare';

  @override
  String get searchRegexError => 'Espressione non valida o ricerca scaduta.';

  @override
  String get searchRegexSubmit =>
      'Avvia la ricerca per eseguire l’espressione.';

  @override
  String get autofillSaveTitle => 'Salva credenziali';

  @override
  String get autofillSaveDescription =>
      'Crea una nuova voce dopo aver verificato questi dati.';

  @override
  String get autofillSaveTarget => 'Sito o app';

  @override
  String get autofillSaveUser => 'Nome utente';

  @override
  String get autofillSaveDatabase => 'Database';

  @override
  String get autofillSavePassword => 'Password';

  @override
  String get autofillSaveConfirm => 'Crea voce';

  @override
  String get autofillSaveRetry =>
      'Chiudi questa schermata e invia di nuovo l\'accesso per riprovare.';

  @override
  String get groupAddTitle => 'Aggiungi';

  @override
  String get templatesInstall => 'Aggiungi modelli predefiniti';

  @override
  String get templatesInstallHint =>
      'Crea un gruppo Modelli con esempi pronti per carte di credito, Wi-Fi e documenti.';

  @override
  String get templateShowAllFields => 'Mostra tutti i campi';

  @override
  String get templatesInstallConfirm =>
      'Aggiungere al database i modelli predefiniti mancanti?';

  @override
  String get templatesInstallSuccess =>
      'I modelli predefiniti sono pronti all’uso.';

  @override
  String get templateGroup => 'Modelli';

  @override
  String get templateIdCard => 'Carta d\'identità';

  @override
  String get templateWlan => 'Wireless LAN';

  @override
  String get templateNote => 'Nota sicura';

  @override
  String get templateCreditCard => 'Carta di credito';

  @override
  String get templateMembership => 'Abbonamento';

  @override
  String get templateNumber => 'Numero';

  @override
  String get templateName => 'Nome';

  @override
  String get templatePlace => 'Luogo di emissione';

  @override
  String get templateIssueDate => 'Data di emissione';

  @override
  String get templateHolder => 'Titolare carta';

  @override
  String get entryTemplateEmpty => 'Nuova voce';

  @override
  String get settingsExpireTan => 'Segna i TAN come scaduti';

  @override
  String get settingsExpireTanHint =>
      'Segna un TAN come utilizzato quando ne apri il dettaglio.';

  @override
  String get entryEditTotpScan => 'Scansiona codice QR';

  @override
  String get entryEditTotpScanError =>
      'Fotocamera non disponibile. Controlla i permessi e riprova.';

  @override
  String get entryColor => 'Colore';

  @override
  String get entryColorNone => 'Nessuno';

  @override
  String entryColorIndicator(String color) {
    return 'Colore: $color';
  }

  @override
  String get entryColorRed => 'Rosso';

  @override
  String get entryColorOrange => 'Arancione';

  @override
  String get entryColorYellow => 'Giallo';

  @override
  String get entryColorGreen => 'Verde';

  @override
  String get entryColorTeal => 'Verde acqua';

  @override
  String get entryColorBlue => 'Blu';

  @override
  String get entryColorPurple => 'Viola';

  @override
  String get entryColorPink => 'Rosa';

  @override
  String get entryColorBrown => 'Marrone';

  @override
  String get entryColorGray => 'Grigio';

  @override
  String get settingsLockInBackground => 'Blocca in background';

  @override
  String get settingsLockInBackgroundHint =>
      'Blocca il database quando passi a un’altra app, escluse le attività di sistema aperte dall’app.';

  @override
  String get generatorSaveAsEntry => 'Salva come nuova voce';

  @override
  String get generatorChooseGroup => 'Scegli il gruppo di destinazione';

  @override
  String get checkAllGood => 'Tutto in ordine';

  @override
  String get checkImprove => 'Da migliorare';

  @override
  String get checkAttention => 'Attenzione';

  @override
  String get checkEmpty => 'Nessuna password da analizzare';

  @override
  String checkSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count password analizzate',
      one: '1 password analizzata',
    );
    return '$_temp0. Controllo locale, solo in memoria.';
  }

  @override
  String get checkDuplicates => 'Duplicate';

  @override
  String get checkWeak => 'Deboli';

  @override
  String get checkOtherProtected => 'Altri campi protetti';

  @override
  String checkExclusions(String references) {
    return 'Sono esclusi: voci nel Cestino, Modelli, campi vuoti, TOTP e riferimenti $references.';
  }

  @override
  String checkSharedCount(int count) {
    return 'Condivisa tra $count voci';
  }

  @override
  String get checkVeryWeak => 'Molto debole';

  @override
  String get checkWeakLevel => 'Debole';

  @override
  String get checkTooShort => 'Troppo corta';

  @override
  String get checkDigitsOnly => 'Solo cifre';

  @override
  String get checkLowVariety => 'Poca varietà o ripetizioni';

  @override
  String get checkCommonPattern => 'Pattern o parola comune';

  @override
  String get checkLimitedComplexity => 'Complessità limitata';

  @override
  String get checkProtectedExplanation =>
      'PIN, CVV e codici secondari hanno spesso lunghezza o formato numerico imposti dal servizio. Aggiornali solo dove è possibile usare valori più lunghi o non riutilizzati.';

  @override
  String get checkReused => 'Valore riutilizzato';

  @override
  String get changeKeyCurrentPassword => 'Password principale attuale';

  @override
  String get changeKeyCurrentRequired => 'Inserisci la password attuale.';

  @override
  String get changeKeyWrongCurrentPassword =>
      'La password attuale non è corretta.';

  @override
  String get autofillNoFillableFields =>
      'Questa voce non contiene valori per i campi richiesti dall’app o dal sito. Aggiungi un nome utente o una password e riprova.';

  @override
  String get dialogSaveUnencryptedTitle => 'Salva in chiaro';

  @override
  String get dialogRestoreVersionTitle => 'Ripristina versione';

  @override
  String get dialogDeleteVersionTitle => 'Elimina versione';

  @override
  String get dialogDiscardBody =>
      'Se esci senza salvare, le modifiche andranno perse.';

  @override
  String get dialogGroupBody => 'Scegli il nome e l’icona del gruppo.';

  @override
  String get dialogLinkedDatabaseBody =>
      'Scegli il database da collegare e inserisci la sua password.';

  @override
  String get dialogRemoteCredentialsBody =>
      'Inserisci le credenziali per accedere al server.';

  @override
  String get dialogProfileBody => 'Scegli un nome per salvare queste opzioni.';

  @override
  String get dialogFill => 'Compila';

  @override
  String get dialogAdd => 'Aggiungi';
}
