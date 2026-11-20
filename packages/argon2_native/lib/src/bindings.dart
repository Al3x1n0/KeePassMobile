// Binding FFI verso la libreria nativa compilata da hook/build.dart.
@DefaultAsset('package:argon2_native/src/bindings.dart')
library;

import 'dart:ffi';

/// `int argon2_hash(t_cost, m_cost, parallelism, pwd, pwdlen, salt, saltlen,
/// hash, hashlen, encoded, encodedlen, type, version)` da `argon2.h`.
@Native<
  Int32 Function(
    Uint32,
    Uint32,
    Uint32,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Char>,
    Size,
    Int32,
    Uint32,
  )
  // isLeaf: false perché il calcolo dura fino a secondi e non deve bloccare il GC.
>(symbol: 'argon2_hash')
external int argon2Hash(
  int tCost,
  int mCost,
  int parallelism,
  Pointer<Uint8> pwd,
  int pwdLen,
  Pointer<Uint8> salt,
  int saltLen,
  Pointer<Uint8> hash,
  int hashLen,
  Pointer<Char> encoded,
  int encodedLen,
  int type,
  int version,
);
