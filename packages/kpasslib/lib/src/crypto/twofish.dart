import 'dart:typed_data';

import 'package:pointycastle/api.dart' show KeyParameter;
import 'package:pointycastle/block/twofish.dart';

import '../kdbx/kdbx_error.dart';

/// Twofish-256 in CBC mode with PKCS7 padding, as used by the KeePass
/// TwofishCipher plugin and Keepass2Android
/// (UUID `ad68f29f-576f-4bb9-a36a-d47af965346c`).
///
/// Added by KeePassMobile: upstream kpasslib does not support Twofish.
final class TwofishCbc {
  /// Creates the cipher from a 32-byte [key].
  TwofishCbc({required Uint8List key}) : _key = Uint8List.fromList(key) {
    if (key.length != 32) {
      throw UnsupportedValueError('twofish key length');
    }
  }

  static const _blockSize = 16;
  final Uint8List _key;

  TwofishEngine _engine(bool forEncryption) =>
      TwofishEngine()..init(forEncryption, KeyParameter(_key));

  /// Encrypts [data] with the 16-byte [iv], adding PKCS7 padding.
  Uint8List encryptCbc({required Uint8List data, required Uint8List iv}) {
    _checkIv(iv);
    final pad = _blockSize - data.length % _blockSize;
    final input = Uint8List(data.length + pad)
      ..setRange(0, data.length, data)
      ..fillRange(data.length, data.length + pad, pad);
    final out = Uint8List(input.length);
    final engine = _engine(true);
    final chain = Uint8List.fromList(iv);
    final block = Uint8List(_blockSize);
    for (var off = 0; off < input.length; off += _blockSize) {
      for (var i = 0; i < _blockSize; i++) {
        block[i] = input[off + i] ^ chain[i];
      }
      engine.processBlock(block, 0, out, off);
      chain.setRange(0, _blockSize, out, off);
    }
    input.fillRange(0, input.length, 0);
    return out;
  }

  /// Decrypts [data] with the 16-byte [iv] and removes the PKCS7 padding.
  ///
  /// Invalid padding usually means a wrong key, so it is reported as
  /// [InvalidCredentialsError].
  Uint8List decryptCbc({required Uint8List data, required Uint8List iv}) {
    _checkIv(iv);
    if (data.isEmpty || data.length % _blockSize != 0) {
      throw FileCorruptedError('twofish data length');
    }
    final out = Uint8List(data.length);
    final engine = _engine(false);
    final chain = Uint8List.fromList(iv);
    for (var off = 0; off < data.length; off += _blockSize) {
      engine.processBlock(data, off, out, off);
      for (var i = 0; i < _blockSize; i++) {
        out[off + i] ^= chain[i];
      }
      chain.setRange(0, _blockSize, data, off);
    }
    final pad = out.last;
    if (pad < 1 || pad > _blockSize) {
      throw InvalidCredentialsError('invalid key');
    }
    for (var i = out.length - pad; i < out.length; i++) {
      if (out[i] != pad) throw InvalidCredentialsError('invalid key');
    }
    final result = Uint8List.fromList(out.sublist(0, out.length - pad));
    out.fillRange(0, out.length, 0);
    return result;
  }

  void _checkIv(Uint8List iv) {
    if (iv.length != _blockSize) {
      throw FileCorruptedError('twofish iv length');
    }
  }
}
