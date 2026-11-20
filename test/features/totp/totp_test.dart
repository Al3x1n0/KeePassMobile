import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/totp/totp.dart';

DateTime at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

void main() {
  group('RFC 6238 (KeePass 2: TimeOtp-*)', () {
    // Chiavi dell'appendice B di RFC 6238.
    final sha1Key = '1234567890' * 2;
    final sha256Key = '1234567890' * 3 + '12';
    final sha512Key = '1234567890' * 6 + '1234';
    const times = [59, 1111111109, 1234567890, 20000000000];
    const sha1Codes = ['94287082', '07081804', '89005924', '65353130'];
    const sha256Codes = ['46119246', '68084774', '91819424', '77737706'];
    const sha512Codes = ['90693936', '25091201', '93441116', '47863826'];

    for (final (algorithm, secret, codes) in [
      ('HMAC-SHA-1', sha1Key, sha1Codes),
      ('HMAC-SHA-256', sha256Key, sha256Codes),
      ('HMAC-SHA-512', sha512Key, sha512Codes),
    ]) {
      test(algorithm, () {
        final config = parseTotp({
          'TimeOtp-Secret': secret,
          'TimeOtp-Length': '8',
          'TimeOtp-Algorithm': algorithm,
        })!;
        for (final (i, t) in times.indexed) {
          expect(config.codeAt(at(t)), codes[i], reason: '$t');
        }
      });
    }

    test('segreto esadecimale, Base32 e Base64 equivalenti', () {
      final bytes = utf8.encode(sha1Key);
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final fromHex = parseTotp({'TimeOtp-Secret-Hex': hex});
      final fromB64 = parseTotp({
        'TimeOtp-Secret-Base64': base64.encode(bytes),
      });
      final fromB32 = parseTotp({
        'TimeOtp-Secret-Base32': 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
      });
      expect(fromHex, isNotNull);
      expect(fromB64, fromHex);
      expect(fromB32, fromHex);
      expect(fromHex!.codeAt(at(59)), '287082');
    });

    test('periodo e lunghezza predefiniti 30 s e 6 cifre', () {
      final config = parseTotp({'TimeOtp-Secret': 'segreto'})!;
      expect(config.period, 30);
      expect(config.digits, 6);
      expect(config.codeAt(at(1700000000)), '056615');
    });
  });

  group('otpauth (KeeWeb, KeePassXC)', () {
    test('valori predefiniti', () {
      final config = parseTotp({
        'otp':
            'otpauth://totp/Prova:utente?secret=JBSWY3DPEHPK3PXP&issuer=Prova',
      })!;
      expect(config.codeAt(at(59)), '996554');
    });

    test('periodo, cifre e algoritmo', () {
      final config = parseTotp({
        'otp': 'otpauth://totp/x?secret=jbswy3dpehpk3pxp&period=60&digits=8&algorithm=SHA1',
      })!;
      expect(config.period, 60);
      expect(config.codeAt(at(1700000000)), '19508648');
    });

    test('Steam', () {
      final config = parseTotp({
        'otp': 'otpauth://totp/Steam:x?secret=JBSWY3DPEHPK3PXP&encoder=steam',
      })!;
      expect(config.steam, isTrue);
      expect(config.codeAt(at(59)), '2YXGV');
    });

    test('HOTP o segreto mancante: configurazione non valida', () {
      expect(
        () => parseTotp({'otp': 'otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP'}),
        throwsA(isA<InvalidTotpConfig>()),
      );
      expect(
        () => parseTotp({'otp': 'otpauth://totp/x?issuer=y'}),
        throwsA(isA<InvalidTotpConfig>()),
      );
    });
  });

  test('KeeOtp: key, step e size', () {
    final config = parseTotp({'otp': 'key=JBSWY3DPEHPK3PXP&step=60&size=8'})!;
    expect(config.codeAt(at(1700000000)), '19508648');
  });

  group('TrayTotp', () {
    test('impostazioni predefinite 30;6', () {
      final config = parseTotp({'TOTP Seed': 'JBSW Y3DP EHPK 3PXP'})!;
      expect(config.codeAt(at(59)), '996554');
    });

    test('Steam con "S"', () {
      final config = parseTotp({
        'TOTP Seed': 'JBSWY3DPEHPK3PXP',
        'TOTP Settings': '30;S',
      })!;
      expect(config.codeAt(at(59)), '2YXGV');
    });

    test('impostazioni non valide', () {
      expect(
        () => parseTotp({
          'TOTP Seed': 'JBSWY3DPEHPK3PXP',
          'TOTP Settings': '30;7',
        }),
        throwsA(isA<InvalidTotpConfig>()),
      );
    });
  });

  test('voce senza TOTP', () {
    expect(parseTotp({'UserName': 'utente', 'Notes': 'otp'}), isNull);
  });

  test('cifre fuori dai limiti o Base32 non valido', () {
    expect(
      () => parseTotp({'TimeOtp-Secret': 'x', 'TimeOtp-Length': '9'}),
      throwsA(isA<InvalidTotpConfig>()),
    );
    expect(
      () => parseTotp({'TimeOtp-Secret-Base32': 'NON-VALIDO!'}),
      throwsA(isA<InvalidTotpConfig>()),
    );
  });

  test('secondi rimanenti', () {
    final config = parseTotp({'TimeOtp-Secret': 'x'})!;
    expect(config.secondsRemaining(at(60)), 30);
    expect(config.secondsRemaining(at(61)), 29);
    expect(config.secondsRemaining(at(89)), 1);
  });

  test('isTotpField', () {
    expect(isTotpField('otp'), isTrue);
    expect(isTotpField('TimeOtp-Period'), isTrue);
    expect(isTotpField('TOTP Seed'), isTrue);
    expect(isTotpField('PIN'), isFalse);
  });
}
