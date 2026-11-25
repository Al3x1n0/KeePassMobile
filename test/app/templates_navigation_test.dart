import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/database_navigation_bar.dart';
import 'package:keepass_mobile/app/router.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_database.dart';

class _OpeningStorage extends FileStorage {
  int writes = 0;

  @override
  Future<void> write(
    FileRef ref,
    Uint8List bytes, {
    String? expectedVersion,
  }) async {
    writes++;
    throw StateError('scrittura inattesa durante apertura');
  }
}

void main() {
  for (final locale in [const Locale('it'), const Locale('en')]) {
    for (final present in [false, true]) {
      testWidgets(
        'Modelli ${locale.languageCode} presenti=$present: Home, menu, creazione diretta senza barra',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final db = newTestDatabase();
          if (present) {
            final group = db.createGroup(
              parent: db.root,
              name: 'Hidden templates',
            );
            db.meta.entryTemplatesGroup = group.uuid;
            addTestEntry(db, group, {EntryFields.title: 'Custom template'});
            db.createGroup(parent: group, name: 'Imported templates');
          }
          final originalUuid = db.meta.entryTemplatesGroup;
          final storage = _OpeningStorage();
          final container = await newTestContainer(
            overrides: [fileStorageProvider.overrideWithValue(storage)],
          );
          container
              .read(databaseSessionProvider.notifier)
              .open(
                DatabaseSession(
                  file: const FileRef(
                    uri: 'file:///synthetic.kdbx',
                    name: 'synthetic.kdbx',
                  ),
                  database: db,
                ),
              );
          final router = container.read(routerProvider);
          final l10n = lookupAppLocalizations(locale);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp.router(
                locale: locale,
                localizationsDelegates: [
                  ...GlobalMaterialLocalizations.delegates,
                  ...AppLocalizations.localizationsDelegates,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                theme: buildLightTheme(),
                routerConfig: router,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Hidden templates'), findsNothing);
          expect(find.text(l10n.groupEmpty), findsOneWidget);
          await tester.tap(find.byTooltip(l10n.groupMore));
          await tester.pumpAndSettle();
          expect(find.text(l10n.templateGroup), findsOneWidget);
          await tester.tap(find.text(l10n.templateGroup));
          await tester.pumpAndSettle();
          expect(find.text(l10n.templateGroup), findsOneWidget);
          expect(find.byType(DatabaseNavigationBar), findsNothing);
          expect(db.meta.entryTemplatesGroup, originalUuid);
          expect(storage.writes, 0);
          if (present) {
            expect(find.text('Custom template'), findsOneWidget);
            await tester.longPress(find.text('Custom template'));
            await tester.pumpAndSettle();
            expect(find.byIcon(Icons.star_border), findsNothing);
            await tester.tap(find.byTooltip(l10n.cancel));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Imported templates'));
            await tester.pumpAndSettle();
            expect(find.byType(DatabaseNavigationBar), findsNothing);
            router.pop();
            await tester.pumpAndSettle();
          } else {
            expect(find.text(l10n.templatesEmpty), findsOneWidget);
          }
          await tester.tap(find.byType(FloatingActionButton));
          await tester.pumpAndSettle();
          expect(find.byType(EntryEditView), findsOneWidget);
          expect(
            tester
                .widget<EntryEditView>(find.byType(EntryEditView))
                .target
                .creatingTemplate,
            isTrue,
          );
          expect(find.text(l10n.groupAddTitle), findsNothing);
          expect(find.byType(DatabaseNavigationBar), findsNothing);
          expect(db.meta.entryTemplatesGroup, originalUuid);
          expect(storage.writes, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'Cestino ${locale.languageCode}: menu Home e sottogruppo senza barra',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = newTestDatabase();
        final bin = db.recycleBin!;
        final nested = db.createGroup(parent: bin, name: 'Deleted group');
        final container = await newTestContainer();
        container
            .read(databaseSessionProvider.notifier)
            .open(
              DatabaseSession(
                file: const FileRef(
                  uri: 'file:///synthetic.kdbx',
                  name: 'synthetic.kdbx',
                ),
                database: db,
              ),
            );
        final router = container.read(routerProvider);
        final l10n = lookupAppLocalizations(locale);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              locale: locale,
              localizationsDelegates: [
                ...GlobalMaterialLocalizations.delegates,
                ...AppLocalizations.localizationsDelegates,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildLightTheme(),
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(l10n.groupMore));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.dbSettingsRecycleBin));
        await tester.pumpAndSettle();
        expect(find.byType(DatabaseNavigationBar), findsNothing);
        await tester.tap(find.text(nested.name));
        await tester.pumpAndSettle();
        expect(find.text(nested.name), findsOneWidget);
        expect(find.byType(DatabaseNavigationBar), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
