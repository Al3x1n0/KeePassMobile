import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compila l'implementazione di riferimento di Argon2 (PHC, CC0/Apache-2.0)
/// come libreria nativa dell'app. Si usa `ref.c` (portabile) e non `opt.c`
/// (richiede SSE, non disponibile su ARM).
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final targetOS = input.config.code.targetOS;

    await CBuilder.library(
      name: 'argon2_native',
      assetName: 'src/bindings.dart',
      sources: const [
        'src/argon2/src/argon2.c',
        'src/argon2/src/core.c',
        'src/argon2/src/encoding.c',
        'src/argon2/src/ref.c',
        'src/argon2/src/thread.c',
        'src/argon2/src/blake2/blake2b.c',
      ],
      includes: const ['src/argon2/include', 'src/argon2/src'],
      defines: {
        // Le funzioni pubbliche devono essere esportate dalla libreria.
        if (targetOS == OS.windows) 'ARGON2_PUBLIC': '__declspec(dllexport)',
      },
    ).run(input: input, output: output);
  });
}
