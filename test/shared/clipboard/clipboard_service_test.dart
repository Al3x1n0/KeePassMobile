import 'package:flutter/services.dart';
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
      expect(await const ClipboardService().clear(), isFalse);

      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'x'),
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect(await const ClipboardService().clear(), isFalse);
    },
  );

  test('copia tramite il plugin con pulizia dopo 30 secondi', () async {
    final clipboard = FakeClipboard(TestDefaultBinaryMessengerBinding.instance);

    await const ClipboardService().copy('valore-segreto');

    expect(clipboard.text, 'valore-segreto');
    expect(clipboard.clearAfter, const Duration(seconds: 30));
  });

  test('clear svuota gli appunti se contengono ancora la copia', () async {
    final clipboard = FakeClipboard(TestDefaultBinaryMessengerBinding.instance);
    const service = ClipboardService();
    await service.copy('valore-segreto');

    expect(await service.clear(), isTrue);
    expect(clipboard.text, '');
  });

  test('clear non tocca gli appunti se l\'utente ha copiato altro', () async {
    final clipboard = FakeClipboard(TestDefaultBinaryMessengerBinding.instance);
    const service = ClipboardService();
    await service.copy('valore-segreto');
    await Clipboard.setData(const ClipboardData(text: 'testo dell\'utente'));

    expect(await service.clear(), isFalse);
    expect(clipboard.text, 'testo dell\'utente');
  });

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
