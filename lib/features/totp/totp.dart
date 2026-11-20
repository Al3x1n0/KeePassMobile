import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Algoritmo HMAC del TOTP.
enum TotpAlgorithm { sha1, sha256, sha512 }

/// Configurazione TOTP di una voce (TotpData di Keepass2Android).
@immutable
class TotpConfig {
  const TotpConfig({
    required this.secret,
    this.period = 30,
    this.digits = 6,
    this.algorithm = TotpAlgorithm.sha1,
    this.steam = false,
  });

  final Uint8List secret;
  final int period;

  /// Cifre del codice; per Steam sempre 5 caratteri.
  final int digits;
  final TotpAlgorithm algorithm;

  /// Codice Steam Guard (alfabeto di 26 caratteri) invece delle cifre RFC 6238.
  final bool steam;

  /// Codice valido all'istante [now].
  String codeAt(DateTime now) => _code(secret, _counter(now), this);

  /// Secondi alla scadenza del codice, da [period] a 1.
  int secondsRemaining(DateTime now) =>
      period - (now.millisecondsSinceEpoch ~/ 1000) % period;

  int _counter(DateTime now) => (now.millisecondsSinceEpoch ~/ 1000) ~/ period;

  @override
  bool operator ==(Object other) =>
      other is TotpConfig &&
      listEquals(other.secret, secret) &&
      other.period == period &&
      other.digits == digits &&
      other.algorithm == algorithm &&
      other.steam == steam;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(secret), period, digits, algorithm, steam);
}

/// Campi della voce che contengono la configurazione TOTP, nei formati letti
/// da Keepass2Android.
abstract final class TotpFields {
  /// KeeOtp (`key=...&step=...&size=...`) e KeeWeb/KeePassXC (`otpauth://`).
  static const otp = 'otp';

  /// TrayTotp: seme Base32 e impostazioni `periodo;cifre` (`S` = Steam).
  static const traySeed = 'TOTP Seed';
  static const traySettings = 'TOTP Settings';

  /// KeePass 2.47+.
  static const keePassPrefix = 'TimeOtp-';
}

/// La voce ha campi TOTP ma la configurazione non è utilizzabile.
final class InvalidTotpConfig implements Exception {
  const InvalidTotpConfig();
}

/// Configurazione TOTP letta dai campi della voce, provando i formati
/// nell'ordine di Kp2aTotp (TrayTotp, KeeOtp, KeeWeb/otpauth, KeePass 2).
/// `null` se la voce non ha TOTP; [InvalidTotpConfig] se i campi ci sono ma
/// non sono validi.
TotpConfig? parseTotp(Map<String, String> fields) {
  var found = false;
  for (final parser in [_tray, _keeOtp, _otpAuth, _keePass2]) {
    final result = parser(fields);
    if (result == null) continue;
    found = true;
    if (result case final TotpConfig config) return config;
  }
  if (found) throw const InvalidTotpConfig();
  return null;
}

/// Campo che fa parte della configurazione TOTP.
bool isTotpField(String key) =>
    key == TotpFields.otp ||
    key == TotpFields.traySeed ||
    key == TotpFields.traySettings ||
    key.startsWith(TotpFields.keePassPrefix);

// Ogni parser restituisce: null se il formato non è presente, una
// TotpConfig se valido, InvalidTotpConfig se presente ma non valido.
typedef _Parsed = Object?;

_Parsed _tray(Map<String, String> fields) {
  final seed = fields[TotpFields.traySeed]?.trim() ?? '';
  if (seed.isEmpty) return null;
  final settings = (fields[TotpFields.traySettings] ?? '30;6').split(';');
  final period = settings.isNotEmpty ? int.tryParse(settings[0].trim()) : null;
  final length = settings.length > 1 ? settings[1].trim() : null;
  if (period == null || period <= 0 || period > 60) {
    return const InvalidTotpConfig();
  }
  if (length != '6' && length != '8' && length != 'S') {
    return const InvalidTotpConfig();
  }
  final secret = base32Decode(seed);
  if (secret == null || secret.isEmpty) return const InvalidTotpConfig();
  return _build(
    secret,
    period,
    length == 'S' ? 5 : int.parse(length!),
    null,
    steam: length == 'S',
  );
}

_Parsed _keeOtp(Map<String, String> fields) {
  final data = fields[TotpFields.otp]?.trim() ?? '';
  if (data.isEmpty || data.startsWith('otpauth://')) return null;
  final params = <String, String>{};
  for (final part in data.split('&')) {
    final pieces = part.split('=');
    if (pieces.length != 2) continue;
    params[pieces[0]] = pieces[1].replaceAll('%3d', '=').replaceAll('%3D', '=');
  }
  final key = params['key'];
  if (key == null) return const InvalidTotpConfig();
  final secret = base32Decode(key);
  if (secret == null || secret.isEmpty) return const InvalidTotpConfig();
  return _build(
    secret,
    int.tryParse(params['step'] ?? '') ?? 30,
    int.tryParse(params['size'] ?? '') ?? 6,
    switch (params['otpHashMode']?.toLowerCase()) {
      'sha256' => TotpAlgorithm.sha256,
      'sha512' => TotpAlgorithm.sha512,
      _ => TotpAlgorithm.sha1,
    },
  );
}

