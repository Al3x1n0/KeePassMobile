import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

/// Selettore che restituisce un file in memoria, a turno.
class _Picker extends FilePickerService {
  final files = <PickedFile>[];

  @override
  Future<PickedFile?> pick() async => files.isEmpty ? null : files.removeAt(0);
}

class _Storage extends FileStorage {
  final released = <FileRef>[];

  @override
  Future<void> release(FileRef ref) async => released.add(ref);
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late File file;

  setUp(() async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
    entry.binaries = {
      'pixel.png': db.binaries.add(
        PlainBinary(
          data: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNg+M8'
            'AAAICAQB7CYF4AAAAAElFTkSuQmCC',
          ),
          compressed: false,
        ),
      ),
    };
    final dir = Directory.systemTemp.createTempSync('keepass_mobile_5d');
    file = File('${dir.path}/prova.kdbx')..writeAsBytesSync(await db.save());
  });

  testWidgets(
    'allegato aggiunto, troppo grande rifiutato, anteprima del testo',
    (tester) async {
      final picker = _Picker()
        ..files.addAll([
          PickedFile(
            ref: const FileRef(uri: 'content://docs/big', name: 'big.bin'),
            bytes: Uint8List(AppLimits.attachmentBytes + 1),
          ),
          PickedFile(
            ref: const FileRef(uri: 'content://docs/nota', name: 'nota.txt'),
            bytes: Uint8List.fromList(utf8.encode('testo di prova')),
          ),
        ]);
      final storage = _Storage();
      SharedPreferences.setMockInitialValues({
        RecentFilesRepository.storageKey: [
          jsonEncode(RecentFile(database: fileRefOf(file)).toJson()),
        ],
      });
      final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            filePickerServiceProvider.overrideWithValue(picker),
            fileStorageProvider.overrideWithValue(storage),
          ],
          child: const KeePassMobileApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('prova.kdbx'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), testMasterKey);
      await tester.tap(find.text(l10n.unlockButton));
      await pumpUntilFound(tester, find.text('Voce'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voce'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.entryEdit));
      await tester.pumpAndSettle();

      final add = find.text(l10n.entryEditAttachmentAdd);
      await tester.scrollUntilVisible(
        add,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.textContaining('exceeds the maximum size'), findsOneWidget);
      expect(find.text('big.bin'), findsNothing);
      // L'avviso copre il pulsante: lo si chiude prima di riprovare.
      ScaffoldMessenger.of(tester.element(add)).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('nota.txt'), findsOneWidget);
      expect(storage.released.map((r) => r.name), ['big.bin', 'nota.txt']);

      await tester.tap(find.byTooltip(l10n.entryEditSave));
      // Il pulsante Modifica c'è solo nel dettaglio: il salvataggio è finito.
      await pumpUntilFound(tester, find.byTooltip(l10n.entryEdit));
      await tester.pumpAndSettle();
      final db = (await tester.runAsync(() => reopenFile(file)))!;
      expect(db.root.allEntries.single.binaries.keys, [
        'pixel.png',
        'nota.txt',
      ]);

      await tester.scrollUntilVisible(find.text('nota.txt'), 200);
      await tester.tap(find.text('nota.txt'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('testo di prova')),
        findsOneWidget,
      );
      expect(find.byType(SelectableText), findsNothing);
      await tester.tap(find.text(l10n.close));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('pixel.png'));
      await tester.tap(find.text('pixel.png'));
      await pumpUntilFound(
        tester,
        find.byWidgetPredicate(
          (widget) => widget is RawImage && widget.image != null,
        ),
      );
      await tester.pumpAndSettle();
      final preview = find.descendant(of: sheet, matching: find.byType(Image));
      final element = tester.element(preview);
      final image = tester.widget<Image>(preview).image;
      final config = createLocalImageConfiguration(element);
      expect(
        (await image.obtainCacheStatus(configuration: config))?.untracked,
        isTrue,
      );

      ProviderScope.containerOf(element)
          .read(databaseSessionProvider.notifier)
          .lock();
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
      expect(
        (await image.obtainCacheStatus(configuration: config))?.untracked,
        isTrue,
      );
    },
  );
}
