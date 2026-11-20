import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:kpasslib/src/crypto/twofish.dart';
import 'package:test/test.dart';

void main() {
  group('TwofishCbc', () {
    // Twofish paper vector: all-zero 256-bit key, all-zero block.
    test('encrypts the reference vector (first block, zero IV)', () {
      final cipher = TwofishCbc(key: Uint8List(32));
      final out = cipher.encryptCbc(data: Uint8List(16), iv: Uint8List(16));
      expect(out.length, 32); // block + PKCS7 padding
      expect(
          hex.encode(out.sublist(0, 16)), '57ff739d4dc92c1bd7fc01700cc8216f');
    });

    test('round-trips data of various lengths', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final iv = Uint8List.fromList(List.generate(16, (i) => 255 - i));
      final cipher = TwofishCbc(key: key);
      for (final len in [0, 1, 15, 16, 17, 1000]) {
        final data = Uint8List.fromList(List.generate(len, (i) => i * 7));
        final enc = cipher.encryptCbc(data: data, iv: iv);
        expect(enc.length % 16, 0);
        expect(cipher.decryptCbc(data: enc, iv: iv), data);
      }
    });

    test('invalid padding is reported as a wrong key', () {
      final enc = TwofishCbc(key: Uint8List(32))
          .encryptCbc(data: Uint8List(5), iv: Uint8List(16));
      final wrong = TwofishCbc(key: Uint8List(32)..[0] = 1);
      expect(() => wrong.decryptCbc(data: enc, iv: Uint8List(16)),
          throwsA(isA<InvalidCredentialsError>()));
    });

    test('rejects key and IV of wrong length', () {
      expect(() => TwofishCbc(key: Uint8List(16)),
          throwsA(isA<UnsupportedValueError>()));
      expect(
          () => TwofishCbc(key: Uint8List(32))
              .encryptCbc(data: Uint8List(1), iv: Uint8List(12)),
          throwsA(isA<FileCorruptedError>()));
    });
  });
}
