import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/password_generator/password_generator.dart';
import 'package:keepass_mobile/features/password_generator/wordlist.dart';

void main() {
  final random = Random(42);

  test('lista di parole di Keepass2Android: 7776 parole distinte', () {
    expect(passphraseWords, hasLength(7776));
    expect(passphraseWords.toSet(), hasLength(7776));
  });

  test('i profili predefiniti sono validi e generano la lunghezza attesa', () {
    for (final MapEntry(:key, :value) in generatorProfiles.entries) {
      expect(value.isValid, isTrue, reason: key);
      expect(generateSecret(value, random: random), isNotEmpty, reason: key);
    }
    expect(
      generateSecret(generatorProfiles['Simple12']!, random: random),
      hasLength(12),
    );
    expect(
      generateSecret(generatorProfiles['Password64']!, random: random),
      hasLength(64),
    );
  });

  test('usa solo i caratteri dei gruppi scelti', () {
    const options = GeneratorOptions(
      charset: CharsetOptions(length: 200, groups: {CharGroup.digits}),
    );
    expect(
      generateSecret(options, random: random),
      matches(RegExp(r'^\d{200}$')),
    );
  });

  test('almeno uno per gruppo: ogni gruppo compare sempre', () {
    const options = GeneratorOptions(
      charset: CharsetOptions(
        length: 4,
        groups: {
          CharGroup.upperCase,
          CharGroup.lowerCase,
          CharGroup.digits,
          CharGroup.brackets,
        },
        atLeastOneFromEachGroup: true,
      ),
    );
    for (var i = 0; i < 300; i++) {
      final value = generateSecret(options, random: random);
      expect(value, matches(RegExp(r'[A-Z]')));
      expect(value, matches(RegExp(r'[a-z]')));
      expect(value, matches(RegExp(r'\d')));
      expect(value, matches(RegExp(r'[\[\]{}()<>]')));
    }
  });

  test('esclude i caratteri simili', () {
    const options = GeneratorOptions(
      charset: CharsetOptions(
        length: 500,
        groups: {CharGroup.upperCase, CharGroup.lowerCase, CharGroup.digits},
        excludeLookAlike: true,
      ),
    );
    final value = generateSecret(options, random: random);
    for (final c in lookAlikeChars.split('')) {
      expect(value.contains(c), isFalse, reason: c);
    }
  });

  test('passphrase: numero di parole, separatore e maiuscole', () {
    const base = PassphraseOptions(wordCount: 5, separator: '-');
    final lower = generateSecret(
      const GeneratorOptions(passphrase: base),
      random: random,
    );
    final words = lower.split('-');
    expect(words, hasLength(5));
    expect(words.every(passphraseWords.contains), isTrue);

    final upper = generateSecret(
      GeneratorOptions(passphrase: base.copyWith(wordCase: WordCase.uppercase)),
      random: random,
    );
    expect(upper, upper.toUpperCase());

    final pascal = generateSecret(
      GeneratorOptions(
        passphrase: base.copyWith(wordCase: WordCase.pascalCase, separator: ''),
      ),
      random: random,
    );
    expect(pascal, matches(RegExp(r'^([A-Z][a-z\-]*){5}$')));
  });

  test('passphrase seguita dai caratteri casuali (Passphrase5Plus)', () {
    final value = generateSecret(
      generatorProfiles['Passphrase5Plus']!,
      random: random,
    );
    final parts = value.split(' ');
    expect(parts, hasLength(6));
    expect(parts.last, hasLength(2));
    expect(parts.last, matches(RegExp(r'\d')));
  });

  test('opzioni non valide', () {
    expect(const GeneratorOptions().isValid, isFalse);
    const noChars = GeneratorOptions(charset: CharsetOptions(length: 8));
    expect(noChars.isValid, isFalse);
    expect(
      () => generateSecret(noChars),
      throwsA(isA<InvalidGeneratorOptions>()),
    );
    expect(generationEntropyBits(noChars), 0);
  });

  test('entropia: gruppi senza caratteri simili e caratteri obbligatori', () {
    double log2(num x) => log(x) / ln2;
    // Senza Il1|8B6GO0: 22 maiuscole, 25 minuscole, 6 cifre.
    final expected = log2(22) + log2(25) + log2(6) + 9 * log2(53);
    expect(
      generationEntropyBits(generatorProfiles['Simple12']!),
      closeTo(expected, 1e-9),
    );
    expect(
      generationEntropyBits(generatorProfiles['Passphrase7']!),
      closeTo(7 * log2(7776), 1e-9),
    );
  });

  test('opzioni salvate e rilette in JSON', () {
    for (final options in generatorProfiles.values) {
      expect(GeneratorOptions.fromJson(options.toJson()), options);
    }
    expect(GeneratorOptions.fromJson(const {}), const GeneratorOptions());
  });
}
