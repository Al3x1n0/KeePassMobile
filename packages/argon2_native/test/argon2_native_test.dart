import 'dart:convert';

import 'package:argon2_native/argon2_native.dart';
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // Vettori di src/test.c dell'implementazione di riferimento PHC.
  final pwd = utf8.encode('password');
  final salt = utf8.encode('somesalt');

  test('libreria nativa disponibile', () {
    expect(isArgon2NativeAvailable, isTrue);
  });

  test('Argon2i v1.3, t=2, m=64 MiB, p=1', () {
    final out = argon2Hash(
      password: pwd,
      salt: salt,
      iterations: 2,
      memoryKiB: 1 << 16,
      parallelism: 1,
      type: Argon2NativeType.i,
    );
    expect(
      _hex(out),
      'c1628832147d9720c5bd1cfd61367078729f6dfb6f8fea9ff98158e0d7816ed0',
    );
  });

  test('Argon2id v1.3, t=2, m=256 KiB, p=2', () {
    final out = argon2Hash(
      password: pwd,
      salt: salt,
      iterations: 2,
      memoryKiB: 1 << 8,
      parallelism: 2,
      type: Argon2NativeType.id,
    );
    expect(
      _hex(out),
      '6d093c501fd5999645e0ea3bf620d7b8be7fd2db59c20d9fff9539da2bf57037',
    );
  });

  test('Argon2i v1.0, t=2, m=256 KiB, p=2', () {
    final out = argon2Hash(
      password: pwd,
      salt: salt,
      iterations: 2,
      memoryKiB: 1 << 8,
      parallelism: 2,
      type: Argon2NativeType.i,
      version: 0x10,
    );
    expect(
      _hex(out),
      'b6c11560a6a9d61eac706b79a2f97d68b4463aa3ad87e00c07e2b01e90c564fb',
    );
  });

  test('parametri non validi: eccezione senza dati sensibili', () {
    expect(
      () => argon2Hash(
        password: pwd,
        salt: const [1, 2], // salt troppo corto
        iterations: 1,
        memoryKiB: 8,
        parallelism: 1,
        type: Argon2NativeType.d,
      ),
      throwsA(
        isA<Argon2NativeException>()
            .having((e) => e.code, 'code', lessThan(0))
            .having((e) => e.toString(), 'toString', isNot(contains('pass'))),
      ),
    );
  });
}
