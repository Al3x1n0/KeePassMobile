import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:kpasslib/kpasslib.dart';

import '../utils/byte_utils.dart';

/// HMAC block transformation functions
abstract final class HmacBlockTransform {
  static const int _blockSize = DataSize.mebi;
  static const int _hashSize = 32;

  /// Returns encrypted [data].
  static Uint8List encrypt({
    required List<int> data,
    required List<int> key,
  }) {
    final reader = BytesReader(data);
    final writer = BytesWriter();
    var index = 0;

    writeBlock(List<int> blockData) {
      final hash = _getBlockHmac(key, index++, blockData);
      writer.writeBytes(hash);
      writer.writeUint32(blockData.length);
      writer.writeBytes(blockData);
    }

    while (reader.bytesLeft > 0) {
      final size = min(_blockSize, reader.bytesLeft);
      final blockData = reader.readBytes(size);
      writeBlock(blockData);
    }

    writeBlock([]);

    return writer.bytes;
  }

  /// Returns decrypted [data].
  static Uint8List decrypt({
    required List<int> data,
    required List<int> key,
  }) {
    final reader = BytesReader(data);
    final writer = BytesWriter();
    var index = 0;

    while (reader.bytesLeft >= _hashSize + Uint32List.bytesPerElement) {
      final hash = reader.readBytes(_hashSize);
      final size = reader.readUint32();
      if (size > reader.bytesLeft) {
        throw const FileCorruptedError('truncated HMAC block');
      }
      final blockData = reader.readBytes(size);

      if (!ListEquality()
          .equals(hash, _getBlockHmac(key, index++, blockData))) {
        throw FileCorruptedError('invalid block hash');
      }

      if (size == 0) {
        if (reader.bytesLeft != 0) {
          throw const FileCorruptedError('unexpected data after HMAC stream');
        }
        return writer.bytes;
      }

      writer.writeBytes(blockData);
    }

    throw const FileCorruptedError('missing HMAC end block');
  }

  /// Returns hash of the [key].
  static List<int> getHmacKey({
    required List<int> key,
    required int index,
  }) {
    final writer = BytesWriter();
    writer.writeUint64(index);
    writer.writeBytes(key);
    return sha512.convert(writer.bytes).bytes;
  }

  static List<int> _getBlockHmac(
    List<int> key,
    int index,
    List<int> data,
  ) {
    final writer = BytesWriter();
    writer.writeUint64(index);
    writer.writeUint32(data.length);
    writer.writeBytes(data);

    final blockKey = getHmacKey(key: key, index: index);
    return Hmac(sha256, blockKey).convert(writer.bytes).bytes;
  }
}
