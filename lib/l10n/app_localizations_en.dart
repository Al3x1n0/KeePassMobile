// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get templatesEmpty =>
      'No templates. Create one with + or add the default templates in Settings.';

  @override
  String get generateKeyFile => 'Generate a key file';

  @override
  String get errorCreateKeyFile => 'Could not save and verify the key file.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get appTitle => 'KeePassMobile';

  @override
  String get navigationHome => 'Home';

  @override
  String get navigationGenerate => 'Generate';

  @override
  String get navigationCheck => 'Check';

  @override
  String get demoDatabaseSubtitle => 'Demo database · Password: demo1234';

  @override
  String get demoDatabasePassword => 'Demo password: demo1234';

  @override
  String get demoDatabaseRemoveTitle => 'Remove demo database';

  @override
  String get demoDatabaseRemoveMessage =>
      'Confirm removing the example database? Once removed, it cannot be restored.';

  @override
  String get demoDatabaseRemoveWithRecents =>
      'Turning off \"Remember recent files\" will also remove the example database, which cannot be restored. Confirm continuing?';

  @override
  String get demoDatabaseRemoveConfirm => 'Confirm';

  @override
  String get fileSelectTitle => 'Open database';

  @override
  String get fileSelectOpenFile => 'Open file';

  @override
  String get fileSelectNewDatabase => 'New DB';

  @override
  String get fileSelectRecentFiles => 'Recent files';

  @override
  String get fileSelectNoRecent =>
      'No recent files. Open a KeePass database (.kdbx) to start.';

  @override
  String get fileSelectRemove => 'Remove from recent files';

  @override
  String get remoteOpenTitle => 'Open from server';

  @override
  String get remoteServerType => 'Server type';

  @override
  String get remoteServerWebDav => 'WebDAV';

  @override
  String get remoteServerNextcloud => 'Nextcloud';

  @override
  String get remoteServerOwnCloud => 'ownCloud';

  @override
  String get remoteAddress => 'Address';

  @override
  String get remoteAddressHintWebDav => 'https://server/folder/';

  @override
  String get remoteAddressHintCloud => 'https://server';

  @override
  String get remoteUserName => 'User name';

  @override
  String get remotePassword => 'Password';

  @override
  String get remoteRemember => 'Remember the credentials';

  @override
  String get remoteRememberHint =>
      'Saved in the device\'s secure storage. Otherwise they are asked every time the file is opened.';

  @override
  String get remoteConnect => 'Connect';

  @override
  String get remoteUp => 'Parent folder';

  @override
  String get remoteEmptyFolder => 'Empty folder';

  @override
  String get remoteCancel => 'Cancel';

  @override
  String get remoteSignIn => 'Sign in';

  @override
  String remoteCredentialsTitle(String server) {
    return 'Sign in to $server';
  }

  @override
  String get remoteCredentialsFailed =>
      'The server rejected the user name or password.';

  @override
  String get remoteCertificateTitle => 'Unrecognized certificate';

  @override
  String remoteCertificateBody(String server) {
    return 'The certificate of $server is not recognized by the system. Accept it only if this SHA-256 fingerprint is the one of your server:';
  }

  @override
  String get remoteCertificateAccept => 'Accept';

  @override
  String get errorRemoteAuth =>
      'The server rejected the user name or password.';

  @override
  String get errorRemoteUnreachable =>
      'Server unreachable. Check the connection and the address.';

  @override
  String get errorRemoteNotFound => 'File or folder not found on the server.';

  @override
  String errorRemoteServer(int status) {
    return 'The server replied with an error ($status).';
  }

  @override
  String get errorRemoteInsecure =>
      'Use an https:// address: the connection must be encrypted.';

  @override
  String get errorRemoteCanceled => 'Access to the server canceled.';

  @override
  String get errorRemoteAddress => 'Invalid address.';

  @override
  String get unlockPassword => 'Master password';

  @override
  String get unlockShowPassword => 'Show password';

  @override
  String get unlockHidePassword => 'Hide password';

  @override
  String get unlockKeyFile => 'Key file';

  @override
  String get unlockNoKeyFile => 'No key file';

  @override
  String get unlockChooseKeyFile => 'Choose key file';

  @override
  String get unlockRemoveKeyFile => 'Remove key file';

  @override
  String get unlockButton => 'Unlock';

  @override
  String get unlockInProgress => 'Unlocking…';

  @override
  String get errorInvalidCredentials => 'Wrong password or key file.';

  @override
  String get errorFileCorrupted =>
      'The file is damaged or is not a KeePass database.';

  @override
  String get errorUnsupported => 'Unsupported database format or algorithm.';

  @override
  String get errorFileTooLarge => 'The file exceeds the 128 MiB size limit.';

  @override
  String get errorDatabasePayloadTooLarge =>
      'The database exceeds the size limit after decompression.';

  @override
  String get errorDatabaseKdfTooCostly =>
      'The key derivation settings exceed the supported memory or computation limits.';

  @override
  String get errorKeyFileUnavailable =>
      'The key file could not be read. Choose it again.';

  @override
  String get errorFileUnavailable =>
      'The database could not be read. Open the file again.';

  @override
  String get errorGeneric => 'The database could not be opened.';

  @override
  String get groupLock => 'Lock database';

  @override
  String get groupEmpty => 'This group is empty.';

  @override
  String get entryUntitled => '(no title)';

  @override
  String get cancel => 'Cancel';

  @override
  String get saving => 'Saving…';

  @override
  String get searchTitle => 'Search';

  @override
  String get searchHint => 'Search entries';

  @override
  String get searchClear => 'Clear search';

  @override
  String get searchNoResults => 'No entries found.';

  @override
  String get favoritesTitle => 'Favorites';

  @override
  String get recentPasswordsTitle => 'Recent passwords';

  @override
  String get settingsRecentPasswordsHint =>
      'Show entries on Home when you copy a field or an OTP code from them.';

  @override
  String get settingsRecentPasswordLimit => 'Number of recent passwords';

  @override
  String get favoritesEmpty => 'No favorite entries.';

  @override
  String get entryFavoriteAdd => 'Add to favorites';

  @override
  String get entryFavoriteRemove => 'Remove from favorites';

  @override
  String get groupAddEntry => 'Add entry or group';

  @override
  String get entryTitle => 'Title';

  @override
  String get entryUserName => 'User name';

  @override
  String get entryPassword => 'Password';

  @override
  String get entryUrl => 'URL';

  @override
  String get entryOverrideUrl => 'Override URL';

  @override
  String get entryNotes => 'Notes';

  @override
  String entryCopy(String field) {
    return 'Copy $field';
  }

  @override
  String get entryShow => 'Show';

  @override
  String get entryHide => 'Hide';

  @override
  String get entryHiddenValue => 'Hidden value';

  @override
  String entryCopied(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Copied. The clipboard will be cleared in $seconds seconds.',
      one: 'Copied. The clipboard will be cleared in 1 second.',
    );
    return '$_temp0';
  }

  @override
  String get entryEdit => 'Edit';

  @override
  String get entryDelete => 'Delete';

  @override
  String itemsSelected(int count) {
    return '$count selected';
  }

  @override
  String get itemsSelectAll => 'Select all';

  @override
  String get itemsSelectAllShort => 'Select all';

  @override
  String get itemsDeleteRecycle =>
      'Move the selected items and their contents to the recycle bin?';

  @override
  String get itemsDeletePermanent =>
      'Permanently delete the selected items and their contents? This cannot be undone.';

  @override
  String get entryDeleteConfirmRecycle =>
      'Delete this entry? It will be moved to the recycle bin.';

  @override
  String get entryDeleteConfirmPermanent =>
      'Delete this entry permanently? This cannot be undone.';

  @override
  String get entryEditTitleNew => 'New entry';

  @override
  String get entryEditTitle => 'Edit entry';

  @override
  String get entryEditSave => 'Save';

  @override
  String get entryEditAddField => 'Add field';

  @override
  String get entryEditFieldName => 'Field name';

  @override
  String get entryEditFieldValue => 'Value';

  @override
  String get entryEditFieldProtected => 'Protected';

  @override
  String get entryEditRemoveField => 'Remove field';

  @override
  String get entryEditFieldNameRequired => 'Enter a name';

  @override
  String get entryEditFieldNameDuplicate => 'This name is already used';

  @override
  String get entryEditFieldNameReserved =>
      'This name is reserved for a standard field';

  @override
  String get entryEditDiscardTitle => 'Discard your changes?';

  @override
  String get entryEditDiscard => 'Discard';

  @override
  String get entryEditKeepEditing => 'Stay';

  @override
  String get errorSaveUnavailable =>
      'Cannot save: the file can no longer be reached. Your changes were not saved.';

  @override
  String get errorSaveFailed => 'Saving failed. Your changes were not saved.';

  @override
  String get errorSaveBusy => 'A save is already in progress.';

  @override
  String get errorSaveLocked => 'The database has been locked.';

  @override
  String get entryEditGenerate => 'Generate password';

  @override
  String get entryTotp => 'TOTP';

  @override
  String entryTotpRemaining(int seconds) {
    return '$seconds s';
  }

  @override
  String get entryTotpInvalid => 'Invalid TOTP settings.';

  @override
  String get generatorTitle => 'Password generator';

  @override
  String get generatorUse => 'Use';

  @override
  String get generatorRegenerate => 'Generate again';

  @override
  String generatorEntropy(int bits) {
    return '$bits bits of entropy';
  }

  @override
  String get generatorInvalid =>
      'Choose at least one character type or a number of words.';

  @override
  String get generatorNoValue => 'Generate a new password';

  @override
  String get generatorProfile => 'Profile';

  @override
  String get generatorProfileCustom => 'Custom';

  @override
  String get generatorCharacters => 'Characters';

  @override
  String get generatorLength => 'Length';

  @override
  String get generatorUpperCase => 'Upper case (A-Z)';

  @override
  String get generatorLowerCase => 'Lower case (a-z)';

  @override
  String get generatorDigits => 'Digits (0-9)';

  @override
  String get generatorMinus => 'Minus (-)';

  @override
  String get generatorUnderline => 'Underline (_)';

  @override
  String get generatorSpace => 'Space';

  @override
  String get generatorSpecials => 'Special (!, \$, %, &, …)';

  @override
  String get generatorSpecialsExtended => 'Extended special (§, ©, ®, …)';

  @override
  String generatorBrackets(String chars) {
    return 'Brackets ($chars)';
  }

  @override
  String generatorExcludeLookAlike(String chars) {
    return 'Exclude look-alike characters ($chars)';
  }

  @override
  String get generatorAtLeastOne => 'At least one character from each group';

  @override
  String get generatorPassphrase => 'Passphrase';

  @override
  String get generatorWordCount => 'Number of words';

  @override
  String get generatorSeparator => 'Separator';

  @override
  String get generatorCaseLower => 'lower';

  @override
  String get generatorCaseUpper => 'UPPER';

  @override
  String get generatorCasePascal => 'Capitalized';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsDatabase => 'Database';

  @override
  String get settingsSecurity => 'Security';

  @override
  String get settingsDisplay => 'Appearance';

  @override
  String get settingsFiles => 'Files';

  @override
  String get settingsSourceCode => 'Source code';

  @override
  String get settingsSourceCodeHost => 'GitHub';

  @override
  String get settingsPrivacyPolicy => 'Privacy policy';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAppVersion => 'App version';

  @override
  String get settingsClipboardTimeout => 'Clear clipboard after';

  @override
  String get settingsLockTimeout => 'Lock after inactivity';

  @override
  String get settingsLockNever => 'Never';

  @override
  String settingsSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds',
      one: '1 second',
    );
    return '$_temp0';
  }

  @override
  String settingsMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get settingsLockOnScreenOff => 'Lock when the screen turns off';

  @override
  String get settingsLockOnScreenOffHint =>
      'On iOS the database locks when the device locks, only if a passcode is set.';

  @override
  String get settingsSecureScreen => 'Secure screen';

  @override
  String get screenProtectionWarning =>
      'Screen protection could not be applied. Continuing may allow screenshots or screen recordings to capture your database.';

  @override
  String get screenProtectionContinue => 'Continue with this risk';

  @override
  String get settingsSecureScreenHint =>
      'Blocks screenshots and screen recordings and hides the preview in recent apps.';

  @override
  String get settingsOpenNotification => 'Open database notification';

  @override
  String get settingsOpenNotificationHint =>
      'While a database is open, shows a notification with the Lock action.';

  @override
  String get settingsAutofill => 'Autofill';

  @override
  String get settingsAutofillOn => 'KeePassMobile is the autofill service';

  @override
  String get settingsAutofillOff =>
      'Tap to choose KeePassMobile in the system settings';

  @override
  String get autofillChooseDatabase => 'Choose the database';

  @override
  String get autofillNoRecentFiles =>
      'No recent databases. Open the database in KeePassMobile first.';

  @override
  String get autofillClose => 'Close';

  @override
  String get autofillPickTitle => 'Choose the entry';

  @override
  String autofillFor(String target) {
    return 'For $target';
  }

  @override
  String get autofillMatches => 'Entries for this app or site';

  @override
  String autofillSiteInApp(String domain, String app) {
    return '$domain in $app';
  }

  @override
  String get autofillApproximateTitle => 'Confirm the recipient';

  @override
  String autofillApproximateBody(String entry, String target) {
    return '“$entry” matched only by a related domain or search text. Fill its credentials in $target?';
  }

  @override
  String autofillAppIdentityWarning(String entry, String app) {
    return '“$entry” is linked to $app. Confirm that you recognize this installed app before filling its credentials.';
  }

  @override
  String get autofillFillAndRememberApp => 'Remember';

  @override
  String get autofillSaveAndRememberApp => 'Create entry and remember app';

  @override
  String get autofillRememberAppSignature =>
      'Choosing “Remember” fills now and saves the app’s signing certificate on this device for future fills.';

  @override
  String get autofillNoMatches =>
      'No entries found: search the database below.';

  @override
  String get autofillSearchAll => 'Search the database';

  @override
  String get autofillSearchHint => 'Search';

  @override
  String autofillDomainWarning(String app, String domain) {
    return 'The app $app says it shows the site $domain. Another app could claim it to obtain the site\'s credentials: use the site\'s entries only if you trust the app.';
  }

  @override
  String get autofillUseDomainOnce => 'Use the site this time';

  @override
  String get autofillUseDomainAlways => 'Always use the site in this app';

  @override
  String get autofillRememberTitle => 'Remember the entry?';

  @override
  String autofillRememberBody(String target, String entry, String field) {
    return 'Fill with “$entry” and remember its association with $target. The field $field will be added to the entry and the database saved.';
  }

  @override
  String get autofillFillOnly => 'Just once';

  @override
  String get autofillFillAndRemember => 'Remember';

  @override
  String get openNotificationChannel => 'Open database';

  @override
  String get openNotificationText => 'Database open';

  @override
  String get openNotificationLock => 'Lock';

  @override
  String get settingsMaskPassword => 'Hide passwords';

  @override
  String get settingsMaskTotp => 'Hide TOTP codes';

  @override
  String get settingsShowGroupNameInSearch =>
      'Show group name in search results';

  @override
  String get settingsShowGroupInEntry => 'Show group in entry details';

  @override
  String get settingsListTextSize => 'List text size';

  @override
  String get settingsSizeSmall => 'Small';

  @override
  String get settingsSizeMedium => 'Medium';

  @override
  String get settingsSizeLarge => 'Large';

  @override
  String get entryGroup => 'Group';

  @override
  String get entryCreated => 'Created';

  @override
  String get entryModified => 'Last modified';

  @override
  String get settingsShowUserName => 'Show user name in lists';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsRememberRecentFiles => 'Remember recent files';

  @override
  String get settingsRememberKeyFile => 'Remember key file';

  @override
  String get createDatabaseTitle => 'New database';

  @override
  String get createDatabaseConfirm => 'Confirm password';

  @override
  String get createDatabaseButton => 'Create database';

  @override
  String get createDatabaseInProgress => 'Creating…';

  @override
  String get createDatabaseKeyRequired =>
      'Enter a password or choose a key file.';

  @override
  String get createDatabaseMismatch => 'The passwords do not match.';

  @override
  String get createDatabaseInfo =>
      'The database uses KDBX 4, AES-256 and Argon2id (64 MiB). Next, choose where to save it.';

  @override
  String get errorCreateFailed =>
      'The database could not be created. No file was opened.';

  @override
  String get groupMore => 'More actions';

  @override
  String get groupSort => 'Sort';

  @override
  String get groupSortAscending => 'Name: A–Z';

  @override
  String get groupSortDescending => 'Name: Z–A';

  @override
  String get groupSortDatabase => 'Database order';

  @override
  String get groupSortModification => 'Last modified: newest first';

  @override
  String get groupSortCreation => 'Created: oldest first';

  @override
  String get dbSettingsTitle => 'Database settings';

  @override
  String get dbSettingsTemplatesGroup => 'Entry templates group';

  @override
  String get dbSettingsTemplatesNone => 'None';

  @override
  String get dbSettingsName => 'Database name';

  @override
  String get dbSettingsRootGroupName => 'Root group name';

  @override
  String get dbSettingsDefaultUserName => 'Default user name';

  @override
  String get dbSettingsRecycleBin => 'Recycle Bin';

  @override
  String get dbSettingsHistoryMaxItems => 'Versions in an entry\'s history';

  @override
  String get dbSettingsHistoryMaxSize =>
      'Maximum size of an entry\'s history (MiB)';

  @override
  String get dbSettingsEmptyUnlimited => 'Empty: no limit';

  @override
  String dbSettingsEncryption(int version) {
    return 'Encryption (KDBX $version)';
  }

  @override
  String get dbSettingsCipher => 'Cipher';

  @override
  String get dbSettingsKdf => 'Key derivation';

  @override
  String get dbSettingsRounds => 'Transformation rounds';

  @override
  String get dbSettingsMemory => 'Memory (MiB)';

  @override
  String get dbSettingsIterations => 'Iterations';

  @override
  String get dbSettingsParallelism => 'Parallelism (threads)';

  @override
  String get dbSettingsMeasure => 'Measure the opening time';

  @override
  String dbSettingsMeasured(String seconds) {
    return 'Opening takes about $seconds s on this device.';
  }

  @override
  String dbSettingsRange(int min, int max) {
    return 'Enter a value from $min to $max.';
  }

  @override
  String get dbSettingsSaved => 'Database settings saved.';

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
  String get changeKeyTitle => 'Change master key';

  @override
  String get changeKeyNewPassword => 'New master password';

  @override
  String get changeKeyButton => 'Change key';

  @override
  String get changeKeyInProgress => 'Changing the key…';

  @override
  String get changeKeyInfo =>
      'After the change the database opens only with the new key.';

  @override
  String get changeKeyDone => 'Master key changed.';

  @override
  String get exportTitle => 'Export a copy';

  @override
  String exportDone(String name) {
    return 'Encrypted copy exported: $name';
  }

  @override
  String get entryEditTotpSetup => 'Set up TOTP';

  @override
  String get entryEditTotpUri => 'otpauth:// URI';

  @override
  String get entryEditTotpHint =>
      'Paste the otpauth:// address provided by the service (often shown next to the QR code). It replaces the entry\'s TOTP settings.';

  @override
  String get entryEditTotpInvalid => 'Invalid otpauth:// URI.';

  @override
  String get entryEditTotpApply => 'Apply';

  @override
  String get generatorSaveProfile => 'Save as profile';

  @override
  String get generatorRemoveProfile => 'Remove profile';

  @override
  String get generatorProfileName => 'Profile name';

  @override
  String get generatorProfileReserved =>
      'This name belongs to a built-in profile.';

  @override
  String get fileSelectNotPersistent =>
      'This file stays accessible only while the app is open: you will need to choose it again later.';

  @override
  String get deviceBlockedTitle => 'Device not secure';

  @override
  String get deviceBlockedBody =>
      'KeePassMobile cannot be used on rooted or jailbroken devices, or on devices configured in an insecure way (for example with developer options or USB debugging enabled). To protect your databases the app stays locked.';

  @override
  String get entryIcon => 'Icon';

  @override
  String get entryEditChooseIcon => 'Choose icon';

  @override
  String entryEditIconNumber(int number) {
    return 'Icon $number';
  }

  @override
  String get entryExpires => 'Expires';

  @override
  String entryExpiresOn(String date) {
    return 'Expires on $date';
  }

  @override
  String entryExpiredOn(String date) {
    return 'Expired on $date';
  }

  @override
  String get entryEditExpiryDate => 'Expiry date';

  @override
  String get entryTags => 'Tags';

  @override
  String get entryEditTagsHint => 'Separated by comma or semicolon';

  @override
  String get entryHistory => 'History';

  @override
  String entryHistoryVersion(String date) {
    return 'Version of $date';
  }

  @override
  String entryHistoryReadOnly(String version) {
    return '$version, read only.';
  }

  @override
  String get entryHistoryRestore => 'Restore';

  @override
  String get entryHistoryDelete => 'Delete version';

  @override
  String get entryHistoryRestoreConfirm =>
      'Restore this version? The current version stays in the history.';

  @override
  String get entryHistoryDeleteConfirm =>
      'Delete this version from the history? This cannot be undone.';

  @override
  String get entryHistoryUndated => 'Undated version';

  @override
  String get close => 'Close';

  @override
  String get entryAttachments => 'Attachments';

  @override
  String get entryEditAttachmentAdd => 'Add attachment';

  @override
  String get entryEditAttachmentRemove => 'Remove attachment';

  @override
  String get entryEditAttachmentUnreadable =>
      'The selected file could not be read.';

  @override
  String entryEditAttachmentTooLarge(String size) {
    return 'The file exceeds the maximum size of $size.';
  }

  @override
  String get entryEditAttachmentExistsTitle => 'Attachment already present';

  @override
  String entryEditAttachmentExists(String name) {
    return 'This entry already has an attachment named \"$name\". Replace it or keep both?';
  }

  @override
  String get entryEditAttachmentReplace => 'Replace';

  @override
  String get entryEditAttachmentRename => 'Keep both';

  @override
  String get entryAttachmentNoPreview =>
      'No preview available for this file type.';

  @override
  String entryAttachmentSave(String name) {
    return 'Save $name';
  }

  @override
  String entryAttachmentSaveWarning(String name) {
    return '\"$name\" will be saved unencrypted, without the database encryption: anyone with access to the file will be able to read it. Continue?';
  }

  @override
  String get entryAttachmentSaveConfirm => 'Save';

  @override
  String entryAttachmentSaved(String name) {
    return 'Attachment saved: $name';
  }

  @override
  String get entryAttachmentSaveFailed => 'The attachment could not be saved.';

  @override
  String get entryUrlOpen => 'Open in browser';

  @override
  String get entryUrlNotSupported =>
      'Only http and https addresses can be opened.';

  @override
  String get entryUrlNoApp => 'No app can open this address.';

  @override
  String get unlockBiometric => 'Unlock with biometrics';

  @override
  String get biometricPromptTitle => 'Unlock the database';

  @override
  String get biometricPromptCancel => 'Use password';

  @override
  String get biometricEnableTitle => 'Turn on biometric unlock';

  @override
  String get biometricUpdateTitle => 'Update biometric unlock';

  @override
  String get errorBiometricUnavailable =>
      'Biometrics unavailable: enrol a fingerprint or face and set a screen lock on the device.';

  @override
  String get errorBiometricFailed =>
      'Biometric unlock failed. Use the password.';

  @override
  String get errorBiometricInvalidated =>
      'Biometric unlock was turned off because the device biometrics changed. Unlock with the password and turn it on again in the database settings.';

  @override
  String get errorBiometricStale =>
      'The database was changed elsewhere or its key changed: unlock with the password and biometric unlock will be updated.';

  @override
  String get dbSettingsBiometric => 'Biometric unlock';

  @override
  String get dbSettingsBiometricInfo =>
      'Open this database with your fingerprint or face. Only the derived key is kept on the device, protected by biometrics.';

  @override
  String get dbSettingsKdfLocked =>
      'With biometric unlock the key derivation stays fixed. To change it, turn biometric unlock off, lock the database and open it again with the password.';

  @override
  String get errorSaveKdfLocked =>
      'The key derivation cannot be changed in this session: open the database with the password.';

  @override
  String get changeKeyDoneBiometricOff =>
      'Master key changed. Biometric unlock was turned off: turn it on again in the database settings.';

  @override
  String get biometricOfferTitle => 'Biometric unlock';

  @override
  String get biometricOfferBody =>
      'Open this database with your fingerprint or face? The derived key stays on this device, protected by biometrics. Choose “Never” to stop this offer for this database. You can turn it on from Settings → Database settings.';

  @override
  String get biometricOfferEnable => 'Turn on';

  @override
  String get biometricOfferNever => 'Never';

  @override
  String get biometricOfferEnabled => 'Biometric unlock turned on.';

  @override
  String get externalChangeTitle => 'File changed elsewhere';

  @override
  String externalChangeBody(String name) {
    return '\"$name\" was changed by another app or device after it was opened. Synchronize merges both versions; Overwrite replaces it with this version and the changes made elsewhere are lost.';
  }

  @override
  String get externalChangeSynchronize => 'Synchronize';

  @override
  String get externalChangeOverwrite => 'Overwrite';

  @override
  String get externalChangeCancel => 'Cancel';

  @override
  String get errorSaveExternalCanceled =>
      'Saving canceled: the file was changed elsewhere. Your changes were not saved.';

  @override
  String get errorSyncKeyMismatch =>
      'Cannot synchronize: the file changed elsewhere has a different master key. Nothing was written.';

  @override
  String get errorSyncNeedsPassword =>
      'Cannot synchronize without the password: lock the database and open it again with the master password. Nothing was written.';

  @override
  String get errorSyncDifferentDatabase =>
      'Cannot synchronize: the file was replaced with a different database. Nothing was written.';

  @override
  String get syncNow => 'Synchronize now';

  @override
  String get syncInProgress => 'Synchronizing…';

  @override
  String get syncUnchanged =>
      'The file has not changed: nothing to synchronize.';

  @override
  String get syncDone =>
      'Database synchronized with the changes made elsewhere.';

  @override
  String get remoteServerSftp => 'SFTP';

  @override
  String get remoteAddressHintSftp => 'sftp://server:22/folder/';

  @override
  String get sshUseKey => 'Use an SSH private key';

  @override
  String get sshPrivateKey => 'OpenSSH private key';

  @override
  String get sshChooseKey => 'Choose private key file';

  @override
  String get sshPassphrase => 'Private key passphrase';

  @override
  String get sshHostTitle => 'Verify SSH server';

  @override
  String sshHostBody(String server) {
    return 'First connection to $server. Compare this fingerprint with the one provided by the server administrator before accepting.';
  }

  @override
  String get errorSshHostChanged =>
      'The server SSH key has changed. Connection blocked. Verify the server with its administrator.';

  @override
  String get errorSshKey => 'Invalid private key or incorrect passphrase.';

  @override
  String get errorSftp =>
      'SFTP operation failed. Check permissions and server rename support.';

  @override
  String get errorRemoteConflict =>
      'The server file changed during saving. Nothing was written to the server. Synchronize and try again.';

  @override
  String get settingsRemoteCache => 'Local cache of remote databases';

  @override
  String get settingsRemoteCacheHint =>
      'Keep an encrypted KDBX copy excluded from backups. Turning this off does not delete changes awaiting upload.';

  @override
  String get settingsRemoteCacheClear => 'Delete synced local copies';

  @override
  String get settingsRemoteCacheClearConfirm =>
      'Changes awaiting upload will be kept. A server connection is needed to recreate the local copies.';

  @override
  String get settingsRemoteCacheClearDone => 'Synced copies cleanup complete.';

  @override
  String get settingsRemoteCacheClearIncomplete =>
      'Some copies could not be verified or changed during cleanup.';

  @override
  String get cacheOffline => 'Offline: using the encrypted local copy.';

  @override
  String get cachePending =>
      'Changes saved on this device, awaiting upload to the server.';

  @override
  String get cacheUnavailable =>
      'Local cache unavailable. An offline copy is not guaranteed.';

  @override
  String get cacheChanged =>
      'The local copy changed in another session. Reopen the database before synchronizing. No copy was overwritten.';

  @override
  String get unlockFromCache =>
      'Open the local copy without contacting the server';

  @override
  String get cacheSyncFailed =>
      'Synchronization failed. The local copy is preserved.';

  @override
  String get unlockChooseAgain => 'Choose the file again';

  @override
  String get groupCreate => 'New group';

  @override
  String get groupEdit => 'Edit group';

  @override
  String get iconImport => 'Import image';

  @override
  String get iconCustom => 'Custom icon';

  @override
  String get iconImportError => 'Unable to read the image.';

  @override
  String get databasesClose => 'Close database';

  @override
  String get databasesMove => 'Move to another database';

  @override
  String get databasesMoveIncomplete =>
      'Copy saved, but the original could not be removed.';

  @override
  String get databasesCopy => 'Copy to another database';

  @override
  String get linkedDatabaseFailure =>
      'Unable to open a linked database. For a server, open it manually first and save the credentials.';

  @override
  String get linkedDatabaseAdd => 'Add linked database';

  @override
  String get linkedDatabaseAddHint =>
      'Links another open database so it unlocks automatically with this one.';

  @override
  String get linkedDatabasePassword =>
      'Linked database password (stored in this database)';

  @override
  String get linkedDatabaseDeviceWarning =>
      'This link contains device-specific rules. Allowing it enables it on this device.';

  @override
  String get linkedDatabaseTitle => 'Open linked database?';

  @override
  String linkedDatabaseBody(String database, String keyFile) {
    return 'Allow access to $database? Key file: $keyFile. Approval is remembered for this link.';
  }

  @override
  String get linkedDatabaseAllow => 'Allow';

  @override
  String get databasesTitle => 'Open databases';

  @override
  String get databasesOpenAnother => 'Open another database';

  @override
  String get searchGoToGroup => 'Go to group';

  @override
  String get groupName => 'Group name';

  @override
  String get groupNameRequired => 'Enter a group name.';

  @override
  String get groupDelete => 'Delete group';

  @override
  String get groupDeleteToBin =>
      'Move this group and all its contents to the recycle bin?';

  @override
  String get groupDeletePermanent =>
      'Permanently delete this group and all its contents? This cannot be undone.';

  @override
  String get itemMoveTitle => 'Move';

  @override
  String get itemNoDestination => 'No destination group is available.';

  @override
  String get itemRestore => 'Restore';

  @override
  String get itemDuplicate => 'Duplicate';

  @override
  String get itemDuplicateSuffix => 'copy';

  @override
  String get errorItemOperation =>
      'This operation is not allowed for the item or destination group.';

  @override
  String get errorFieldReference => 'Unable to resolve the field reference.';

  @override
  String get searchOptions => 'Search options';

  @override
  String get searchFieldTitle => 'Title';

  @override
  String get searchFieldUserName => 'User name';

  @override
  String get searchFieldUrl => 'URL';

  @override
  String get searchFieldPassword => 'Password';

  @override
  String get searchFieldNotes => 'Notes';

  @override
  String get searchFieldOther => 'Other fields';

  @override
  String get searchFieldTags => 'Tags';

  @override
  String get searchFieldGroup => 'Group name';

  @override
  String get searchCaseSensitive => 'Case sensitive';

  @override
  String get searchExcludeExpired => 'Exclude expired entries';

  @override
  String get searchRegex => 'Regular expression';

  @override
  String get searchRegexError => 'Invalid expression or search timed out.';

  @override
  String get searchRegexSubmit => 'Submit the search to run the expression.';

  @override
  String get autofillSaveTitle => 'Save credentials';

  @override
  String get autofillSaveDescription =>
      'Create a new entry after reviewing these details.';

  @override
  String get autofillSaveTarget => 'Website or app';

  @override
  String get autofillSaveUser => 'Username';

  @override
  String get autofillSaveDatabase => 'Database';

  @override
  String get autofillSavePassword => 'Password';

  @override
  String get autofillSaveConfirm => 'Create entry';

  @override
  String get autofillSaveRetry =>
      'Close this screen and submit the login again to retry.';

  @override
  String get groupAddTitle => 'Add';

  @override
  String get templatesInstall => 'Add default templates';

  @override
  String get templatesInstallHint =>
      'Creates a Templates group with ready-made examples for cards, Wi-Fi, and IDs.';

  @override
  String get templateShowAllFields => 'Show all fields';

  @override
  String get templatesInstallConfirm =>
      'Add missing default templates to the database?';

  @override
  String get templatesInstallSuccess => 'Default templates are ready to use.';

  @override
  String get templateGroup => 'Templates';

  @override
  String get templateIdCard => 'ID card';

  @override
  String get templateWlan => 'Wireless LAN';

  @override
  String get templateNote => 'Secure note';

  @override
  String get templateCreditCard => 'Credit card';

  @override
  String get templateMembership => 'Membership';

  @override
  String get templateNumber => 'Number';

  @override
  String get templateName => 'Name';

  @override
  String get templatePlace => 'Place of issue';

  @override
  String get templateIssueDate => 'Date of issue';

  @override
  String get templateHolder => 'Card holder';

  @override
  String get entryTemplateEmpty => 'New entry';

  @override
  String get settingsExpireTan => 'Expire TAN entries when opened';

  @override
  String get settingsExpireTanHint =>
      'Mark a TAN as used when its details are opened.';

  @override
  String get entryEditTotpScan => 'Scan QR code';

  @override
  String get entryEditTotpScanError =>
      'Camera unavailable. Check permissions and try again.';

  @override
  String get entryColor => 'Color';

  @override
  String get entryColorNone => 'None';

  @override
  String entryColorIndicator(String color) {
    return 'Color: $color';
  }

  @override
  String get entryColorRed => 'Red';

  @override
  String get entryColorOrange => 'Orange';

  @override
  String get entryColorYellow => 'Yellow';

  @override
  String get entryColorGreen => 'Green';

  @override
  String get entryColorTeal => 'Teal';

  @override
  String get entryColorBlue => 'Blue';

  @override
  String get entryColorPurple => 'Purple';

  @override
  String get entryColorPink => 'Pink';

  @override
  String get entryColorBrown => 'Brown';

  @override
  String get entryColorGray => 'Gray';

  @override
  String get settingsLockInBackground => 'Lock in background';

  @override
  String get settingsLockInBackgroundHint =>
      'Lock the database when you switch to another app, except for system activities opened by the app.';

  @override
  String get generatorSaveAsEntry => 'Save as new entry';

  @override
  String get generatorChooseGroup => 'Choose destination group';

  @override
  String get checkAllGood => 'All clear';

  @override
  String get checkImprove => 'Room for improvement';

  @override
  String get checkAttention => 'Attention needed';

  @override
  String get checkEmpty => 'No passwords to analyze';

  @override
  String checkSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count passwords analyzed',
      one: '1 password analyzed',
    );
    return '$_temp0. Checked locally, only in memory.';
  }

  @override
  String get checkDuplicates => 'Duplicates';

  @override
  String get checkWeak => 'Weak';

  @override
  String get checkOtherProtected => 'Other protected fields';

  @override
  String checkExclusions(String references) {
    return 'Excluded: Recycle Bin entries, Templates, empty fields, TOTP and references $references.';
  }

  @override
  String checkSharedCount(int count) {
    return 'Shared by $count entries';
  }

  @override
  String get checkVeryWeak => 'Very weak';

  @override
  String get checkWeakLevel => 'Weak';

  @override
  String get checkTooShort => 'Too short';

  @override
  String get checkDigitsOnly => 'Digits only';

  @override
  String get checkLowVariety => 'Low variety or repetition';

  @override
  String get checkCommonPattern => 'Common pattern or word';

  @override
  String get checkLimitedComplexity => 'Limited complexity';

  @override
  String get checkProtectedExplanation =>
      'PINs, CVVs and secondary codes often have lengths or numeric formats required by the service. Update them only where longer or unique values are allowed.';

  @override
  String get checkReused => 'Reused value';

  @override
  String get changeKeyCurrentPassword => 'Current master password';

  @override
  String get changeKeyCurrentRequired => 'Enter the current password.';

  @override
  String get changeKeyWrongCurrentPassword => 'Current password is incorrect.';

  @override
  String get autofillNoFillableFields =>
      'This entry has no values for the fields requested by the app or website. Add a username or password, then try again.';

  @override
  String get dialogSaveUnencryptedTitle => 'Save unencrypted';

  @override
  String get dialogRestoreVersionTitle => 'Restore version';

  @override
  String get dialogDeleteVersionTitle => 'Delete version';

  @override
  String get dialogDiscardBody =>
      'If you leave without saving, your changes will be lost.';

  @override
  String get dialogGroupBody => 'Choose the group name and icon.';

  @override
  String get dialogLinkedDatabaseBody =>
      'Choose the database to link and enter its password.';

  @override
  String get dialogRemoteCredentialsBody =>
      'Enter your credentials to connect to the server.';

  @override
  String get dialogProfileBody => 'Choose a name to save these options.';

  @override
  String get dialogFill => 'Fill';

  @override
  String get dialogAdd => 'Add';
}
