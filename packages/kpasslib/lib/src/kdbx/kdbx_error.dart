/// A KDBX error that can be thrown.
sealed class KdbxError implements Exception {
  final String _message;
  const KdbxError([String message = '']) : _message = message;

  /// The description of the error.
  String get message => _message;
}

/// Resource ceilings applied while opening a KDBX file.
enum KdbxResourceLimit { fileSize, payloadSize, kdfCost }

/// A file requires more resources than the reader allows.
final class KdbxResourceLimitError extends KdbxError {
  /// Creates an error for the specified [limit].
  const KdbxResourceLimitError(this.limit)
      : super('Database exceeds the supported resource limits');

  /// The ceiling that would be exceeded.
  final KdbxResourceLimit limit;
}

/// A error thrown if a KDBX file corruption detected.
class FileCorruptedError extends KdbxError {
  /// Creates a [FileCorruptedError] with [message].
  const FileCorruptedError(String message) : super('File corrupted: $message');
}

/// A error thrown while attempting to set an unsupported value.
class UnsupportedValueError extends KdbxError {
  /// Creates a [UnsupportedValueError] with [message].
  const UnsupportedValueError(String message)
      : super('Not supported value: $message');
}

/// A error thrown if an invalid state detected.
class InvalidStateError extends KdbxError {
  /// Creates a [InvalidStateError] with [message].
  const InvalidStateError(String message) : super('Invalid state: $message');
}

/// A error thrown if credentials are invalid.
class InvalidCredentialsError extends KdbxError {
  /// Creates a [InvalidCredentialsError] with [message].
  const InvalidCredentialsError(String message)
      : super('Invalid credentials: $message');
}

/// A error thrown while attempting to merge.
class MergeError extends KdbxError {
  /// Creates a [MergeError] with [message].
  const MergeError(String message) : super('Merge error: $message');
}

/// Thrown when a transformed key no longer matches the KDF parameters of the
/// file (e.g. the file was saved elsewhere with a new salt) and no password or
/// key file is available to derive it again.
///
/// Added by KeePassMobile.
class TransformedKeyStaleError extends KdbxError {
  /// Creates a [TransformedKeyStaleError].
  const TransformedKeyStaleError()
      : super('Transformed key does not match the file KDF parameters');
}
