import 'package:app_security/app_security.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(
    () => messenger.setMockStreamHandler(AppSecurity.screenOffChannel, null),
  );

  test('screenOff: un evento per ogni notifica del codice nativo', () async {
    messenger.setMockStreamHandler(
      AppSecurity.screenOffChannel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          events
            ..success('screen_off')
            ..success('screen_off')
            ..endOfStream();
        },
      ),
    );

    final events = await const AppSecurity().screenOff().toList();

    expect(events, hasLength(2));
  });

  test('screenOff: annullare l\'ascolto ferma il codice nativo', () async {
    var cancelled = false;
    messenger.setMockStreamHandler(
      AppSecurity.screenOffChannel,
      MockStreamHandler.inline(
        onListen: (_, _) {},
        onCancel: (_) => cancelled = true,
      ),
    );

    final subscription = const AppSecurity().screenOff().listen((_) {});
    await pumpEventQueue();
    await subscription.cancel();
    await pumpEventQueue();

    expect(cancelled, isTrue);
  });

  group('hasStrongBiometrics', () {
    tearDown(
      () => messenger.setMockMethodCallHandler(AppSecurity.methodChannel, null),
    );

    test('risposta del codice nativo', () async {
      messenger.setMockMethodCallHandler(
        AppSecurity.methodChannel,
        (call) async => call.method == 'hasStrongBiometrics',
      );

      expect(await const AppSecurity().hasStrongBiometrics(), isTrue);
    });

    test('errore del codice nativo: false', () async {
      messenger.setMockMethodCallHandler(
        AppSecurity.methodChannel,
        (_) async => throw PlatformException(code: 'x'),
      );

      expect(await const AppSecurity().hasStrongBiometrics(), isFalse);
    });

    test('plugin assente: false', () async {
      expect(await const AppSecurity().hasStrongBiometrics(), isFalse);
    });
  });

  group('notifica del database aperto', () {
    const texts = OpenNotificationTexts(
      channel: 'canale',
      title: 'titolo',
      text: 'testo',
      lock: 'blocca',
    );

    tearDown(() {
      messenger
        ..setMockMethodCallHandler(AppSecurity.methodChannel, null)
        ..setMockStreamHandler(AppSecurity.notificationLockChannel, null);
    });

    test(
      'mostra: passa i testi al codice nativo e ne riporta l\'esito',
      () async {
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(AppSecurity.methodChannel, (
          call,
        ) async {
          calls.add(call);
          return true;
        });

        final shown = await const AppSecurity().showOpenNotification(texts);
        await const AppSecurity().hideOpenNotification();

        expect(shown, isTrue);
        expect(calls.map((c) => c.method), [
          'showOpenNotification',
          'hideOpenNotification',
        ]);
        expect(calls.first.arguments, {
          'channel': 'canale',
          'title': 'titolo',
          'text': 'testo',
          'lock': 'blocca',
        });
      },
    );

    test('notifiche disattivate o plugin assente: false', () async {
      expect(await const AppSecurity().showOpenNotification(texts), isFalse);
      expect(
        await const AppSecurity().requestNotificationPermission(),
        isFalse,
      );

      messenger.setMockMethodCallHandler(
        AppSecurity.methodChannel,
        (_) async => false,
      );
      expect(await const AppSecurity().showOpenNotification(texts), isFalse);
    });

    test('permesso: risposta del codice nativo', () async {
      messenger.setMockMethodCallHandler(
        AppSecurity.methodChannel,
        (call) async => call.method == 'requestNotificationPermission',
      );

      expect(await const AppSecurity().requestNotificationPermission(), isTrue);
    });

    test('"Blocca": un evento per ogni tocco nella notifica', () async {
      messenger.setMockStreamHandler(
        AppSecurity.notificationLockChannel,
        MockStreamHandler.inline(
          onListen: (_, events) {
            events
              ..success('lock')
              ..endOfStream();
          },
        ),
      );

      final events = await const AppSecurity().notificationLock().toList();

      expect(events, hasLength(1));
    });
  });
}
