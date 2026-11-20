/// Argon2 nativo (implementazione di riferimento PHC) via FFI.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/bindings.dart' as native;

/// Variante di Argon2 (valori di `argon2_type`).
enum Argon2NativeType {
  /// Argon2d.
  d(0),

  /// Argon2i.
  i(1),

  /// Argon2id.
  id(2);

  const Argon2NativeType(this.value);

  /// Valore numerico usato dalla libreria C.
  final int value;
}

/// Errore restituito dalla libreria nativa (codice `ARGON2_*`).
///
/// Il messaggio non contiene mai password, salt o risultato.
final class Argon2NativeException implements Exception {
  /// Crea l'eccezione con il [code] restituito da `argon2_hash`.
  const Argon2NativeException(this.code);

  /// Codice di errore Argon2 (negativo).
  final int code;

  @override
  String toString() => 'Argon2NativeException: codice $code';
}

/// Calcola Argon2 grezzo (senza codifica) con la libreria nativa.
///
/// [memoryKiB] è il costo di memoria in KiB, [version] è `0x10` o `0x13`.
/// La copia nativa della password viene azzerata prima di liberare la memoria.
Uint8List argon2Hash({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  required int memoryKiB,
  required int parallelism,
  required Argon2NativeType type,
  int version = 0x13,
  int length = 32,
}) {
  final pwdPtr = calloc<Uint8>(password.isEmpty ? 1 : password.length);
  final saltPtr = calloc<Uint8>(salt.isEmpty ? 1 : salt.length);
  final outPtr = calloc<Uint8>(length);
  try {
    pwdPtr.asTypedList(password.length).setAll(0, password);
    saltPtr.asTypedList(salt.length).setAll(0, salt);
    final rc = native.argon2Hash(
      iterations,
      memoryKiB,
      parallelism,
      pwdPtr,
      password.length,
      saltPtr,
      salt.length,
      outPtr,
      length,
      nullptr,
      0,
      type.value,
      version,
    );
    if (rc != 0) throw Argon2NativeException(rc);
    return Uint8List.fromList(outPtr.asTypedList(length));
  } finally {
    pwdPtr
        .asTypedList(password.isEmpty ? 1 : password.length)
        .fillRange(0, password.isEmpty ? 1 : password.length, 0);
    outPtr.asTypedList(length).fillRange(0, length, 0);
    calloc
      ..free(pwdPtr)
      ..free(saltPtr)
      ..free(outPtr);
  }
}

/// `true` se la libreria nativa è caricata e funziona su questa piattaforma.
///
/// Esegue un calcolo minimo; il risultato viene memorizzato.
bool get isArgon2NativeAvailable => _available ??= _probe();

bool? _available;

bool _probe() {
  try {
    argon2Hash(
      password: const [1],
      salt: List.filled(8, 2),
      iterations: 1,
      memoryKiB: 8,
      parallelism: 1,
      type: Argon2NativeType.d,
    );
    return true;
  } on Object {
    // ArgumentError o UnsupportedError se l'asset nativo manca.
    return false;
  }
}
