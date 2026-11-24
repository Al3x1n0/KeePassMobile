import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  /// No description provided for @generateKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Generate a key file'**
  String get generateKeyFile;

  /// No description provided for @errorCreateKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Could not save and verify the key file.'**
  String get errorCreateKeyFile;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'KeePassMobile'**
  String get appTitle;

  /// No description provided for @navigationHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navigationHome;

  /// No description provided for @navigationGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get navigationGenerate;

  /// No description provided for @navigationCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get navigationCheck;

  /// No description provided for @demoDatabaseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Demo database · Password: demo1234'**
  String get demoDatabaseSubtitle;

  /// No description provided for @demoDatabasePassword.
  ///
  /// In en, this message translates to:
  /// **'Demo password: demo1234'**
  String get demoDatabasePassword;

  /// No description provided for @demoDatabaseRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove demo database'**
  String get demoDatabaseRemoveTitle;

  /// No description provided for @demoDatabaseRemoveMessage.
  ///
  /// In en, this message translates to:
  /// **'Confirm removing the example database? Once removed, it cannot be restored.'**
  String get demoDatabaseRemoveMessage;

  /// No description provided for @demoDatabaseRemoveWithRecents.
  ///
  /// In en, this message translates to:
  /// **'Turning off \"Remember recent files\" will also remove the example database, which cannot be restored. Confirm continuing?'**
  String get demoDatabaseRemoveWithRecents;

  /// No description provided for @demoDatabaseRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get demoDatabaseRemoveConfirm;

  /// No description provided for @fileSelectTitle.
  ///
  /// In en, this message translates to:
  /// **'Open database'**
  String get fileSelectTitle;

  /// No description provided for @fileSelectOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open file'**
  String get fileSelectOpenFile;

  /// No description provided for @fileSelectNewDatabase.
  ///
  /// In en, this message translates to:
  /// **'New DB'**
  String get fileSelectNewDatabase;

  /// No description provided for @fileSelectRecentFiles.
  ///
  /// In en, this message translates to:
  /// **'Recent files'**
  String get fileSelectRecentFiles;

  /// No description provided for @fileSelectNoRecent.
  ///
  /// In en, this message translates to:
  /// **'No recent files. Open a KeePass database (.kdbx) to start.'**
  String get fileSelectNoRecent;

  /// No description provided for @fileSelectRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from recent files'**
  String get fileSelectRemove;

  /// No description provided for @remoteOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Open from server'**
  String get remoteOpenTitle;

  /// No description provided for @remoteServerType.
  ///
  /// In en, this message translates to:
  /// **'Server type'**
  String get remoteServerType;

  /// No description provided for @remoteServerWebDav.
  ///
  /// In en, this message translates to:
  /// **'WebDAV'**
  String get remoteServerWebDav;

  /// No description provided for @remoteServerNextcloud.
  ///
  /// In en, this message translates to:
  /// **'Nextcloud'**
  String get remoteServerNextcloud;

  /// No description provided for @remoteServerOwnCloud.
  ///
  /// In en, this message translates to:
  /// **'ownCloud'**
  String get remoteServerOwnCloud;

  /// No description provided for @remoteAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get remoteAddress;

  /// No description provided for @remoteAddressHintWebDav.
  ///
  /// In en, this message translates to:
  /// **'https://server/folder/'**
  String get remoteAddressHintWebDav;

  /// No description provided for @remoteAddressHintCloud.
  ///
  /// In en, this message translates to:
  /// **'https://server'**
  String get remoteAddressHintCloud;

  /// No description provided for @remoteUserName.
  ///
  /// In en, this message translates to:
  /// **'User name'**
  String get remoteUserName;

  /// No description provided for @remotePassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get remotePassword;

  /// No description provided for @remoteRemember.
  ///
  /// In en, this message translates to:
  /// **'Remember the credentials'**
  String get remoteRemember;

  /// No description provided for @remoteRememberHint.
  ///
  /// In en, this message translates to:
  /// **'Saved in the device\'s secure storage. Otherwise they are asked every time the file is opened.'**
  String get remoteRememberHint;

  /// No description provided for @remoteConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get remoteConnect;

  /// No description provided for @remoteUp.
  ///
  /// In en, this message translates to:
  /// **'Parent folder'**
  String get remoteUp;

  /// No description provided for @remoteEmptyFolder.
  ///
  /// In en, this message translates to:
  /// **'Empty folder'**
  String get remoteEmptyFolder;

  /// No description provided for @remoteCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get remoteCancel;

  /// No description provided for @remoteSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get remoteSignIn;

  /// No description provided for @remoteCredentialsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {server}'**
  String remoteCredentialsTitle(String server);

  /// No description provided for @remoteCredentialsFailed.
  ///
  /// In en, this message translates to:
  /// **'The server rejected the user name or password.'**
  String get remoteCredentialsFailed;

  /// No description provided for @remoteCertificateTitle.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized certificate'**
  String get remoteCertificateTitle;

  /// No description provided for @remoteCertificateBody.
  ///
  /// In en, this message translates to:
  /// **'The certificate of {server} is not recognized by the system. Accept it only if this SHA-256 fingerprint is the one of your server:'**
  String remoteCertificateBody(String server);

  /// No description provided for @remoteCertificateAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get remoteCertificateAccept;

  /// No description provided for @errorRemoteAuth.
  ///
  /// In en, this message translates to:
  /// **'The server rejected the user name or password.'**
  String get errorRemoteAuth;

  /// No description provided for @errorRemoteUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Server unreachable. Check the connection and the address.'**
  String get errorRemoteUnreachable;

  /// No description provided for @errorRemoteNotFound.
  ///
  /// In en, this message translates to:
  /// **'File or folder not found on the server.'**
  String get errorRemoteNotFound;

  /// No description provided for @errorRemoteServer.
  ///
  /// In en, this message translates to:
  /// **'The server replied with an error ({status}).'**
  String errorRemoteServer(int status);

  /// No description provided for @errorRemoteInsecure.
  ///
  /// In en, this message translates to:
  /// **'Use an https:// address: the connection must be encrypted.'**
  String get errorRemoteInsecure;

  /// No description provided for @errorRemoteCanceled.
  ///
  /// In en, this message translates to:
  /// **'Access to the server canceled.'**
  String get errorRemoteCanceled;

  /// No description provided for @errorRemoteAddress.
  ///
  /// In en, this message translates to:
  /// **'Invalid address.'**
  String get errorRemoteAddress;

  /// No description provided for @unlockPassword.
  ///
  /// In en, this message translates to:
  /// **'Master password'**
  String get unlockPassword;

  /// No description provided for @unlockShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get unlockShowPassword;

  /// No description provided for @unlockHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get unlockHidePassword;

  /// No description provided for @unlockKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Key file'**
  String get unlockKeyFile;

  /// No description provided for @unlockNoKeyFile.
  ///
  /// In en, this message translates to:
  /// **'No key file'**
  String get unlockNoKeyFile;

  /// No description provided for @unlockChooseKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Choose key file'**
  String get unlockChooseKeyFile;

  /// No description provided for @unlockRemoveKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Remove key file'**
  String get unlockRemoveKeyFile;

  /// No description provided for @unlockButton.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockButton;

  /// No description provided for @unlockInProgress.
  ///
  /// In en, this message translates to:
  /// **'Unlocking…'**
  String get unlockInProgress;

  /// No description provided for @errorInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Wrong password or key file.'**
  String get errorInvalidCredentials;

  /// No description provided for @errorFileCorrupted.
  ///
  /// In en, this message translates to:
  /// **'The file is damaged or is not a KeePass database.'**
  String get errorFileCorrupted;

  /// No description provided for @errorUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Unsupported database format or algorithm.'**
  String get errorUnsupported;

  /// No description provided for @errorFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file exceeds the 128 MiB size limit.'**
  String get errorFileTooLarge;

  /// No description provided for @errorDatabasePayloadTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The database exceeds the size limit after decompression.'**
  String get errorDatabasePayloadTooLarge;

  /// No description provided for @errorDatabaseKdfTooCostly.
  ///
  /// In en, this message translates to:
  /// **'The key derivation settings exceed the supported memory or computation limits.'**
  String get errorDatabaseKdfTooCostly;

  /// No description provided for @errorKeyFileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The key file could not be read. Choose it again.'**
  String get errorKeyFileUnavailable;

  /// No description provided for @errorFileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The database could not be read. Open the file again.'**
  String get errorFileUnavailable;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'The database could not be opened.'**
  String get errorGeneric;

  /// No description provided for @groupLock.
  ///
  /// In en, this message translates to:
  /// **'Lock database'**
  String get groupLock;

  /// No description provided for @groupEmpty.
  ///
  /// In en, this message translates to:
  /// **'This group is empty.'**
  String get groupEmpty;

  /// No description provided for @entryUntitled.
  ///
  /// In en, this message translates to:
  /// **'(no title)'**
  String get entryUntitled;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search entries'**
  String get searchHint;

  /// No description provided for @searchClear.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get searchClear;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No entries found.'**
  String get searchNoResults;

  /// No description provided for @favoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesTitle;

  /// No description provided for @recentPasswordsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent passwords'**
  String get recentPasswordsTitle;

  /// No description provided for @settingsRecentPasswordsHint.
  ///
  /// In en, this message translates to:
  /// **'Show entries on Home when you copy a field or an OTP code from them.'**
  String get settingsRecentPasswordsHint;

  /// No description provided for @settingsRecentPasswordLimit.
  ///
  /// In en, this message translates to:
  /// **'Number of recent passwords'**
  String get settingsRecentPasswordLimit;

  /// No description provided for @favoritesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No favorite entries.'**
  String get favoritesEmpty;

  /// No description provided for @entryFavoriteAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get entryFavoriteAdd;

  /// No description provided for @entryFavoriteRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get entryFavoriteRemove;

  /// No description provided for @groupAddEntry.
  ///
  /// In en, this message translates to:
  /// **'Add entry or group'**
  String get groupAddEntry;

  /// No description provided for @entryTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get entryTitle;

  /// No description provided for @entryUserName.
  ///
  /// In en, this message translates to:
  /// **'User name'**
  String get entryUserName;

  /// No description provided for @entryPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get entryPassword;

  /// No description provided for @entryUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get entryUrl;

  /// No description provided for @entryOverrideUrl.
  ///
  /// In en, this message translates to:
  /// **'Override URL'**
  String get entryOverrideUrl;

  /// No description provided for @entryNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get entryNotes;

  /// No description provided for @entryCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy {field}'**
  String entryCopy(String field);

  /// No description provided for @entryShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get entryShow;

  /// No description provided for @entryHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get entryHide;

  /// No description provided for @entryHiddenValue.
  ///
  /// In en, this message translates to:
  /// **'Hidden value'**
  String get entryHiddenValue;

  /// No description provided for @entryCopied.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Copied. The clipboard will be cleared in 1 second.} other{Copied. The clipboard will be cleared in {seconds} seconds.}}'**
  String entryCopied(int seconds);

  /// No description provided for @entryEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get entryEdit;

  /// No description provided for @entryDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get entryDelete;

  /// No description provided for @itemsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String itemsSelected(int count);

  /// No description provided for @itemsSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get itemsSelectAll;

  /// No description provided for @itemsSelectAllShort.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get itemsSelectAllShort;

  /// No description provided for @itemsDeleteRecycle.
  ///
  /// In en, this message translates to:
  /// **'Move the selected items and their contents to the recycle bin?'**
  String get itemsDeleteRecycle;

  /// No description provided for @itemsDeletePermanent.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete the selected items and their contents? This cannot be undone.'**
  String get itemsDeletePermanent;

  /// No description provided for @entryDeleteConfirmRecycle.
  ///
  /// In en, this message translates to:
  /// **'Move this entry to the recycle bin?'**
  String get entryDeleteConfirmRecycle;

  /// No description provided for @entryDeleteConfirmPermanent.
  ///
  /// In en, this message translates to:
  /// **'Delete this entry permanently? This cannot be undone.'**
  String get entryDeleteConfirmPermanent;

  /// No description provided for @entryEditTitleNew.
  ///
  /// In en, this message translates to:
  /// **'New entry'**
  String get entryEditTitleNew;

  /// No description provided for @entryEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit entry'**
  String get entryEditTitle;

  /// No description provided for @entryEditSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get entryEditSave;

  /// No description provided for @entryEditAddField.
  ///
  /// In en, this message translates to:
  /// **'Add field'**
  String get entryEditAddField;

  /// No description provided for @entryEditFieldName.
  ///
  /// In en, this message translates to:
  /// **'Field name'**
  String get entryEditFieldName;

  /// No description provided for @entryEditFieldValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get entryEditFieldValue;

  /// No description provided for @entryEditFieldProtected.
  ///
  /// In en, this message translates to:
  /// **'Protected'**
  String get entryEditFieldProtected;

  /// No description provided for @entryEditRemoveField.
  ///
  /// In en, this message translates to:
  /// **'Remove field'**
  String get entryEditRemoveField;

  /// No description provided for @entryEditFieldNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get entryEditFieldNameRequired;

  /// No description provided for @entryEditFieldNameDuplicate.
  ///
  /// In en, this message translates to:
  /// **'This name is already used'**
  String get entryEditFieldNameDuplicate;

  /// No description provided for @entryEditFieldNameReserved.
  ///
  /// In en, this message translates to:
  /// **'This name is reserved for a standard field'**
  String get entryEditFieldNameReserved;

  /// No description provided for @entryEditDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard your changes?'**
  String get entryEditDiscardTitle;

  /// No description provided for @entryEditDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get entryEditDiscard;

  /// No description provided for @entryEditKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get entryEditKeepEditing;

  /// No description provided for @errorSaveUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cannot save: the file can no longer be reached. Your changes were not saved.'**
  String get errorSaveUnavailable;

  /// No description provided for @errorSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Saving failed. Your changes were not saved.'**
  String get errorSaveFailed;

  /// No description provided for @errorSaveBusy.
  ///
  /// In en, this message translates to:
  /// **'A save is already in progress.'**
  String get errorSaveBusy;

  /// No description provided for @errorSaveLocked.
  ///
  /// In en, this message translates to:
  /// **'The database has been locked.'**
  String get errorSaveLocked;

  /// No description provided for @entryEditGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate password'**
  String get entryEditGenerate;

  /// No description provided for @entryTotp.
  ///
  /// In en, this message translates to:
  /// **'TOTP'**
  String get entryTotp;

  /// No description provided for @entryTotpRemaining.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String entryTotpRemaining(int seconds);

  /// No description provided for @entryTotpInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid TOTP settings.'**
  String get entryTotpInvalid;

  /// No description provided for @generatorTitle.
  ///
  /// In en, this message translates to:
  /// **'Password generator'**
  String get generatorTitle;

  /// No description provided for @generatorUse.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get generatorUse;

  /// No description provided for @generatorRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate again'**
  String get generatorRegenerate;

  /// No description provided for @generatorEntropy.
  ///
  /// In en, this message translates to:
  /// **'{bits} bits of entropy'**
  String generatorEntropy(int bits);

  /// No description provided for @generatorInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one character type or a number of words.'**
  String get generatorInvalid;

  /// No description provided for @generatorProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get generatorProfile;

  /// No description provided for @generatorProfileCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get generatorProfileCustom;

  /// No description provided for @generatorCharacters.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get generatorCharacters;

  /// No description provided for @generatorLength.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get generatorLength;

  /// No description provided for @generatorUpperCase.
  ///
  /// In en, this message translates to:
  /// **'Upper case (A-Z)'**
  String get generatorUpperCase;

  /// No description provided for @generatorLowerCase.
  ///
  /// In en, this message translates to:
  /// **'Lower case (a-z)'**
  String get generatorLowerCase;

  /// No description provided for @generatorDigits.
  ///
  /// In en, this message translates to:
  /// **'Digits (0-9)'**
  String get generatorDigits;

  /// No description provided for @generatorMinus.
  ///
  /// In en, this message translates to:
  /// **'Minus (-)'**
  String get generatorMinus;

  /// No description provided for @generatorUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline (_)'**
  String get generatorUnderline;

  /// No description provided for @generatorSpace.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get generatorSpace;

  /// No description provided for @generatorSpecials.
  ///
  /// In en, this message translates to:
  /// **'Special (!, \$, %, &, …)'**
  String get generatorSpecials;

  /// No description provided for @generatorSpecialsExtended.
  ///
  /// In en, this message translates to:
  /// **'Extended special (§, ©, ®, …)'**
  String get generatorSpecialsExtended;

  /// No description provided for @generatorBrackets.
  ///
  /// In en, this message translates to:
  /// **'Brackets ({chars})'**
  String generatorBrackets(String chars);

  /// No description provided for @generatorExcludeLookAlike.
  ///
  /// In en, this message translates to:
  /// **'Exclude look-alike characters ({chars})'**
  String generatorExcludeLookAlike(String chars);

  /// No description provided for @generatorAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'At least one character from each group'**
  String get generatorAtLeastOne;

  /// No description provided for @generatorPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get generatorPassphrase;

  /// No description provided for @generatorWordCount.
  ///
  /// In en, this message translates to:
  /// **'Number of words'**
  String get generatorWordCount;

  /// No description provided for @generatorSeparator.
  ///
  /// In en, this message translates to:
  /// **'Separator'**
  String get generatorSeparator;

  /// No description provided for @generatorCaseLower.
  ///
  /// In en, this message translates to:
  /// **'lower'**
  String get generatorCaseLower;

  /// No description provided for @generatorCaseUpper.
  ///
  /// In en, this message translates to:
  /// **'UPPER'**
  String get generatorCaseUpper;

  /// No description provided for @generatorCasePascal.
  ///
  /// In en, this message translates to:
  /// **'Capitalized'**
  String get generatorCasePascal;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get settingsDatabase;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// No description provided for @settingsDisplay.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsDisplay;

  /// No description provided for @settingsFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get settingsFiles;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsAppVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get settingsAppVersion;

  /// No description provided for @settingsClipboardTimeout.
  ///
  /// In en, this message translates to:
  /// **'Clear clipboard after'**
  String get settingsClipboardTimeout;

  /// No description provided for @settingsLockTimeout.
  ///
  /// In en, this message translates to:
  /// **'Lock after inactivity'**
  String get settingsLockTimeout;

  /// No description provided for @settingsLockNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get settingsLockNever;

  /// No description provided for @settingsSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{1 second} other{{seconds} seconds}}'**
  String settingsSeconds(int seconds);

  /// No description provided for @settingsMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 minute} other{{minutes} minutes}}'**
  String settingsMinutes(int minutes);

  /// No description provided for @settingsLockOnScreenOff.
  ///
  /// In en, this message translates to:
  /// **'Lock when the screen turns off'**
  String get settingsLockOnScreenOff;

  /// No description provided for @settingsLockOnScreenOffHint.
  ///
  /// In en, this message translates to:
  /// **'On iOS the database locks when the device locks, only if a passcode is set.'**
  String get settingsLockOnScreenOffHint;

  /// No description provided for @settingsSecureScreen.
  ///
  /// In en, this message translates to:
  /// **'Secure screen'**
  String get settingsSecureScreen;

  /// No description provided for @screenProtectionWarning.
  ///
  /// In en, this message translates to:
  /// **'Screen protection could not be applied. Continuing may allow screenshots or screen recordings to capture your database.'**
  String get screenProtectionWarning;

  /// No description provided for @screenProtectionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue with this risk'**
  String get screenProtectionContinue;

  /// No description provided for @settingsSecureScreenHint.
  ///
  /// In en, this message translates to:
  /// **'Blocks screenshots and screen recordings and hides the preview in recent apps.'**
  String get settingsSecureScreenHint;

  /// No description provided for @settingsOpenNotification.
  ///
  /// In en, this message translates to:
  /// **'Open database notification'**
  String get settingsOpenNotification;

  /// No description provided for @settingsOpenNotificationHint.
  ///
  /// In en, this message translates to:
  /// **'While a database is open, shows a notification with the Lock action.'**
  String get settingsOpenNotificationHint;

  /// No description provided for @settingsAutofill.
  ///
  /// In en, this message translates to:
  /// **'Autofill'**
  String get settingsAutofill;

  /// No description provided for @settingsAutofillOn.
  ///
  /// In en, this message translates to:
  /// **'KeePassMobile is the autofill service'**
  String get settingsAutofillOn;

  /// No description provided for @settingsAutofillOff.
  ///
  /// In en, this message translates to:
  /// **'Tap to choose KeePassMobile in the system settings'**
  String get settingsAutofillOff;

  /// No description provided for @autofillChooseDatabase.
  ///
  /// In en, this message translates to:
  /// **'Choose the database'**
  String get autofillChooseDatabase;

  /// No description provided for @autofillNoRecentFiles.
  ///
  /// In en, this message translates to:
  /// **'No recent databases. Open the database in KeePassMobile first.'**
  String get autofillNoRecentFiles;

  /// No description provided for @autofillClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get autofillClose;

  /// No description provided for @autofillPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the entry'**
  String get autofillPickTitle;

  /// No description provided for @autofillFor.
  ///
  /// In en, this message translates to:
  /// **'For {target}'**
  String autofillFor(String target);

  /// No description provided for @autofillMatches.
  ///
  /// In en, this message translates to:
  /// **'Entries for this app or site'**
  String get autofillMatches;

  /// No description provided for @autofillSiteInApp.
  ///
  /// In en, this message translates to:
  /// **'{domain} in {app}'**
  String autofillSiteInApp(String domain, String app);

  /// No description provided for @autofillApproximateTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm the recipient'**
  String get autofillApproximateTitle;

  /// No description provided for @autofillApproximateBody.
  ///
  /// In en, this message translates to:
  /// **'“{entry}” matched only by a related domain or search text. Fill its credentials in {target}?'**
  String autofillApproximateBody(String entry, String target);

  /// No description provided for @autofillAppIdentityWarning.
  ///
  /// In en, this message translates to:
  /// **'“{entry}” is linked to {app}. Confirm that you recognize this installed app before filling its credentials.'**
  String autofillAppIdentityWarning(String entry, String app);

  /// No description provided for @autofillFillAndRememberApp.
  ///
  /// In en, this message translates to:
  /// **'Fill and remember app'**
  String get autofillFillAndRememberApp;

  /// No description provided for @autofillSaveAndRememberApp.
  ///
  /// In en, this message translates to:
  /// **'Create entry and remember app'**
  String get autofillSaveAndRememberApp;

  /// No description provided for @autofillRememberAppSignature.
  ///
  /// In en, this message translates to:
  /// **'Remembering this app saves its signing certificate on this device for future fills of entries linked to it.'**
  String get autofillRememberAppSignature;

  /// No description provided for @autofillNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No entries found: search the database below.'**
  String get autofillNoMatches;

  /// No description provided for @autofillSearchAll.
  ///
  /// In en, this message translates to:
  /// **'Search the database'**
  String get autofillSearchAll;

  /// No description provided for @autofillSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get autofillSearchHint;

  /// No description provided for @autofillDomainWarning.
  ///
  /// In en, this message translates to:
  /// **'The app {app} says it shows the site {domain}. Another app could claim it to obtain the site\'s credentials: use the site\'s entries only if you trust the app.'**
  String autofillDomainWarning(String app, String domain);

  /// No description provided for @autofillUseDomainOnce.
  ///
  /// In en, this message translates to:
  /// **'Use the site this time'**
  String get autofillUseDomainOnce;

  /// No description provided for @autofillUseDomainAlways.
  ///
  /// In en, this message translates to:
  /// **'Always use the site in this app'**
  String get autofillUseDomainAlways;

  /// No description provided for @autofillRememberTitle.
  ///
  /// In en, this message translates to:
  /// **'Remember the entry?'**
  String get autofillRememberTitle;

  /// No description provided for @autofillRememberBody.
  ///
  /// In en, this message translates to:
  /// **'Next time {target} asks, “{entry}” is suggested right away. The field {field} is added to the entry and the database is saved.'**
  String autofillRememberBody(String target, String entry, String field);

  /// No description provided for @autofillFillOnly.
  ///
  /// In en, this message translates to:
  /// **'Fill only'**
  String get autofillFillOnly;

  /// No description provided for @autofillFillAndRemember.
  ///
  /// In en, this message translates to:
  /// **'Fill and remember'**
  String get autofillFillAndRemember;

  /// No description provided for @openNotificationChannel.
  ///
  /// In en, this message translates to:
  /// **'Open database'**
  String get openNotificationChannel;

  /// No description provided for @openNotificationText.
  ///
  /// In en, this message translates to:
  /// **'Database open'**
  String get openNotificationText;

  /// No description provided for @openNotificationLock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get openNotificationLock;

  /// No description provided for @settingsMaskPassword.
  ///
  /// In en, this message translates to:
  /// **'Hide passwords'**
  String get settingsMaskPassword;

  /// No description provided for @settingsMaskTotp.
  ///
  /// In en, this message translates to:
  /// **'Hide TOTP codes'**
  String get settingsMaskTotp;

  /// No description provided for @settingsShowGroupNameInSearch.
  ///
  /// In en, this message translates to:
  /// **'Show group name in search results'**
  String get settingsShowGroupNameInSearch;

  /// No description provided for @settingsShowGroupInEntry.
  ///
  /// In en, this message translates to:
  /// **'Show group in entry details'**
  String get settingsShowGroupInEntry;

  /// No description provided for @settingsListTextSize.
  ///
  /// In en, this message translates to:
  /// **'List text size'**
  String get settingsListTextSize;

  /// No description provided for @settingsSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get settingsSizeSmall;

  /// No description provided for @settingsSizeMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get settingsSizeMedium;

  /// No description provided for @settingsSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get settingsSizeLarge;

  /// No description provided for @entryGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get entryGroup;

  /// No description provided for @entryCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get entryCreated;

  /// No description provided for @entryModified.
  ///
  /// In en, this message translates to:
  /// **'Last modified'**
  String get entryModified;

  /// No description provided for @settingsShowUserName.
  ///
  /// In en, this message translates to:
  /// **'Show user name in lists'**
  String get settingsShowUserName;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsRememberRecentFiles.
  ///
  /// In en, this message translates to:
  /// **'Remember recent files'**
  String get settingsRememberRecentFiles;

  /// No description provided for @settingsRememberKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Remember key file'**
  String get settingsRememberKeyFile;

  /// No description provided for @createDatabaseTitle.
  ///
  /// In en, this message translates to:
  /// **'New database'**
  String get createDatabaseTitle;

  /// No description provided for @createDatabaseConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get createDatabaseConfirm;

  /// No description provided for @createDatabaseButton.
  ///
  /// In en, this message translates to:
  /// **'Create database'**
  String get createDatabaseButton;

  /// No description provided for @createDatabaseInProgress.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get createDatabaseInProgress;

  /// No description provided for @createDatabaseKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a password or choose a key file.'**
  String get createDatabaseKeyRequired;

  /// No description provided for @createDatabaseMismatch.
  ///
  /// In en, this message translates to:
  /// **'The passwords do not match.'**
  String get createDatabaseMismatch;

  /// No description provided for @createDatabaseInfo.
  ///
  /// In en, this message translates to:
  /// **'The database uses KDBX 4, AES-256 and Argon2id (64 MiB). Next, choose where to save it.'**
  String get createDatabaseInfo;

  /// No description provided for @errorCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'The database could not be created. No file was opened.'**
  String get errorCreateFailed;

  /// No description provided for @groupMore.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get groupMore;

  /// No description provided for @groupSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get groupSort;

  /// No description provided for @groupSortAscending.
  ///
  /// In en, this message translates to:
  /// **'Name: A–Z'**
  String get groupSortAscending;

  /// No description provided for @groupSortDescending.
  ///
  /// In en, this message translates to:
  /// **'Name: Z–A'**
  String get groupSortDescending;

  /// No description provided for @groupSortDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database order'**
  String get groupSortDatabase;

  /// No description provided for @groupSortModification.
  ///
  /// In en, this message translates to:
  /// **'Last modified: newest first'**
  String get groupSortModification;

  /// No description provided for @groupSortCreation.
  ///
  /// In en, this message translates to:
  /// **'Created: oldest first'**
  String get groupSortCreation;

  /// No description provided for @dbSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Database settings'**
  String get dbSettingsTitle;

  /// No description provided for @dbSettingsTemplatesGroup.
  ///
  /// In en, this message translates to:
  /// **'Entry templates group'**
  String get dbSettingsTemplatesGroup;

  /// No description provided for @dbSettingsTemplatesNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get dbSettingsTemplatesNone;

  /// No description provided for @dbSettingsName.
  ///
  /// In en, this message translates to:
  /// **'Database name'**
  String get dbSettingsName;

  /// No description provided for @dbSettingsRootGroupName.
  ///
  /// In en, this message translates to:
  /// **'Root group name'**
  String get dbSettingsRootGroupName;

  /// No description provided for @dbSettingsDefaultUserName.
  ///
  /// In en, this message translates to:
  /// **'Default user name'**
  String get dbSettingsDefaultUserName;

  /// No description provided for @dbSettingsRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Recycle Bin'**
  String get dbSettingsRecycleBin;

  /// No description provided for @dbSettingsHistoryMaxItems.
  ///
  /// In en, this message translates to:
  /// **'Versions in an entry\'s history'**
  String get dbSettingsHistoryMaxItems;

  /// No description provided for @dbSettingsHistoryMaxSize.
  ///
  /// In en, this message translates to:
  /// **'Maximum size of an entry\'s history (MiB)'**
  String get dbSettingsHistoryMaxSize;

  /// No description provided for @dbSettingsEmptyUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Empty: no limit'**
  String get dbSettingsEmptyUnlimited;

  /// No description provided for @dbSettingsEncryption.
  ///
  /// In en, this message translates to:
  /// **'Encryption (KDBX {version})'**
  String dbSettingsEncryption(int version);

  /// No description provided for @dbSettingsCipher.
  ///
  /// In en, this message translates to:
  /// **'Cipher'**
  String get dbSettingsCipher;

  /// No description provided for @dbSettingsKdf.
  ///
  /// In en, this message translates to:
  /// **'Key derivation'**
  String get dbSettingsKdf;

  /// No description provided for @dbSettingsRounds.
  ///
  /// In en, this message translates to:
  /// **'Transformation rounds'**
  String get dbSettingsRounds;

  /// No description provided for @dbSettingsMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory (MiB)'**
  String get dbSettingsMemory;

  /// No description provided for @dbSettingsIterations.
  ///
  /// In en, this message translates to:
  /// **'Iterations'**
  String get dbSettingsIterations;

  /// No description provided for @dbSettingsParallelism.
  ///
  /// In en, this message translates to:
  /// **'Parallelism (threads)'**
  String get dbSettingsParallelism;

  /// No description provided for @dbSettingsMeasure.
  ///
  /// In en, this message translates to:
  /// **'Measure the opening time'**
  String get dbSettingsMeasure;

  /// No description provided for @dbSettingsMeasured.
  ///
  /// In en, this message translates to:
  /// **'Opening takes about {seconds} s on this device.'**
  String dbSettingsMeasured(String seconds);

  /// No description provided for @dbSettingsRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a value from {min} to {max}.'**
  String dbSettingsRange(int min, int max);

  /// No description provided for @dbSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Database settings saved.'**
  String get dbSettingsSaved;

  /// No description provided for @cipherAes.
  ///
  /// In en, this message translates to:
  /// **'AES-256'**
  String get cipherAes;

  /// No description provided for @cipherChaCha20.
  ///
  /// In en, this message translates to:
  /// **'ChaCha20'**
  String get cipherChaCha20;

  /// No description provided for @cipherTwofish.
  ///
  /// In en, this message translates to:
  /// **'Twofish'**
  String get cipherTwofish;

  /// No description provided for @kdfAes.
  ///
  /// In en, this message translates to:
  /// **'AES-KDF'**
  String get kdfAes;

  /// No description provided for @kdfArgon2d.
  ///
  /// In en, this message translates to:
  /// **'Argon2d'**
  String get kdfArgon2d;

  /// No description provided for @kdfArgon2id.
  ///
  /// In en, this message translates to:
  /// **'Argon2id'**
  String get kdfArgon2id;

  /// No description provided for @changeKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Change master key'**
  String get changeKeyTitle;

  /// No description provided for @changeKeyNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New master password'**
  String get changeKeyNewPassword;

  /// No description provided for @changeKeyButton.
  ///
  /// In en, this message translates to:
  /// **'Change key'**
  String get changeKeyButton;

  /// No description provided for @changeKeyInProgress.
  ///
  /// In en, this message translates to:
  /// **'Changing the key…'**
  String get changeKeyInProgress;

  /// No description provided for @changeKeyInfo.
  ///
  /// In en, this message translates to:
  /// **'After the change the database opens only with the new key.'**
  String get changeKeyInfo;

  /// No description provided for @changeKeyDone.
  ///
  /// In en, this message translates to:
  /// **'Master key changed.'**
  String get changeKeyDone;

  /// No description provided for @exportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export a copy'**
  String get exportTitle;

  /// No description provided for @exportDone.
  ///
  /// In en, this message translates to:
  /// **'Encrypted copy exported: {name}'**
  String exportDone(String name);

  /// No description provided for @entryEditTotpSetup.
  ///
  /// In en, this message translates to:
  /// **'Set up TOTP'**
  String get entryEditTotpSetup;

  /// No description provided for @entryEditTotpUri.
  ///
  /// In en, this message translates to:
  /// **'otpauth:// URI'**
  String get entryEditTotpUri;

  /// No description provided for @entryEditTotpHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the otpauth:// address provided by the service (often shown next to the QR code). It replaces the entry\'s TOTP settings.'**
  String get entryEditTotpHint;

  /// No description provided for @entryEditTotpInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid otpauth:// URI.'**
  String get entryEditTotpInvalid;

  /// No description provided for @entryEditTotpApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get entryEditTotpApply;

  /// No description provided for @generatorSaveProfile.
  ///
  /// In en, this message translates to:
  /// **'Save as profile'**
  String get generatorSaveProfile;

  /// No description provided for @generatorRemoveProfile.
  ///
  /// In en, this message translates to:
  /// **'Remove profile'**
  String get generatorRemoveProfile;

  /// No description provided for @generatorProfileName.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get generatorProfileName;

  /// No description provided for @generatorProfileReserved.
  ///
  /// In en, this message translates to:
  /// **'This name belongs to a built-in profile.'**
  String get generatorProfileReserved;

  /// No description provided for @fileSelectNotPersistent.
  ///
  /// In en, this message translates to:
  /// **'This file stays accessible only while the app is open: you will need to choose it again later.'**
  String get fileSelectNotPersistent;

  /// No description provided for @deviceBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Device not secure'**
  String get deviceBlockedTitle;

  /// No description provided for @deviceBlockedBody.
  ///
  /// In en, this message translates to:
  /// **'KeePassMobile cannot be used on rooted or jailbroken devices, or on devices configured in an insecure way (for example with developer options or USB debugging enabled). To protect your databases the app stays locked.'**
  String get deviceBlockedBody;

  /// No description provided for @entryIcon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get entryIcon;

  /// No description provided for @entryEditChooseIcon.
  ///
  /// In en, this message translates to:
  /// **'Choose icon'**
  String get entryEditChooseIcon;

  /// No description provided for @entryEditIconNumber.
  ///
  /// In en, this message translates to:
  /// **'Icon {number}'**
  String entryEditIconNumber(int number);

  /// No description provided for @entryExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get entryExpires;

  /// No description provided for @entryExpiresOn.
  ///
  /// In en, this message translates to:
  /// **'Expires on {date}'**
  String entryExpiresOn(String date);

  /// No description provided for @entryExpiredOn.
  ///
  /// In en, this message translates to:
  /// **'Expired on {date}'**
  String entryExpiredOn(String date);

  /// No description provided for @entryEditExpiryDate.
  ///
  /// In en, this message translates to:
  /// **'Expiry date'**
  String get entryEditExpiryDate;

  /// No description provided for @entryTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get entryTags;

  /// No description provided for @entryEditTagsHint.
  ///
  /// In en, this message translates to:
  /// **'Separated by comma or semicolon'**
  String get entryEditTagsHint;

  /// No description provided for @entryHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get entryHistory;

  /// No description provided for @entryHistoryVersion.
  ///
  /// In en, this message translates to:
  /// **'Version of {date}'**
  String entryHistoryVersion(String date);

  /// No description provided for @entryHistoryReadOnly.
  ///
  /// In en, this message translates to:
  /// **'{version}, read only.'**
  String entryHistoryReadOnly(String version);

  /// No description provided for @entryHistoryRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get entryHistoryRestore;

  /// No description provided for @entryHistoryDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete version'**
  String get entryHistoryDelete;

  /// No description provided for @entryHistoryRestoreConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restore this version? The current version stays in the history.'**
  String get entryHistoryRestoreConfirm;

  /// No description provided for @entryHistoryDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this version from the history? This cannot be undone.'**
  String get entryHistoryDeleteConfirm;

  /// No description provided for @entryHistoryUndated.
  ///
  /// In en, this message translates to:
  /// **'Undated version'**
  String get entryHistoryUndated;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @entryAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get entryAttachments;

  /// No description provided for @entryEditAttachmentAdd.
  ///
  /// In en, this message translates to:
  /// **'Add attachment'**
  String get entryEditAttachmentAdd;

  /// No description provided for @entryEditAttachmentRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove attachment'**
  String get entryEditAttachmentRemove;

  /// No description provided for @entryEditAttachmentUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The selected file could not be read.'**
  String get entryEditAttachmentUnreadable;

  /// No description provided for @entryEditAttachmentTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file exceeds the maximum size of {size}.'**
  String entryEditAttachmentTooLarge(String size);

  /// No description provided for @entryEditAttachmentExistsTitle.
  ///
  /// In en, this message translates to:
  /// **'Attachment already present'**
  String get entryEditAttachmentExistsTitle;

  /// No description provided for @entryEditAttachmentExists.
  ///
  /// In en, this message translates to:
  /// **'The entry already has an attachment \"{name}\".'**
  String entryEditAttachmentExists(String name);

  /// No description provided for @entryEditAttachmentReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get entryEditAttachmentReplace;

  /// No description provided for @entryEditAttachmentRename.
  ///
  /// In en, this message translates to:
  /// **'Add with another name'**
  String get entryEditAttachmentRename;

  /// No description provided for @entryAttachmentNoPreview.
  ///
  /// In en, this message translates to:
  /// **'No preview available for this file type.'**
  String get entryAttachmentNoPreview;

  /// No description provided for @entryAttachmentSave.
  ///
  /// In en, this message translates to:
  /// **'Save {name}'**
  String entryAttachmentSave(String name);

  /// No description provided for @entryAttachmentSaveWarning.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be saved unencrypted, without the database encryption: anyone with access to the file will be able to read it. Continue?'**
  String entryAttachmentSaveWarning(String name);

  /// No description provided for @entryAttachmentSaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Save unencrypted'**
  String get entryAttachmentSaveConfirm;

  /// No description provided for @entryAttachmentSaved.
  ///
  /// In en, this message translates to:
  /// **'Attachment saved: {name}'**
  String entryAttachmentSaved(String name);

  /// No description provided for @entryAttachmentSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'The attachment could not be saved.'**
  String get entryAttachmentSaveFailed;

  /// No description provided for @entryUrlOpen.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get entryUrlOpen;

  /// No description provided for @entryUrlNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Only http and https addresses can be opened.'**
  String get entryUrlNotSupported;

  /// No description provided for @entryUrlNoApp.
  ///
  /// In en, this message translates to:
  /// **'No app can open this address.'**
  String get entryUrlNoApp;

  /// No description provided for @unlockBiometric.
  ///
  /// In en, this message translates to:
  /// **'Unlock with biometrics'**
  String get unlockBiometric;

  /// No description provided for @biometricPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock the database'**
  String get biometricPromptTitle;

  /// No description provided for @biometricPromptCancel.
  ///
  /// In en, this message translates to:
  /// **'Use password'**
  String get biometricPromptCancel;

  /// No description provided for @biometricEnableTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on biometric unlock'**
  String get biometricEnableTitle;

  /// No description provided for @biometricUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update biometric unlock'**
  String get biometricUpdateTitle;

  /// No description provided for @errorBiometricUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Biometrics unavailable: enrol a fingerprint or face and set a screen lock on the device.'**
  String get errorBiometricUnavailable;

  /// No description provided for @errorBiometricFailed.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock failed. Use the password.'**
  String get errorBiometricFailed;

  /// No description provided for @errorBiometricInvalidated.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock was turned off because the device biometrics changed. Unlock with the password and turn it on again in the database settings.'**
  String get errorBiometricInvalidated;

  /// No description provided for @errorBiometricStale.
  ///
  /// In en, this message translates to:
  /// **'The database was changed elsewhere or its key changed: unlock with the password and biometric unlock will be updated.'**
  String get errorBiometricStale;

  /// No description provided for @dbSettingsBiometric.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get dbSettingsBiometric;

  /// No description provided for @dbSettingsBiometricInfo.
  ///
  /// In en, this message translates to:
  /// **'Open this database with your fingerprint or face. Only the derived key is kept on the device, protected by biometrics.'**
  String get dbSettingsBiometricInfo;

  /// No description provided for @dbSettingsKdfLocked.
  ///
  /// In en, this message translates to:
  /// **'With biometric unlock the key derivation stays fixed. To change it, turn biometric unlock off, lock the database and open it again with the password.'**
  String get dbSettingsKdfLocked;

  /// No description provided for @errorSaveKdfLocked.
  ///
  /// In en, this message translates to:
  /// **'The key derivation cannot be changed in this session: open the database with the password.'**
  String get errorSaveKdfLocked;

  /// No description provided for @changeKeyDoneBiometricOff.
  ///
  /// In en, this message translates to:
  /// **'Master key changed. Biometric unlock was turned off: turn it on again in the database settings.'**
  String get changeKeyDoneBiometricOff;

  /// No description provided for @biometricOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get biometricOfferTitle;

  /// No description provided for @biometricOfferBody.
  ///
  /// In en, this message translates to:
  /// **'Do you want to open this database with your fingerprint or face? Only the derived key is kept on the device, protected by biometrics. You can change this from Settings → Database settings.'**
  String get biometricOfferBody;

  /// No description provided for @biometricOfferEnable.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get biometricOfferEnable;

  /// No description provided for @biometricOfferNever.
  ///
  /// In en, this message translates to:
  /// **'Don\'t ask again'**
  String get biometricOfferNever;

  /// No description provided for @biometricOfferEnabled.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock turned on.'**
  String get biometricOfferEnabled;

  /// No description provided for @externalChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'File changed elsewhere'**
  String get externalChangeTitle;

  /// No description provided for @externalChangeBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" was changed by another app or device after it was opened. Synchronize merges both versions; Overwrite replaces it with this version and the changes made elsewhere are lost.'**
  String externalChangeBody(String name);

  /// No description provided for @externalChangeSynchronize.
  ///
  /// In en, this message translates to:
  /// **'Synchronize'**
  String get externalChangeSynchronize;

  /// No description provided for @externalChangeOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get externalChangeOverwrite;

  /// No description provided for @externalChangeCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get externalChangeCancel;

  /// No description provided for @errorSaveExternalCanceled.
  ///
  /// In en, this message translates to:
  /// **'Saving canceled: the file was changed elsewhere. Your changes were not saved.'**
  String get errorSaveExternalCanceled;

  /// No description provided for @errorSyncKeyMismatch.
  ///
  /// In en, this message translates to:
  /// **'Cannot synchronize: the file changed elsewhere has a different master key. Nothing was written.'**
  String get errorSyncKeyMismatch;

  /// No description provided for @errorSyncNeedsPassword.
  ///
  /// In en, this message translates to:
  /// **'Cannot synchronize without the password: lock the database and open it again with the master password. Nothing was written.'**
  String get errorSyncNeedsPassword;

  /// No description provided for @errorSyncDifferentDatabase.
  ///
  /// In en, this message translates to:
  /// **'Cannot synchronize: the file was replaced with a different database. Nothing was written.'**
  String get errorSyncDifferentDatabase;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Synchronize now'**
  String get syncNow;

  /// No description provided for @syncInProgress.
  ///
  /// In en, this message translates to:
  /// **'Synchronizing…'**
  String get syncInProgress;

  /// No description provided for @syncUnchanged.
  ///
  /// In en, this message translates to:
  /// **'The file has not changed: nothing to synchronize.'**
  String get syncUnchanged;

  /// No description provided for @syncDone.
  ///
  /// In en, this message translates to:
  /// **'Database synchronized with the changes made elsewhere.'**
  String get syncDone;

  /// No description provided for @remoteServerSftp.
  ///
  /// In en, this message translates to:
  /// **'SFTP'**
  String get remoteServerSftp;

  /// No description provided for @remoteAddressHintSftp.
  ///
  /// In en, this message translates to:
  /// **'sftp://server:22/folder/'**
  String get remoteAddressHintSftp;

  /// No description provided for @sshUseKey.
  ///
  /// In en, this message translates to:
  /// **'Use an SSH private key'**
  String get sshUseKey;

  /// No description provided for @sshPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'OpenSSH private key'**
  String get sshPrivateKey;

  /// No description provided for @sshChooseKey.
  ///
  /// In en, this message translates to:
  /// **'Choose private key file'**
  String get sshChooseKey;

  /// No description provided for @sshPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Private key passphrase'**
  String get sshPassphrase;

  /// No description provided for @sshHostTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify SSH server'**
  String get sshHostTitle;

  /// No description provided for @sshHostBody.
  ///
  /// In en, this message translates to:
  /// **'First connection to {server}. Compare this fingerprint with the one provided by the server administrator before accepting.'**
  String sshHostBody(String server);

  /// No description provided for @errorSshHostChanged.
  ///
  /// In en, this message translates to:
  /// **'The server SSH key has changed. Connection blocked. Verify the server with its administrator.'**
  String get errorSshHostChanged;

  /// No description provided for @errorSshKey.
  ///
  /// In en, this message translates to:
  /// **'Invalid private key or incorrect passphrase.'**
  String get errorSshKey;

  /// No description provided for @errorSftp.
  ///
  /// In en, this message translates to:
  /// **'SFTP operation failed. Check permissions and server rename support.'**
  String get errorSftp;

  /// No description provided for @errorRemoteConflict.
  ///
  /// In en, this message translates to:
  /// **'The server file changed during saving. Nothing was written to the server. Synchronize and try again.'**
  String get errorRemoteConflict;

  /// No description provided for @settingsRemoteCache.
  ///
  /// In en, this message translates to:
  /// **'Local cache of remote databases'**
  String get settingsRemoteCache;

  /// No description provided for @settingsRemoteCacheHint.
  ///
  /// In en, this message translates to:
  /// **'Keep an encrypted KDBX copy excluded from backups. Turning this off does not delete changes awaiting upload.'**
  String get settingsRemoteCacheHint;

  /// No description provided for @settingsRemoteCacheClear.
  ///
  /// In en, this message translates to:
  /// **'Delete synced local copies'**
  String get settingsRemoteCacheClear;

  /// No description provided for @settingsRemoteCacheClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Changes awaiting upload will be kept. A server connection is needed to recreate the local copies.'**
  String get settingsRemoteCacheClearConfirm;

  /// No description provided for @settingsRemoteCacheClearDone.
  ///
  /// In en, this message translates to:
  /// **'Synced copies cleanup complete.'**
  String get settingsRemoteCacheClearDone;

  /// No description provided for @settingsRemoteCacheClearIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Some copies could not be verified or changed during cleanup.'**
  String get settingsRemoteCacheClearIncomplete;

  /// No description provided for @cacheOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline: using the encrypted local copy.'**
  String get cacheOffline;

  /// No description provided for @cachePending.
  ///
  /// In en, this message translates to:
  /// **'Changes saved on this device, awaiting upload to the server.'**
  String get cachePending;

  /// No description provided for @cacheUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Local cache unavailable. An offline copy is not guaranteed.'**
  String get cacheUnavailable;

  /// No description provided for @cacheChanged.
  ///
  /// In en, this message translates to:
  /// **'The local copy changed in another session. Reopen the database before synchronizing. No copy was overwritten.'**
  String get cacheChanged;

  /// No description provided for @unlockFromCache.
  ///
  /// In en, this message translates to:
  /// **'Open the local copy without contacting the server'**
  String get unlockFromCache;

  /// No description provided for @cacheSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Synchronization failed. The local copy is preserved.'**
  String get cacheSyncFailed;

  /// No description provided for @unlockChooseAgain.
  ///
  /// In en, this message translates to:
  /// **'Choose the file again'**
  String get unlockChooseAgain;

  /// No description provided for @groupCreate.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get groupCreate;

  /// No description provided for @groupEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit group'**
  String get groupEdit;

  /// No description provided for @iconImport.
  ///
  /// In en, this message translates to:
  /// **'Import image'**
  String get iconImport;

  /// No description provided for @iconCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom icon'**
  String get iconCustom;

  /// No description provided for @iconImportError.
  ///
  /// In en, this message translates to:
  /// **'Unable to read the image.'**
  String get iconImportError;

  /// No description provided for @databasesClose.
  ///
  /// In en, this message translates to:
  /// **'Close database'**
  String get databasesClose;

  /// No description provided for @databasesMove.
  ///
  /// In en, this message translates to:
  /// **'Move to another database'**
  String get databasesMove;

  /// No description provided for @databasesMoveIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Copy saved, but the original could not be removed.'**
  String get databasesMoveIncomplete;

  /// No description provided for @databasesCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy to another database'**
  String get databasesCopy;

  /// No description provided for @linkedDatabaseFailure.
  ///
  /// In en, this message translates to:
  /// **'Unable to open a linked database. For a server, open it manually first and save the credentials.'**
  String get linkedDatabaseFailure;

  /// No description provided for @linkedDatabaseAdd.
  ///
  /// In en, this message translates to:
  /// **'Add linked database'**
  String get linkedDatabaseAdd;

  /// No description provided for @linkedDatabaseAddHint.
  ///
  /// In en, this message translates to:
  /// **'Links another open database so it unlocks automatically with this one.'**
  String get linkedDatabaseAddHint;

  /// No description provided for @linkedDatabasePassword.
  ///
  /// In en, this message translates to:
  /// **'Linked database password (stored in this database)'**
  String get linkedDatabasePassword;

  /// No description provided for @linkedDatabaseDeviceWarning.
  ///
  /// In en, this message translates to:
  /// **'This link contains device-specific rules. Allowing it enables it on this device.'**
  String get linkedDatabaseDeviceWarning;

  /// No description provided for @linkedDatabaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Open linked database?'**
  String get linkedDatabaseTitle;

  /// No description provided for @linkedDatabaseBody.
  ///
  /// In en, this message translates to:
  /// **'Allow access to {database}? Key file: {keyFile}. Approval is remembered for this link.'**
  String linkedDatabaseBody(String database, String keyFile);

  /// No description provided for @linkedDatabaseAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get linkedDatabaseAllow;

  /// No description provided for @databasesTitle.
  ///
  /// In en, this message translates to:
  /// **'Open databases'**
  String get databasesTitle;

  /// No description provided for @databasesOpenAnother.
  ///
  /// In en, this message translates to:
  /// **'Open another database'**
  String get databasesOpenAnother;

  /// No description provided for @searchGoToGroup.
  ///
  /// In en, this message translates to:
  /// **'Go to group'**
  String get searchGoToGroup;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @groupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a group name.'**
  String get groupNameRequired;

  /// No description provided for @groupDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get groupDelete;

  /// No description provided for @groupDeleteToBin.
  ///
  /// In en, this message translates to:
  /// **'Move this group and all its contents to the recycle bin?'**
  String get groupDeleteToBin;

  /// No description provided for @groupDeletePermanent.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete this group and all its contents? This cannot be undone.'**
  String get groupDeletePermanent;

  /// No description provided for @itemMoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get itemMoveTitle;

  /// No description provided for @itemNoDestination.
  ///
  /// In en, this message translates to:
  /// **'No destination group is available.'**
  String get itemNoDestination;

  /// No description provided for @itemRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore from recycle bin'**
  String get itemRestore;

  /// No description provided for @itemDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate entry'**
  String get itemDuplicate;

  /// No description provided for @itemDuplicateSuffix.
  ///
  /// In en, this message translates to:
  /// **'copy'**
  String get itemDuplicateSuffix;

  /// No description provided for @errorItemOperation.
  ///
  /// In en, this message translates to:
  /// **'This operation is not allowed for the item or destination group.'**
  String get errorItemOperation;

  /// No description provided for @errorFieldReference.
  ///
  /// In en, this message translates to:
  /// **'Unable to resolve the field reference.'**
  String get errorFieldReference;

  /// No description provided for @searchOptions.
  ///
  /// In en, this message translates to:
  /// **'Search options'**
  String get searchOptions;

  /// No description provided for @searchFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get searchFieldTitle;

  /// No description provided for @searchFieldUserName.
  ///
  /// In en, this message translates to:
  /// **'User name'**
  String get searchFieldUserName;

  /// No description provided for @searchFieldUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get searchFieldUrl;

  /// No description provided for @searchFieldPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get searchFieldPassword;

  /// No description provided for @searchFieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get searchFieldNotes;

  /// No description provided for @searchFieldOther.
  ///
  /// In en, this message translates to:
  /// **'Other fields'**
  String get searchFieldOther;

  /// No description provided for @searchFieldTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get searchFieldTags;

  /// No description provided for @searchFieldGroup.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get searchFieldGroup;

  /// No description provided for @searchCaseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Case sensitive'**
  String get searchCaseSensitive;

  /// No description provided for @searchExcludeExpired.
  ///
  /// In en, this message translates to:
  /// **'Exclude expired entries'**
  String get searchExcludeExpired;

  /// No description provided for @searchRegex.
  ///
  /// In en, this message translates to:
  /// **'Regular expression'**
  String get searchRegex;

  /// No description provided for @searchRegexError.
  ///
  /// In en, this message translates to:
  /// **'Invalid expression or search timed out.'**
  String get searchRegexError;

  /// No description provided for @searchRegexSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit the search to run the expression.'**
  String get searchRegexSubmit;

  /// No description provided for @autofillSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save credentials'**
  String get autofillSaveTitle;

  /// No description provided for @autofillSaveDescription.
  ///
  /// In en, this message translates to:
  /// **'Create a new entry after reviewing these details.'**
  String get autofillSaveDescription;

  /// No description provided for @autofillSaveTarget.
  ///
  /// In en, this message translates to:
  /// **'Website or app'**
  String get autofillSaveTarget;

  /// No description provided for @autofillSaveUser.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get autofillSaveUser;

  /// No description provided for @autofillSaveDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get autofillSaveDatabase;

  /// No description provided for @autofillSavePassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get autofillSavePassword;

  /// No description provided for @autofillSaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Create entry'**
  String get autofillSaveConfirm;

  /// No description provided for @autofillSaveRetry.
  ///
  /// In en, this message translates to:
  /// **'Close this screen and submit the login again to retry.'**
  String get autofillSaveRetry;

  /// No description provided for @groupAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get groupAddTitle;

  /// No description provided for @templatesInstall.
  ///
  /// In en, this message translates to:
  /// **'Add default templates'**
  String get templatesInstall;

  /// No description provided for @templatesInstallHint.
  ///
  /// In en, this message translates to:
  /// **'Creates a Templates group with ready-made examples for cards, Wi-Fi, and IDs.'**
  String get templatesInstallHint;

  /// No description provided for @templateShowAllFields.
  ///
  /// In en, this message translates to:
  /// **'Show all fields'**
  String get templateShowAllFields;

  /// No description provided for @templatesInstallConfirm.
  ///
  /// In en, this message translates to:
  /// **'Add missing default templates to the database?'**
  String get templatesInstallConfirm;

  /// No description provided for @templatesInstallSuccess.
  ///
  /// In en, this message translates to:
  /// **'Default templates are ready to use.'**
  String get templatesInstallSuccess;

  /// No description provided for @templateGroup.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get templateGroup;

  /// No description provided for @templateIdCard.
  ///
  /// In en, this message translates to:
  /// **'ID card'**
  String get templateIdCard;

  /// No description provided for @templateWlan.
  ///
  /// In en, this message translates to:
  /// **'Wireless LAN'**
  String get templateWlan;

  /// No description provided for @templateNote.
  ///
  /// In en, this message translates to:
  /// **'Secure note'**
  String get templateNote;

  /// No description provided for @templateCreditCard.
  ///
  /// In en, this message translates to:
  /// **'Credit card'**
  String get templateCreditCard;

  /// No description provided for @templateMembership.
  ///
  /// In en, this message translates to:
  /// **'Membership'**
  String get templateMembership;

  /// No description provided for @templateNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get templateNumber;

  /// No description provided for @templateName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get templateName;

  /// No description provided for @templatePlace.
  ///
  /// In en, this message translates to:
  /// **'Place of issue'**
  String get templatePlace;

  /// No description provided for @templateIssueDate.
  ///
  /// In en, this message translates to:
  /// **'Date of issue'**
  String get templateIssueDate;

  /// No description provided for @templateHolder.
  ///
  /// In en, this message translates to:
  /// **'Card holder'**
  String get templateHolder;

  /// No description provided for @entryTemplateEmpty.
  ///
  /// In en, this message translates to:
  /// **'New entry'**
  String get entryTemplateEmpty;

  /// No description provided for @settingsExpireTan.
  ///
  /// In en, this message translates to:
  /// **'Expire TAN entries when opened'**
  String get settingsExpireTan;

  /// No description provided for @settingsExpireTanHint.
  ///
  /// In en, this message translates to:
  /// **'Mark a TAN as used when its details are opened.'**
  String get settingsExpireTanHint;

  /// No description provided for @entryEditTotpScan.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get entryEditTotpScan;

  /// No description provided for @entryEditTotpScanError.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable. Check permissions and try again.'**
  String get entryEditTotpScanError;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
