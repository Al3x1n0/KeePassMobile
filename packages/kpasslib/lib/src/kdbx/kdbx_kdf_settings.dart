import 'constants.dart';

/// KDF settings of a database: AES-KDF rounds or Argon2 parameters.
///
/// Read and written with `KdbxHeader.kdfSettings`. Added by KeePassMobile.
sealed class KdfSettings {
  const KdfSettings();

  /// The [KdfId] of the algorithm.
  String get kdfId;
}

/// AES-KDF with [rounds] transformation rounds.
final class AesKdfSettings extends KdfSettings {
  /// Constructs AES-KDF settings.
  const AesKdfSettings({required this.rounds});

  /// The number of AES transformation rounds.
  final int rounds;

  @override
  String get kdfId => KdfId.aes;

  @override
  bool operator ==(Object other) =>
      other is AesKdfSettings && other.rounds == rounds;

  @override
  int get hashCode => rounds.hashCode;
}

/// Argon2d or Argon2id with [memory] bytes, [iterations] and [parallelism].
final class Argon2KdfSettings extends KdfSettings {
  /// Constructs Argon2 settings; [id] selects Argon2id instead of Argon2d.
  const Argon2KdfSettings({
    required this.id,
    required this.memory,
    required this.iterations,
    required this.parallelism,
  });

  /// Argon2id when `true`, Argon2d otherwise.
  final bool id;

  /// The memory in bytes.
  final int memory;

  /// The number of iterations.
  final int iterations;

  /// The number of lanes (threads).
  final int parallelism;

  @override
  String get kdfId => id ? KdfId.argon2id : KdfId.argon2d;

  @override
  bool operator ==(Object other) =>
      other is Argon2KdfSettings &&
      other.id == id &&
      other.memory == memory &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(id, memory, iterations, parallelism);
}
