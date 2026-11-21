import 'package:document_access/document_access.dart';
import 'package:flutter/foundation.dart';

/// Record atomici in memoria con lo stesso confronto CAS del plugin nativo.
class MemoryCacheDocuments extends DocumentAccess {
  final records = <String, Uint8List>{};
  bool unavailable = false;

  @override
  Future<List<String>> listRemoteCacheIds() async {
    if (unavailable) throw const DocumentAccessException('io');
    return records.keys.toList();
  }

  @override
  Future<bool> deleteRemoteCache(String id, Uint8List expectedToken) async {
    if (unavailable) throw const DocumentAccessException('io');
    final current = records[id];
    if (current == null ||
        current.length < 32 ||
        !listEquals(current.sublist(0, 32), expectedToken)) {
      return false;
    }
    records.remove(id);
    return true;
  }

  @override
  Future<Uint8List?> readRemoteCache(String id) async {
    if (unavailable) throw const DocumentAccessException('io');
    final bytes = records[id];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<bool> writeRemoteCache(
    String id,
    Uint8List record, {
    Uint8List? expectedToken,
  }) async {
    if (unavailable) throw const DocumentAccessException('io');
    final current = records[id];
    if (expectedToken == null
        ? current != null
        : current == null ||
              !listEquals(current.sublist(0, 32), expectedToken)) {
      return false;
    }
    records[id] = Uint8List.fromList(record);
    return true;
  }
}
