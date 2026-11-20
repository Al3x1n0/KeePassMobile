import 'package:flutter/foundation.dart';
import 'package:kpasslib/kpasslib.dart';

import 'file_storage.dart';

/// Genera un file XML 1.00 leggibile anche dalle versioni di Keepass2Android
/// che interpretano il campo Data come Base64.
Future<PickedFile?> createKeyFile(FileStorage storage) async {
  final bytes = Uint8List.fromList(
    KdbxCredentials.createRandomKeyFile(version: 1),
  );
  try {
    final ref = await storage.create(
      suggestedName: 'keepass.key',
      bytes: bytes,
    );
    if (ref == null) return null;
    final saved = await storage.read(ref);
    if (!listEquals(saved.bytes, bytes)) throw const FileWriteException();
    return PickedFile(ref: saved.ref);
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}
