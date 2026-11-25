import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/password_check/password_strength.dart';

void main() {
  for (final value in [
    '',
    'a',
    'A9!kL2?',
    '123456',
    'qwerty',
    'aaaa',
    'ababab',
    '🔐🔐🔐🔐🔐🔐🔐',
  ]) {
    test('meno di otto caratteri: molto debole (${value.runes.length})', () {
      expect(
        evaluatePasswordStrength(value).level,
        PasswordStrengthLevel.veryWeak,
      );
      expect(
        evaluatePasswordStrength(value).reason,
        PasswordWeaknessReason.tooShort,
      );
    });
  }
  for (final value in [
    '123456789012345678901234567890',
    '121212121212',
    'aaaaaaaaaaaa',
    'aaaabbbbccccdddd',
    '1111222233334444',
    'abababababababab',
    'abcdabcdabcd',
    'qwertyuiop',
    'Password123!',
    'P@ssw0rd1!',
    '1og1n2026!',
    'WELCOME2026!',
    'letme1n123!',
    '43219876',
    'hvrnktps',
    'Kp7!vR9?',
  ]) {
    test('valore prevedibile o limitato resta debole: $value', () {
      expect(evaluatePasswordStrength(value).isWeak, isTrue);
    });
  }
  for (final value in [
    'Password123!',
    'P@ssw0rd1!',
    '1og1n2026!',
    'qwertyuiop',
    'abcdEFgh',
  ]) {
    test('pattern riconosciuto: $value', () {
      expect(
        evaluatePasswordStrength(value).reason,
        PasswordWeaknessReason.commonPattern,
      );
    });
  }
  for (final value in [
    'vK9!tR4?mZ',
    '9071846205983617402859163847',
    'passwordvK9!tR4?mZ',
    '🌙fiume-albero-montagna-luna',
    'X7@kN2#vR9!',
    'cavallo verde montagna luna',
    'river-cloud-copper-orbit',
    'fiumealberomontagnaluna',
  ]) {
    test('casuale o passphrase sufficiente: $value', () {
      expect(evaluatePasswordStrength(value).isWeak, isFalse);
    });
  }
}
