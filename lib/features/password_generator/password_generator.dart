// Riferimento: Keepass2Android, src/keepass2android-app/password/PasswordGenerator.cs,
// revisione 8b60a72fc8eb23e8580df053a49ca813a686c838. Il file originale reca
// Copyright 2013 Philipp Crocoll ed è basato su Keepassdroid, Copyright Brian
// Pellin; GPL versione 3 o successiva, senza garanzia. Comportamento ricreato
// in Dart nel 2026, con modifiche; vedi LICENSE.

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'wordlist.dart';

/// Gruppi di caratteri del generatore, come PasswordGenerator.cs di
/// Keepass2Android (stessi caratteri e stesso ordine).
enum CharGroup {
  upperCase('ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
  lowerCase('abcdefghijklmnopqrstuvwxyz'),
  digits('0123456789'),
  minus('-'),
  underline('_'),
  space(' '),
  specials('!"#\$%&\'*+,./:;=?@\\^`'),
  specialsExtended('§©®¢°±¹²³¼½×÷«âéïñù¡¿»¦Ø'),
  brackets('[]{}()<>');

  const CharGroup(this.chars);

  final String chars;
}

/// Caratteri che si confondono facilmente, esclusi se richiesto.
const lookAlikeChars = 'Il1|8B6GO0';

/// Maiuscole e minuscole delle parole della passphrase.
enum WordCase { lowercase, uppercase, pascalCase }

/// Opzioni della parte a caratteri casuali.
@immutable
class CharsetOptions {
  const CharsetOptions({
    this.length = 0,
    this.groups = const {},
    this.excludeLookAlike = false,
    this.atLeastOneFromEachGroup = false,
  });

  final int length;
  final Set<CharGroup> groups;
  final bool excludeLookAlike;
  final bool atLeastOneFromEachGroup;

  bool get isEnabled => length > 0;

  /// Gruppi selezionati, nell'ordine di [CharGroup], senza i caratteri
  /// ambigui se richiesto. I gruppi rimasti vuoti vengono scartati.
  List<String> get effectiveGroups => [
    for (final g in CharGroup.values)
      if (groups.contains(g))
        excludeLookAlike
            ? g.chars.split('').where((c) => !lookAlikeChars.contains(c)).join()
            : g.chars,
  ].where((g) => g.isNotEmpty).toList();

  CharsetOptions copyWith({
    int? length,
    Set<CharGroup>? groups,
    bool? excludeLookAlike,
    bool? atLeastOneFromEachGroup,
  }) => CharsetOptions(
    length: length ?? this.length,
    groups: groups ?? this.groups,
    excludeLookAlike: excludeLookAlike ?? this.excludeLookAlike,
    atLeastOneFromEachGroup:
        atLeastOneFromEachGroup ?? this.atLeastOneFromEachGroup,
  );

  Map<String, Object> toJson() => {
    'length': length,
    'groups': [for (final g in groups) g.name],
    'excludeLookAlike': excludeLookAlike,
    'atLeastOneFromEachGroup': atLeastOneFromEachGroup,
  };

  static CharsetOptions fromJson(Map<String, Object?> json) => CharsetOptions(
    length: (json['length'] as num?)?.toInt() ?? 0,
    groups: {
      for (final name in (json['groups'] as List?) ?? const [])
        ...CharGroup.values.where((g) => g.name == name),
    },
    excludeLookAlike: json['excludeLookAlike'] == true,
    atLeastOneFromEachGroup: json['atLeastOneFromEachGroup'] == true,
  );

  @override
  bool operator ==(Object other) =>
      other is CharsetOptions &&
      other.length == length &&
      setEquals(other.groups, groups) &&
      other.excludeLookAlike == excludeLookAlike &&
      other.atLeastOneFromEachGroup == atLeastOneFromEachGroup;

  @override
  int get hashCode => Object.hash(
    length,
    Object.hashAllUnordered(groups),
    excludeLookAlike,
    atLeastOneFromEachGroup,
  );
}

/// Opzioni della passphrase.
@immutable
class PassphraseOptions {
  const PassphraseOptions({
    this.wordCount = 0,
    this.separator = ' ',
    this.wordCase = WordCase.lowercase,
  });

  final int wordCount;
  final String separator;
  final WordCase wordCase;

  bool get isEnabled => wordCount > 0;

  PassphraseOptions copyWith({
    int? wordCount,
    String? separator,
    WordCase? wordCase,
  }) => PassphraseOptions(
    wordCount: wordCount ?? this.wordCount,
    separator: separator ?? this.separator,
    wordCase: wordCase ?? this.wordCase,
  );

  Map<String, Object> toJson() => {
    'wordCount': wordCount,
    'separator': separator,
    'wordCase': wordCase.name,
  };

