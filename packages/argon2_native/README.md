# argon2_native

Argon2 (implementazione di riferimento [PHC](https://github.com/P-H-C/phc-winner-argon2),
release `20190702`) per Dart via FFI.

La libreria C viene compilata dal build hook (`hook/build.dart`, `native_toolchain_c`)
durante `flutter build` / `flutter test`: niente CocoaPods, Gradle/CMake o Rust.
Si usa `ref.c` (portabile) e non `opt.c` (richiede SSE).

| Piattaforma | Verifica |
|---|---|
| macOS (test) | `dart test`: vettori di `src/test.c` |
| Android | `libargon2_native.so` incluso nell'APK |
| iOS | `argon2_native.framework` incluso nell'app |

Sorgenti C in `src/argon2/` invariati, licenza CC0 1.0 o Apache 2.0 (`src/argon2/LICENSE`).
