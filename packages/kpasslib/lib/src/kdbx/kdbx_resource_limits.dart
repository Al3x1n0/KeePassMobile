import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'constants.dart';
import 'kdbx_error.dart';

/// Resource ceilings for opening KeePass databases on mobile devices.
abstract final class KdbxResourceLimits {
  /// Maximum size of the encrypted file.
  static const maxFileBytes = 128 * DataSize.mebi;

  /// Maximum total decoded payload size, including expanded attachments.
  static const maxDecodedBytes = 128 * DataSize.mebi;

  /// Maximum AES-KDF transformation rounds.
  static const maxAesRounds = 10000000;

  /// Maximum Argon2 memory in bytes.
  static const maxArgon2Memory = 256 * DataSize.mebi;

  /// Maximum Argon2 passes over memory.
  static const maxArgon2Iterations = 32;

  /// Maximum Argon2 lanes.
  static const maxArgon2Parallelism = 16;

  // Bound memory bandwidth as well as peak memory for combinations of settings.
  static const _maxArgon2Work = 2048 * DataSize.mebi;

  /// Rejects an encrypted file above the size ceiling.
  static void checkFileSize(int length) {
    if (length > maxFileBytes) {
      throw const KdbxResourceLimitError(KdbxResourceLimit.fileSize);
    }
  }

  /// Rejects unsupported AES-KDF work.
  static void checkAesRounds(int rounds) {
    if (rounds > maxAesRounds) {
      throw const KdbxResourceLimitError(KdbxResourceLimit.kdfCost);
    }
  }

  /// Rejects unsupported Argon2 work.
  ///
  /// Call after validating the positive input values.
  static void checkArgon2Cost({
    required int memory,
    required int iterations,
    required int parallelism,
  }) {
    if (memory > maxArgon2Memory ||
        iterations > maxArgon2Iterations ||
        parallelism > maxArgon2Parallelism ||
        memory > _maxArgon2Work ~/ iterations) {
      throw const KdbxResourceLimitError(KdbxResourceLimit.kdfCost);
    }
  }
}

/// Tracks cumulative expansion for the main payload and nested gzip binaries.
final class KdbxDecodedSizeBudget {
  /// Starts a fresh [maxBytes] budget.
  KdbxDecodedSizeBudget([int maxBytes = KdbxResourceLimits.maxDecodedBytes])
      : _remaining = maxBytes;

  int _remaining;

  /// Charges a payload to the budget, expanding it if [compressed] is true.
  Uint8List decode(Uint8List bytes, {required bool compressed}) {
    if (compressed) {
      try {
        bytes = const GZipDecoder().decodeBytes(
          bytes,
          throwOnError: true,
          maxOutputSize: _remaining,
        );
      } on ArchiveLimitException {
        throw const KdbxResourceLimitError(KdbxResourceLimit.payloadSize);
      } on FormatException {
        throw const FileCorruptedError('invalid gzip data');
      }
    }
    if (bytes.length > _remaining) {
      throw const KdbxResourceLimitError(KdbxResourceLimit.payloadSize);
    }
    _remaining -= bytes.length;
    return bytes;
  }
}