  static PassphraseOptions fromJson(Map<String, Object?> json) =>
      PassphraseOptions(
        wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
        separator: json['separator'] as String? ?? ' ',
        wordCase: WordCase.values.firstWhere(
          (c) => c.name == json['wordCase'],
          orElse: () => WordCase.lowercase,
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is PassphraseOptions &&
      other.wordCount == wordCount &&
      other.separator == separator &&
      other.wordCase == wordCase;

  @override
  int get hashCode => Object.hash(wordCount, separator, wordCase);
}

/// Opzioni complete: passphrase seguita (se attivi entrambi) dai caratteri
/// casuali, come CombinedKeyOptions di Keepass2Android.
@immutable
class GeneratorOptions {
  const GeneratorOptions({
    this.charset = const CharsetOptions(),
    this.passphrase = const PassphraseOptions(),
  });

  final CharsetOptions charset;
  final PassphraseOptions passphrase;

  /// Almeno una parte attiva e, se attivi, i caratteri hanno un insieme non
  /// vuoto.
  bool get isValid =>
      (charset.isEnabled || passphrase.isEnabled) &&
      (!charset.isEnabled || charset.effectiveGroups.isNotEmpty);

  GeneratorOptions copyWith({
    CharsetOptions? charset,
    PassphraseOptions? passphrase,
  }) => GeneratorOptions(
    charset: charset ?? this.charset,
    passphrase: passphrase ?? this.passphrase,
  );

  Map<String, Object> toJson() => {
    'charset': charset.toJson(),
    'passphrase': passphrase.toJson(),
  };

  static GeneratorOptions fromJson(Map<String, Object?> json) =>
      GeneratorOptions(
        charset: CharsetOptions.fromJson(
          (json['charset'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
        passphrase: PassphraseOptions.fromJson(
          (json['passphrase'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is GeneratorOptions &&
      other.charset == charset &&
      other.passphrase == passphrase;

  @override
  int get hashCode => Object.hash(charset, passphrase);
}

/// Profili predefiniti di Keepass2Android (GeneratePasswordActivity).
const generatorProfiles = <String, GeneratorOptions>{
  'Simple12': GeneratorOptions(
    charset: CharsetOptions(
      length: 12,
      groups: {CharGroup.upperCase, CharGroup.lowerCase, CharGroup.digits},
      excludeLookAlike: true,
      atLeastOneFromEachGroup: true,
    ),
  ),
  'Special12': GeneratorOptions(
    charset: CharsetOptions(
      length: 12,
      groups: {
        CharGroup.upperCase,
        CharGroup.lowerCase,
        CharGroup.digits,
        CharGroup.specials,
        CharGroup.brackets,
      },
      excludeLookAlike: true,
      atLeastOneFromEachGroup: true,
    ),
  ),
  'Password64': GeneratorOptions(
    charset: CharsetOptions(
      length: 64,
      groups: {...CharGroup.values},
      atLeastOneFromEachGroup: true,
    ),
  ),
  'Passphrase7': GeneratorOptions(passphrase: PassphraseOptions(wordCount: 7)),
  'Passphrase5Plus': GeneratorOptions(
    passphrase: PassphraseOptions(wordCount: 5, wordCase: WordCase.pascalCase),
    charset: CharsetOptions(
      length: 2,
      groups: {CharGroup.digits, CharGroup.specials},
      excludeLookAlike: true,
      atLeastOneFromEachGroup: true,
    ),
  ),
};

/// Opzioni iniziali senza preferenze salvate (Keepass2Android: 12 caratteri,
/// maiuscole, minuscole e cifre).
const defaultGeneratorOptions = GeneratorOptions(
  charset: CharsetOptions(
    length: 12,
    groups: {CharGroup.upperCase, CharGroup.lowerCase, CharGroup.digits},
  ),
);

/// Opzioni non valide: nessuna parte attiva o nessun carattere disponibile.
final class InvalidGeneratorOptions implements Exception {
  const InvalidGeneratorOptions();
}

/// Genera un valore come PasswordGenerator.GeneratePassword di
/// Keepass2Android, con un generatore crittografico e indici senza bias.
String generateSecret(GeneratorOptions options, {Random? random}) {
  if (!options.isValid) throw const InvalidGeneratorOptions();
  final rng = random ?? Random.secure();
  final out = StringBuffer();

  final passphrase = options.passphrase;
  if (passphrase.isEnabled) {
    for (var i = 0; i < passphrase.wordCount; i++) {
      final word = passphraseWords[rng.nextInt(passphraseWords.length)];
      out.write(switch (passphrase.wordCase) {
        WordCase.lowercase => word.toLowerCase(),
        WordCase.uppercase => word.toUpperCase(),
        WordCase.pascalCase => word[0].toUpperCase() + word.substring(1),
      });
      // Come Keepass2Android: separatore anche dopo l'ultima parola se segue
      // la parte a caratteri casuali.
      if (i < passphrase.wordCount - 1 || options.charset.isEnabled) {
        out.write(passphrase.separator);
      }
    }
  }

  final charset = options.charset;
  if (charset.isEnabled) {
    final groups = charset.effectiveGroups;
    final all = groups.join();
    final chars = <String>[
      if (charset.atLeastOneFromEachGroup)
        for (final g in groups) g[rng.nextInt(g.length)],
    ];
    while (chars.length < charset.length) {
      chars.add(all[rng.nextInt(all.length)]);
    }
    if (charset.atLeastOneFromEachGroup) {
      // Fisher-Yates: i caratteri obbligatori non restano in testa.
      for (var i = chars.length - 1; i >= 1; i--) {
        final j = rng.nextInt(i + 1);
        final tmp = chars[i];
        chars[i] = chars[j];
        chars[j] = tmp;
      }
    }
    out.write(chars.join());
  }
  return out.toString();
}

/// Entropia del processo di generazione in bit (non del singolo valore):
/// ogni parola vale log2(7776), ogni carattere log2(dimensione
/// dell'insieme). Con "almeno uno per gruppo" i caratteri obbligatori valgono
/// log2 della dimensione del proprio gruppo.
double generationEntropyBits(GeneratorOptions options) {
  if (!options.isValid) return 0;
  double log2(num x) => log(x) / ln2;
  var bits = 0.0;
  if (options.passphrase.isEnabled) {
    bits += options.passphrase.wordCount * log2(passphraseWords.length);
  }
  final charset = options.charset;
  if (charset.isEnabled) {
    final groups = charset.effectiveGroups;
    final all = groups.join().length;
    var free = charset.length;
    if (charset.atLeastOneFromEachGroup) {
      for (final g in groups) {
        bits += log2(g.length);
      }
      free -= groups.length;
    }
    if (free > 0) bits += free * log2(all);
  }
  return bits;
}

