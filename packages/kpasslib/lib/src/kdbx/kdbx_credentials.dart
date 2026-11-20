import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:xml/xml.dart';

import '../crypto/crypto_utils.dart';
import '../utils/xml_utils.dart';

/// A challenge response function type.
typedef KdbxChallengeResponse = List<int> Function(List<int> challenge);

/// A composite key that has already been through the KDF (AES-KDF or Argon2),
/// bound to the KDF parameters of the file by [fingerprint].
///
/// Allows reopening the database without running the KDF again (biometric
/// unlock, memory-limited iOS autofill extension). It is as sensitive as the
/// master key: store it only in the Keychain/Keystore.
///
/// Added by KeePassMobile.
class KdbxTransformedKey {
  /// Constructs a [KdbxTransformedKey].
  KdbxTransformedKey({required this.key, required List<int> fingerprint})
      : fingerprint = List.unmodifiable(fingerprint);

  /// The KDF output (32 bytes), protected in memory.
  final ProtectedData key;

  /// Fingerprint of the KDF parameters the key belongs to.
  final List<int> fingerprint;
}

/// A KDBX master key credentials
class KdbxCredentials {
  final ProtectedData? _passwordHash;
  final ProtectedData? _keyFileHash;
  final KdbxChallengeResponse? _challengeResponse;
  final bool _hasRawKey;

  /// Transformed key used instead of the KDF when its fingerprint matches.
  final KdbxTransformedKey? transformedKey;

  /// Constructs [KdbxCredentials] from [password], key file [keyData]
  /// and [challengeResponse].
  ///
  /// If [transformedKey] is given and still valid, the KDF is skipped.
  KdbxCredentials(
      {ProtectedData? password,
      List<int>? keyData,
      KdbxChallengeResponse? challengeResponse,
      this.transformedKey})
      : _passwordHash = _getPasswordHash(password),
        _keyFileHash = _getKeyFileHash(keyData),
        _challengeResponse = challengeResponse,
        _hasRawKey = true;

  /// Credentials made of a transformed key only.
  ///
  /// The database can be opened and saved, but the KDF salt is not rotated on
  /// save (that would require the original composite key).
  KdbxCredentials.fromTransformedKey(KdbxTransformedKey this.transformedKey,
      {KdbxChallengeResponse? challengeResponse})
      : _passwordHash = null,
        _keyFileHash = null,
        _challengeResponse = challengeResponse,
        _hasRawKey = false;

  /// Whether password and/or key file are available to run the KDF.
  bool get hasRawKey => _hasRawKey;

  /// The hash of the credentials without challenge response.
  get hash => getHash();

  /// The hash of the credentials with optional [challenge] response.
  List<int> getHash({List<int>? challenge}) {
    final challengeResp = getChallengeResponse(challenge);

    final allBytes = <int>[];
    final passwordHash = _passwordHash;
    final keyFileHash = _keyFileHash;

    if (passwordHash != null) {
      allBytes.addAll(passwordHash.bytes);
    }

    if (keyFileHash != null) {
      allBytes.addAll(keyFileHash.bytes);
    }

    if (challengeResp != null) {
      allBytes.addAll(challengeResp);
    }

    var hash = sha256.convert(allBytes).bytes;
    CryptoUtils.wipeData(allBytes);
    return hash;
  }

  /// Calculates challenge response for requested [challenge].
  List<int>? getChallengeResponse(List<int>? challenge) {
    final response = _challengeResponse;
    if (response == null || challenge == null) {
      return null;
    }

    final result = response(challenge);
    final hash = sha256.convert(result).bytes;
    CryptoUtils.wipeData(result);
    return hash;
  }

  /// Generates key file random data with provided [version].
  static List<int> createRandomKeyFile({required int version}) =>
      createKeyFileWithHash(
        bytes: CryptoUtils.randomBytes(32),
        version: version,
      );

  /// Constructs key file with provided [bytes] and [version].
  static List<int> createKeyFileWithHash(
      {required List<int> bytes, required int version}) {
    final versionString = version == 2 ? '2.0' : '1.00';
    final doc = XmlUtils.create('KeyFile', extraAttributes: '');
    final meta = XmlElement(
      XmlName(XmlElem.meta),
      [],
      [XmlElement(XmlName(XmlElem.version))..innerText = versionString],
    );
    final data = XmlElement(XmlName(XmlElem.data));

    if (version == 1) {
      data.innerText = base64.encode(bytes);
    } else {
      final hash = sha256.convert(bytes).bytes;
      final hashString = hex.encode(hash.sublist(0, 4)).toUpperCase();
      final slices = bytes.slices(4).slices(4);
      final keyString = slices
          .map((e) => e
              .map((e) => hex.encode(e).toUpperCase())
              .fold('', (prev, e) => '$prev $e')
              .trim())
          .fold('', (prev, e) => '$prev\n      $e');

      data.attributes.add(XmlAttribute(XmlName(XmlAttr.hash), hashString));
      data.innerText = '$keyString\n';
    }

    final key = XmlElement(XmlName(XmlElem.key), [], [data]);
    doc.rootElement.children.addAll([meta, key]);

    return utf8.encode(doc.toXmlString(
      pretty: true,
      preserveWhitespace: (_) => true,
    ));
  }

  static ProtectedData? _getPasswordHash(ProtectedData? password) {
    return password == null ? null : ProtectedData.fromBytes(password.hash);
  }

  static ProtectedData? _getKeyFileHash(List<int>? keyData) {
    if (keyData == null) {
      return null;
    }

    var keyDataStr = '';

    try {
      keyDataStr = utf8.decode(keyData);
      final xml = XmlDocument.parse(keyDataStr);
      final meta = xml.rootElement.getElement(XmlElem.meta);
      if (meta == null) {
        throw UnsupportedValueError('xml key-file without meta element');
      }

      final version = meta.getElement(XmlElem.version);
      if (version == null) {
        throw UnsupportedValueError('xml key-file without version element');
      }
      final majorVersion = version.innerText.split('.').first.trim();

      final key = xml.rootElement.getElement(XmlElem.key);
      if (key == null) {
        throw UnsupportedValueError('xml key-file without key element');
      }

      final data = key.getElement(XmlElem.data);
      if (data == null) {
        throw UnsupportedValueError('xml key-file without data element');
      }

      switch (majorVersion) {
        case '1':
          return ProtectedData.fromBytes(base64.decode(data.innerText));
        case '2':
          final keyFileData =
              hex.decode(data.innerText.replaceAll(RegExp('\\s+'), ''));
          final keyFileDataHash = data.getAttribute(XmlAttr.hash);
          if (keyFileDataHash != null) {
            final computedHash = sha256.convert(keyFileData).bytes;
            final computedHashStr = hex.encode(computedHash.sublist(0, 4));
            if (computedHashStr.toUpperCase() !=
                keyFileDataHash.toUpperCase()) {
              throw FileCorruptedError('xml key-file data hash mismatch');
            }
          }
          return ProtectedData.fromBytes(keyFileData);

        default:
          throw UnsupportedValueError('xml key-file version');
      }
    } on KdbxError catch (_) {
      rethrow;
    } catch (_) {}

    if (keyDataStr.length == 64) {
      try {
        final bytes = hex.decode(keyDataStr);
        return ProtectedData.fromBytes(bytes);
      } catch (_) {}
    }

    if (keyData.length == 32) {
      return ProtectedData.fromBytes(keyData);
    }

    final hash = sha256.convert(keyData).bytes;
    return ProtectedData.fromBytes(hash);
  }
}
