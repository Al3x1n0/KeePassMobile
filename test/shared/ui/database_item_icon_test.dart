import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/ui/database_item_icon.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
  );
  late KdbxDatabase database;
  late KdbxEntry entry;
  late KdbxUuid iconId;

  setUp(() {
    database = newTestDatabase();
    entry = database.createEntry(parent: database.root);
    iconId = KdbxUuid.random();
    entry.customIcon = iconId;
  });

  Future<void> showIcon(WidgetTester tester, {bool expired = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DatabaseItemIcon(
          item: entry,
          database: database,
          expired: expired,
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  testWidgets('mostra l’immagine senza aggiungerla alla cache globale', (
    tester,
  ) async {
    database.meta.customIcons[iconId] = KdbxCustomIcon(data: png);
    final count = PaintingBinding.instance.imageCache.currentSize;
    await showIcon(tester);
    expect(find.byType(RawImage), findsOneWidget);
    expect(PaintingBinding.instance.imageCache.currentSize, count);
    await tester.pumpWidget(const SizedBox());
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('icone mancanti, non valide e troppo grandi usano il ripiego', (
    tester,
  ) async {
    for (final data in [
      <int>[],
      <int>[1, 2, 3],
      Uint8List(1024 * 1024 + 1),
    ]) {
      database.meta.customIcons[iconId] = KdbxCustomIcon(data: data);
      await showIcon(tester);
      expect(find.byType(RawImage), findsNothing);
      expect(find.byIcon(Icons.vpn_key_outlined), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('voce scaduta conserva la sua icona di avviso', (tester) async {
    database.meta.customIcons[iconId] = KdbxCustomIcon(data: png);
    await showIcon(tester, expired: true);
    expect(find.byIcon(Icons.event_busy), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets(
    'un gruppo mostra l’icona personalizzata, il cestino quella dedicata',
    (tester) async {
      final group = database.createGroup(
        parent: database.root,
        name: 'Example',
        icon: KdbxIcon.folder,
      )..customIcon = iconId;
      database.meta.customIcons[iconId] = KdbxCustomIcon(data: png);
      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseItemIcon(item: group, database: database),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseItemIcon(
            item: group,
            database: database,
            recycleBin: true,
          ),
        ),
      );
      expect(find.byType(RawImage), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    },
  );

  testWidgets('immagine personalizzata conservata nella riapertura KDBX', (
    tester,
  ) async {
    database.meta.customIcons[iconId] = KdbxCustomIcon(data: png);
    final reopened = await tester.runAsync(() => saveToTempFile(database));
    final restored = reopened!.$2;
    final restoredEntry = restored.root.entries.single;
    expect(restoredEntry.customIcon, iconId);
    expect(restored.meta.customIcons[iconId]?.data, png);
    await tester.pumpWidget(
      MaterialApp(
        home: DatabaseItemIcon(item: restoredEntry, database: restored),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
  });
}
