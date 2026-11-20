import 'dart:io';
import 'dart:typed_data';

import 'package:keepass_mobile/shared/storage/file_storage.dart';

/// Crea i file in una cartella temporanea al posto del selettore del sistema.
class FakeCreateStorage extends FileStorage {
  FakeCreateStorage({this.cancel = false});

  final bool cancel;
  final dir = Directory.systemTemp.createTempSync('keepass_mobile_create');
  String? suggestedName;

  @override
  Future<FileRef?> create({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    this.suggestedName = suggestedName;
    if (cancel) return null;
    final file = File('${dir.path}/$suggestedName')..writeAsBytesSync(bytes);
    return FileRef(uri: file.uri.toString(), name: suggestedName);
  }
}
