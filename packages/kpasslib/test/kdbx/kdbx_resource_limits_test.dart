import 'dart:collection';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:kpasslib/src/kdbx/kdbx_resource_limits.dart'
    show KdbxDecodedSizeBudget;
import 'package:test/test.dart';

class _SizedInput extends ListBase<int> {
  @override
  int length = KdbxResourceLimits.maxFileBytes + 1;

  @override
  int operator [](int index) => throw StateError('Input letto fuori limite');

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');
}

Matcher _limit(KdbxResourceLimit limit) => isA<KdbxResourceLimitError>()
    .having((error) => error.limit, 'limit', limit);

void main() {
  test('rifiuta un file oltre il limite di dimensione prima di leggerlo', () {
    expect(
      KdbxDatabase.fromBytes(
          data: _SizedInput(), credentials: KdbxCredentials()),
      throwsA(_limit(KdbxResourceLimit.fileSize)),
    );
  });

  test('conteggia la decompressione nel limite aggregato del payload', () {
    final budget = KdbxDecodedSizeBudget(10);
    final compressed = const GZipEncoder().encodeBytes([1, 2, 3, 4]);
    budget.decode(Uint8List(6), compressed: false);
    expect(budget.decode(compressed, compressed: true), [1, 2, 3, 4]);
    expect(
      () => budget.decode(compressed, compressed: true),
      throwsA(_limit(KdbxResourceLimit.payloadSize)),
    );
  });

  test('limita i round AES prima di avviare la KDF', () {
    const max = KdbxResourceLimits.maxAesRounds;
    expect(() => KdbxResourceLimits.checkAesRounds(max), returnsNormally);
    expect(
      () => KdbxResourceLimits.checkAesRounds(max + 1),
      throwsA(_limit(KdbxResourceLimit.kdfCost)),
    );
  });

  test('limita il lavoro Argon2 cumulativo su memoria e passaggi', () {
    void check(int iterations) => KdbxResourceLimits.checkArgon2Cost(
          memory: KdbxResourceLimits.maxArgon2Memory,
          iterations: iterations,
          parallelism: 2,
        );
    expect(() => check(8), returnsNormally);
    expect(() => check(9), throwsA(_limit(KdbxResourceLimit.kdfCost)));
  });
}
