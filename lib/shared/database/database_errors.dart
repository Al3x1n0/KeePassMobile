import 'field_references.dart';

import 'package:kpasslib/kpasslib.dart';

import '../../l10n/app_localizations.dart';
import '../security/biometric_key_store.dart';
import '../storage/file_storage.dart';
import '../storage/sftp_client.dart';
import '../storage/remote_cache.dart';
import '../storage/webdav_client.dart';
import 'database_session.dart';
import 'external_change.dart';
import 'item_edits.dart';

final class AutofillNoFillableFieldsException implements Exception {
  const AutofillNoFillableFieldsException();
}

/// Il file chiave indicato non è leggibile.
final class KeyFileUnavailableException implements Exception {
  const KeyFileUnavailableException();
}

/// Messaggio per un errore durante la scelta del database.
String describeFilePickError(AppLocalizations l10n, Object error) =>
    error is KdbxResourceLimitError
    ? _describeResourceLimit(l10n, error.limit)
    : l10n.errorFileUnavailable;

/// Messaggio per l'utente scelto per tipo di errore, mai dal testo
/// dell'eccezione (SEC-01).
String describeDatabaseError(
  AppLocalizations l10n,
  Object error,
) => switch (error) {
  InvalidCredentialsError() => l10n.errorInvalidCredentials,
  FileCorruptedError() => l10n.errorFileCorrupted,
  UnsupportedValueError() => l10n.errorUnsupported,
  KdbxResourceLimitError(:final limit) => _describeResourceLimit(l10n, limit),
  KeyFileUnavailableException() => l10n.errorKeyFileUnavailable,
  FileUnavailableException() => l10n.errorFileUnavailable,
  BiometricKeyException(:final reason) => describeBiometricError(l10n, reason),
  _ when isRemoteError(error) => describeRemoteError(l10n, error),
  _ => l10n.errorGeneric,
};

/// `true` per gli errori dei server remoti (ADR-014).
bool isRemoteError(Object error) => switch (error) {
  SshHostKeyChangedException() ||
  InvalidSshKeyException() ||
  RemoteSftpException() ||
  RemoteCacheUnavailableException() ||
  RemoteCacheChangedException() ||
  RemoteConflictException() ||
  RemoteAuthException() ||
  RemoteUnreachableException() ||
  RemoteNotFoundException() ||
  RemoteHttpException() ||
  InsecureRemoteException() ||
  RemoteCanceledException() ||
  UntrustedCertificateException() ||
  InvalidRemoteAddressException() => true,
  _ => false,
};

/// Messaggio per un errore di un server remoto, mai dal testo dell'eccezione
/// (SEC-01).
String describeRemoteError(AppLocalizations l10n, Object error) =>
    switch (error) {
      KdbxResourceLimitError(:final limit) => _describeResourceLimit(
        l10n,
        limit,
      ),
      SshHostKeyChangedException() => l10n.errorSshHostChanged,
      InvalidSshKeyException() => l10n.errorSshKey,
      RemoteSftpException() => l10n.errorSftp,
      RemoteCacheUnavailableException() => l10n.cacheUnavailable,
      RemoteCacheChangedException() => l10n.cacheChanged,
      RemoteConflictException() => l10n.errorRemoteConflict,
      RemoteAuthException() => l10n.errorRemoteAuth,
      RemoteUnreachableException() => l10n.errorRemoteUnreachable,
      RemoteNotFoundException() => l10n.errorRemoteNotFound,
      RemoteHttpException(:final status) => l10n.errorRemoteServer(status),
      InsecureRemoteException() => l10n.errorRemoteInsecure,
      RemoteCanceledException() => l10n.errorRemoteCanceled,
      UntrustedCertificateException() => l10n.errorRemoteCanceled,
      InvalidRemoteAddressException() => l10n.errorRemoteAddress,
      _ => l10n.errorGeneric,
    };

/// Messaggio per uno sblocco biometrico (o un'attivazione) non riuscito.
String describeBiometricError(
  AppLocalizations l10n,
  BiometricKeyError reason,
) => switch (reason) {
  BiometricKeyError.unavailable => l10n.errorBiometricUnavailable,
  BiometricKeyError.invalidated => l10n.errorBiometricInvalidated,
  BiometricKeyError.stale => l10n.errorBiometricStale,
  BiometricKeyError.canceled ||
  BiometricKeyError.failed => l10n.errorBiometricFailed,
};

/// Messaggio per una creazione di database non riuscita.
String describeCreateError(AppLocalizations l10n, Object error) =>
    switch (error) {
      KeyFileUnavailableException() => l10n.errorKeyFileUnavailable,
      _ => l10n.errorCreateFailed,
    };

/// Messaggio per un errore durante il salvataggio o la compilazione.
String describeSaveError(AppLocalizations l10n, Object error) =>
    switch (error) {
      AutofillNoFillableFieldsException() => l10n.autofillNoFillableFields,
      FieldReferenceException() => l10n.errorFieldReference,
      InvalidItemEditException() => l10n.errorItemOperation,
      KdbxResourceLimitError(:final limit) => _describeResourceLimit(
        l10n,
        limit,
      ),
      FileUnavailableException() => l10n.errorSaveUnavailable,
      DatabaseBusyException() => l10n.errorSaveBusy,
      DatabaseLockedException() => l10n.errorSaveLocked,
      TransformedKeyStaleError() => l10n.errorSaveKdfLocked,
      ExternalChangeCanceledException() => l10n.errorSaveExternalCanceled,
      SyncKeyMismatchException() => l10n.errorSyncKeyMismatch,
      SyncNeedsPasswordException() => l10n.errorSyncNeedsPassword,
      SyncDifferentDatabaseException() => l10n.errorSyncDifferentDatabase,
      _ when isRemoteError(error) => describeRemoteError(l10n, error),
      _ => l10n.errorSaveFailed,
    };

String _describeResourceLimit(AppLocalizations l10n, KdbxResourceLimit limit) =>
    switch (limit) {
      KdbxResourceLimit.fileSize => l10n.errorFileTooLarge,
      KdbxResourceLimit.payloadSize => l10n.errorDatabasePayloadTooLarge,
      KdbxResourceLimit.kdfCost => l10n.errorDatabaseKdfTooCostly,
    };
