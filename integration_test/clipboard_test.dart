import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:secure_clipboard/secure_clipboard.dart';

/// Plugin secure_clipboard sul dispositivo, con l'app in primo piano.
/// La pulizia in background si verifica pilotando il telefono con adb.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const clipboard = SecureClipboard();

  Future<String?> current() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  testWidgets('copia leggibile e svuotata alla scadenza', (tester) async {
    await clipboard.copy(
      'valore-di-prova',
      clearAfter: const Duration(seconds: 2),
    );
    expect(await current(), 'valore-di-prova');

    await Future<void>.delayed(const Duration(seconds: 4));
    expect(await current(), anyOf(isNull, isEmpty));
  });

  testWidgets('clearOwnCopy svuota la copia dell\'app', (tester) async {
    await clipboard.copy(
      'valore-di-prova',
      clearAfter: const Duration(minutes: 1),
    );

    expect(await clipboard.clearOwnCopy(), isTrue);
    expect(await current(), anyOf(isNull, isEmpty));
  });

  testWidgets('clearOwnCopy non tocca una copia fatta da altri', (
    tester,
  ) async {
    await clipboard.copy(
      'valore-di-prova',
      clearAfter: const Duration(seconds: 2),
    );
    await Clipboard.setData(const ClipboardData(text: 'testo-utente'));

    expect(await clipboard.clearOwnCopy(), isFalse);
    // Anche la pulizia programmata, annullata, non deve toccarla.
    await Future<void>.delayed(const Duration(seconds: 4));
    expect(await current(), 'testo-utente');
    await Clipboard.setData(const ClipboardData(text: ''));
  });

  testWidgets('pulizia programmata non tocca una copia fatta da altri', (
    tester,
  ) async {
    await clipboard.copy(
      'valore-di-prova',
      clearAfter: const Duration(seconds: 2),
    );
    await Clipboard.setData(const ClipboardData(text: 'testo-utente'));

    await Future<void>.delayed(const Duration(seconds: 4));
    expect(await current(), 'testo-utente');
    await Clipboard.setData(const ClipboardData(text: ''));
  });
}
