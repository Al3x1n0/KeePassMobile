import 'dart:math' as math;

enum PasswordStrengthLevel { veryWeak, weak, good, strong }

enum PasswordWeaknessReason {
  tooShort,
  digitsOnly,
  lowVariety,
  commonPattern,
  limitedComplexity,
}

class PasswordStrength {
  const PasswordStrength(this.level, this.reason);
  final PasswordStrengthLevel level;
  final PasswordWeaknessReason? reason;
  bool get isWeak => level.index <= PasswordStrengthLevel.weak.index;
}

/// Local heuristic, not a prediction of cracking time. Keeps no input value.
PasswordStrength evaluatePasswordStrength(String text) {
  final chars = text.runes.toList();
  final length = chars.length;
  if (length < 8) {
    return const PasswordStrength(
      PasswordStrengthLevel.veryWeak,
      PasswordWeaknessReason.tooShort,
    );
  }
  final digits = RegExp(r'^\d+$').hasMatch(text);
  final unique = chars.toSet().length;
  final prefix = List<int>.filled(length, 0);
  for (var i = 1; i < length; i++) {
    var j = prefix[i - 1];
    while (j > 0 && chars[i] != chars[j]) {
      j = prefix[j - 1];
    }
    if (chars[i] == chars[j]) j++;
    prefix[i] = j;
  }
  final period = length - prefix.last;
  final repeated = period < length && length % period == 0;
  var runs = 1;
  for (var i = 1; i < length; i++) {
    if (chars[i] != chars[i - 1]) runs++;
  }
  final repeatedRuns = runs <= length ~/ 2;
  final classes = [
    RegExp('[a-z]'),
    RegExp('[A-Z]'),
    RegExp('[0-9]'),
    RegExp(r'[^a-zA-Z0-9]'),
  ].where((r) => r.hasMatch(text)).length;
  final pool =
      (RegExp('[a-z]').hasMatch(text) ? 26 : 0) +
      (RegExp('[A-Z]').hasMatch(text) ? 26 : 0) +
      (RegExp('[0-9]').hasMatch(text) ? 10 : 0) +
      (RegExp(r'[^a-zA-Z0-9]').hasMatch(text) ? 33 : 0);
  var bits = length * math.log(pool) / math.ln2;
  PasswordWeaknessReason? structuralReason;
  if (unique <= 3 || repeated || repeatedRuns) {
    // Repeating a seed adds little uncertainty, regardless of total length.
    bits = math.min(
      bits,
      unique * math.log(pool) / math.ln2 + math.log(length) / math.ln2,
    );
    structuralReason = PasswordWeaknessReason.lowVariety;
  }
  if (digits) {
    bits *= .6;
    structuralReason = PasswordWeaknessReason.digitsOnly;
  }
  if (structuralReason != null && (length < 12 || bits < 50)) {
    return PasswordStrength(
      bits < 32 ? PasswordStrengthLevel.veryWeak : PasswordStrengthLevel.weak,
      structuralReason,
    );
  }
  final predictable = List<bool>.filled(text.length, false);
  final lower = text.toLowerCase();
  final normalized = lower
      .replaceAll('@', 'a')
      .replaceAll('0', 'o')
      .replaceAll('3', 'e')
      .replaceAll(r'$', 's');
  const words = [
    'password',
    'admin',
    'welcome',
    'letmein',
    'master',
    'dragon',
    'monkey',
    'login',
    'pass',
    'ciao',
    'segreta',
    'secret',
    'qwerty',
    'asdf',
    'zxcv',
    'iloveyou',
    'changeme',
  ];
  void mark(String candidate, String pattern) {
    var start = candidate.indexOf(pattern);
    while (start >= 0) {
      for (
        var i = start;
        i < start + pattern.length && i < predictable.length;
        i++
      ) {
        predictable[i] = true;
      }
      start = candidate.indexOf(pattern, start + 1);
    }
  }

  for (final word in words) {
    final pattern = word
        .split('')
        .map(
          (char) => char == 'i' || char == 'l' ? '[il1]' : RegExp.escape(char),
        )
        .join();
    for (final match in RegExp(pattern).allMatches(normalized)) {
      for (var i = match.start; i < match.end && i < predictable.length; i++) {
        predictable[i] = true;
      }
    }
  }
  for (final sequence in [
    '0123456789',
    'abcdefghijklmnopqrstuvwxyz',
    'qwertyuiop',
    'asdfghjkl',
    'zxcvbnm',
  ]) {
    for (final source in [sequence, sequence.split('').reversed.join()]) {
      // Overlapping four-character windows also cover longer sequences.
      for (var start = 0; start + 4 <= source.length; start++) {
        mark(lower, source.substring(start, start + 4));
      }
    }
  }
  if (predictable.contains(true)) {
    // Numeric affixes and punctuation next to dictionary bases are predictable.
    final remainder = String.fromCharCodes([
      for (var i = 0; i < text.length; i++)
        if (!predictable[i]) text.codeUnitAt(i),
    ]).replaceAll(RegExp(r'^[0-9\W_]+|[0-9\W_]+$'), '');
    bits = math.min(bits, remainder.runes.length * math.log(pool) / math.ln2);
    if (bits < 50) {
      return PasswordStrength(
        bits < 32 ? PasswordStrengthLevel.veryWeak : PasswordStrengthLevel.weak,
        PasswordWeaknessReason.commonPattern,
      );
    }
  }
  if (bits < 50 ||
      (length < 12 && (classes < 2 || length < 10 || classes < 3))) {
    return const PasswordStrength(
      PasswordStrengthLevel.weak,
      PasswordWeaknessReason.limitedComplexity,
    );
  }
  return PasswordStrength(
    bits >= 70 ? PasswordStrengthLevel.strong : PasswordStrengthLevel.good,
    null,
  );
}
