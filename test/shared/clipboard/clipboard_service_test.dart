import 'dart:async';

import 'package:flutter/services.dart';
import 'package:secure_clipboard/secure_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/clipboard/clipboard_service.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'clear senza codice nativo o con errore: false, nessuna eccezione',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel(
        'io.github.al3x1n0.keepassmobile/secure_clipboard',
      );
      messenger.setMockMethodCallHandler(channel, null);
      expect(await ClipboardService().clear(), isFalse);

      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'x'),
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect(await ClipboardService().clear(), isFalse);
    },
  );

  test('copia tramite il plugin con pulizia dopo 30 secondi', () async {
    final clipboard = FakeClipboard(TestDefaultBinaryMessengerBinding.instance);

    await ClipboardService().copy('valore-segreto');

    expect(clipboard.text, 'valore-segreto');
    expect(clipboard.clearAfter, const Duration(seconds: 30));
  });

  test('clear svuota gli appunti se contengono ancora la copia', () async {
    final clipboard = FakeClipboard(TestDefaultBinaryMessengerBinding.instance);
    final service = ClipboardService();
    await service.copy('valore-segreto');

    expect(await service.clear(), isTrue);
    expect(clipboard.text, '');
  });

  test('clear non tocca gli appunti se l\'utente ha copiato altro', () async {
    final clipboard = FakeClipboard(TestDefaultBinaryMessengerBinding.instance);
    final service = ClipboardService();
    await service.copy('valore-segreto');
    await Clipboard.setData(const ClipboardData(text: 'testo dell\'utente'));

    expect(await service.clear(), isFalse);
    expect(clipboard.text, 'testo dell\'utente');
  });

  test(
    'blocco automatico lascia solo la copia Genera al timeout nativo',
    () async {
      final clipboard = FakeClipboard(
        TestDefaultBinaryMessengerBinding.instance,
      );
      final service = ClipboardService(clearAfter: const Duration(seconds: 10));
      await service.copy('generata-sintetica', generated: true);

      expect(await service.clear(preserveGenerated: true), isFalse);
      expect(clipboard.text, 'generata-sintetica');
      expect(clipboard.clearAfter, const Duration(seconds: 10));
      expect(await service.clear(), isTrue);
      expect(clipboard.text, '');
    },
  );

  test('una copia della voce sostituisce la categoria Genera e si pulisce al blocco', () async {
    final clipboard = FakeClipboard(TestDefaultBinaryMessengerBinding.instance);
    final service = ClipboardService();
    await service.copy('generata-sintetica', generated: true);
    await service.copy('voce-sintetica');

    expect(await service.clear(preserveGenerated: true), isTrue);
    expect(clipboard.text, '');
  });

  test('una copia fallita non conserva la categoria Genera', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var clears = 0;
    messenger.setMockMethodCallHandler(SecureClipboard.channel, (call) async {
      if (call.method == 'copy') throw PlatformException(code: 'test');
      clears++;
      return true;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SecureClipboard.channel, null),
    );
    final service = ClipboardService();
    await expectLater(
      service.copy('sintetica', generated: true),
      throwsA(isA<PlatformException>()),
    );

    expect(await service.clear(preserveGenerated: true), isTrue);
    expect(clears, 1);
  });

  test(
    'blocco durante copia in corso pulisce dopo il completamento nativo',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final copied = Completer<void>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(SecureClipboard.channel, (call) async {
        calls.add(call.method);
        if (call.method == 'copy') {
          await copied.future;
          return null;
        }
        return true;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SecureClipboard.channel, null),
      );
      final service = ClipboardService();
      final copying = service.copy('sintetica', generated: true);
      final clearing = service.clear();
      await pumpEventQueue();
      expect(calls, ['copy']);

      copied.complete();
      await copying;
      expect(await clearing, isTrue);
      expect(calls, ['copy', 'clearOwnCopy']);
    },
  );

  test(
    'cambio timeout durante copia non sostituisce la coda di pulizia',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final copied = Completer<void>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(SecureClipboard.channel, (call) async {
        calls.add(call.method);
        if (call.method == 'copy') {
          await copied.future;
          return null;
        }
        return true;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SecureClipboard.channel, null),
      );
      final container = await newTestContainer();
      addTearDown(container.dispose);
      final service = container.read(clipboardServiceProvider);
      final copying = service.copy('sintetica', generated: true);
      await container
          .read(appSettingsProvider.notifier)
          .update(const AppSettings(clipboardTimeout: Duration(seconds: 10)));
      expect(container.read(clipboardServiceProvider), same(service));
      final clearing = container.read(clipboardServiceProvider).clear();
      await pumpEventQueue();
      expect(calls, ['copy']);

      copied.complete();
      await copying;
      expect(await clearing, isTrue);
      expect(calls, ['copy', 'clearOwnCopy']);
      expect(service.clearAfter, const Duration(seconds: 10));
    },
  );

  test('il tempo di pulizia segue l\'impostazione', () async {
    final clipboard = FakeClipboard(TestDefaultBinaryMessengerBinding.instance);
    final container = await newTestContainer();
    addTearDown(container.dispose);
    await container
        .read(appSettingsProvider.notifier)
        .update(const AppSettings(clipboardTimeout: Duration(seconds: 10)));

    await container.read(clipboardServiceProvider).copy('valore-segreto');

    expect(clipboard.clearAfter, const Duration(seconds: 10));
  });

  test('il blocco del database svuota gli appunti', () async {
    final clipboard = FakeClipboard(TestDefaultBinaryMessengerBinding.instance);
    final container = await newTestContainer();
    addTearDown(container.dispose);

    await container.read(clipboardServiceProvider).copy('valore-segreto');
    container.read(databaseSessionProvider.notifier).lock();
    await pumpEventQueue();

    expect(clipboard.text, '');
  });
}