_Parsed _otpAuth(Map<String, String> fields) {
  final data = fields[TotpFields.otp]?.trim() ?? '';
  if (!data.startsWith('otpauth://')) return null;
  final uri = Uri.tryParse(data);
  if (uri == null || uri.host.toLowerCase() != 'totp') {
    return const InvalidTotpConfig();
  }
  final q = uri.queryParameters;
  final secret = base32Decode(q['secret'] ?? '');
  if (secret == null || secret.isEmpty) return const InvalidTotpConfig();
  final steam = q['encoder']?.toLowerCase() == 'steam';
  return _build(
    secret,
    int.tryParse(q['period'] ?? '') ?? 30,
    steam ? 5 : int.tryParse(q['digits'] ?? '') ?? 6,
    switch (q['algorithm']?.toUpperCase()) {
      'SHA256' => TotpAlgorithm.sha256,
      'SHA512' => TotpAlgorithm.sha512,
      _ => TotpAlgorithm.sha1,
    },
    steam: steam,
  );
}

_Parsed _keePass2(Map<String, String> fields) {
  const p = TotpFields.keePassPrefix;
  Uint8List? secret;
  var present = false;
  for (final (suffix, decode) in <(String, Uint8List? Function(String))>[
    ('Secret', (s) => Uint8List.fromList(utf8.encode(s))),
    ('Secret-Hex', _hexDecode),
    ('Secret-Base32', base32Decode),
    ('Secret-Base64', _base64Decode),
  ]) {
    final value = fields['$p$suffix'];
    if (value == null || value.isEmpty) continue;
    present = true;
    secret = decode(value);
    break;
  }
  if (!present) return null;
  if (secret == null || secret.isEmpty) return const InvalidTotpConfig();
  final period = int.tryParse(fields['${p}Period'] ?? '') ?? 0;
  final length = int.tryParse(fields['${p}Length'] ?? '') ?? 0;
  return _build(
    secret,
    period == 0 ? 30 : period,
    length == 0 ? 6 : length,
    switch (fields['${p}Algorithm']) {
      'HMAC-SHA-256' => TotpAlgorithm.sha256,
      'HMAC-SHA-512' => TotpAlgorithm.sha512,
      _ => TotpAlgorithm.sha1,
    },
  );
}

/// Stessi limiti di TOTPProvider di Keepass2Android: periodo > 0, cifre 4–8.
_Parsed _build(
  Uint8List secret,
  int period,
  int digits,
  TotpAlgorithm? algorithm, {
  bool steam = false,
}) {
  if (period <= 0 || digits < 4 || digits > 8) {
    return const InvalidTotpConfig();
  }
  return TotpConfig(
    secret: secret,
    period: period,
    digits: digits,
    algorithm: algorithm ?? TotpAlgorithm.sha1,
    steam: steam,
  );
}

const _steamChars = '23456789BCDFGHJKMNPQRTVWXY';

String _code(Uint8List secret, int counter, TotpConfig config) {
  final message = Uint8List(8);
  ByteData.sublistView(message).setUint64(0, counter);
  final hash = switch (config.algorithm) {
    TotpAlgorithm.sha1 => sha1,
    TotpAlgorithm.sha256 => sha256,
    TotpAlgorithm.sha512 => sha512,
  };
  final mac = Hmac(hash, secret).convert(message).bytes;
  final offset = mac.last & 0x0f;
  var full =
      ((mac[offset] & 0x7f) << 24) |
      (mac[offset + 1] << 16) |
      (mac[offset + 2] << 8) |
      mac[offset + 3];
  if (config.steam) {
    final code = StringBuffer();
    for (var i = 0; i < config.digits; i++) {
      code.write(_steamChars[full % _steamChars.length]);
      full ~/= _steamChars.length;
    }
    return code.toString();
  }
  var mod = 1;
  for (var i = 0; i < config.digits; i++) {
    mod *= 10;
  }
  return (full % mod).toString().padLeft(config.digits, '0');
}

/// Base32 (RFC 4648) tollerante: ignora spazi, trattini e `=`, accetta le
/// minuscole. `null` se contiene caratteri non validi.
Uint8List? base32Decode(String input) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final clean = input.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
  final out = BytesBuilder(copy: false);
  var buffer = 0;
  var bits = 0;
  for (final char in clean.split('')) {
    final value = alphabet.indexOf(char);
    if (value < 0) return null;
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.addByte((buffer >> bits) & 0xff);
    }
  }
  return out.toBytes();
}

Uint8List? _hexDecode(String input) {
  final clean = input.replaceAll(RegExp(r'\s'), '');
  if (clean.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(clean)) {
    return null;
  }
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

Uint8List? _base64Decode(String input) {
  try {
    return base64.decode(input.replaceAll(RegExp(r'\s'), ''));
  } on FormatException {
    return null;
  }
}
