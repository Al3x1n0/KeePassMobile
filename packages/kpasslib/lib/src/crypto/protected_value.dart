import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'crypto_utils.dart';

/// A wrapper for protection sensitive data in memory
class ProtectedData {
  final List<int> _data;
  final List<int> _salt;

  ProtectedData._(this._data, this._salt);

  /// Constructs [ProtectedData] from [bytes] already protected with [salt].
  ProtectedData.fromProtectedBytes({
    required List<int> bytes,
    required List<int> salt,
  }) : this._(Uint8List.fromList(bytes), Uint8List.fromList(salt));

  /// Constructs [ProtectedData] from [text], protected with random salt.
  factory ProtectedData.fromString(String text) {
    final bytes = utf8.encode(text);
    try {
      return ProtectedData.fromBytes(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// Constructs [ProtectedData] from [bytes] protected with random salt.
  factory ProtectedData.fromBytes(List<int> bytes) {
    final salt = CryptoUtils.randomBytes(bytes.length);
    final data = CryptoUtils.transformXor(data: bytes, salt: salt);
    return ProtectedData._(data, salt);
  }

  /// The hash of the plain data.
  List<int> get hash {
    final bytes = this.bytes;
    final hash = sha256.convert(bytes).bytes;
    CryptoUtils.wipeData(bytes);
    return hash;
  }

  /// The plain data as text.
  String get text {
    final plain = bytes;
    try {
      return utf8.decode(plain);
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  /// Erases the owned buffers. Previously returned values are independent.
  void clear() {
    _data.fillRange(0, _data.length, 0);
    _salt.fillRange(0, _salt.length, 0);
  }

  /// The plain data as bytes.
  List<int> get bytes => CryptoUtils.transformXor(
        data: _data,
        salt: _salt,
      );
}
