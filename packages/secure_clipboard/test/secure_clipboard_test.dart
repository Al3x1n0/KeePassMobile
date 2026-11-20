import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_clipboard/secure_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const clipboard = SecureClipboard();
  final calls = <MethodCall>[];

  void reply(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(SecureClipboard.channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(
    () => messenger.setMockMethodCallHandler(SecureClipboard.channel, null),
  );

  test('copy: inoltra testo e durata in millisecondi', () async {
    reply((_) => null);

    await clipboard.copy('valore', clearAfter: const Duration(seconds: 30));

    expect(calls.single.method, 'copy');
    expect(calls.single.arguments, {'text': 'valore', 'clearAfterMs': 30000});
  });

  test('clearOwnCopy: risultato del codice nativo', () async {
    reply((_) => true);
    expect(await clipboard.clearOwnCopy(), isTrue);

    reply((_) => false);
    expect(await clipboard.clearOwnCopy(), isFalse);

    reply((_) => null);
    expect(await clipboard.clearOwnCopy(), isFalse);
  });
}
