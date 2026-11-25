import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/group/group_view.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:keepass_mobile/shared/ui/entry_tile.dart';
import 'package:keepass_mobile/shared/ui/expandable_section.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/test_database.dart';

void main() {
  for (final locale in [const Locale('it'), const Locale('en')]) {
    testWidgets(
      'Home ${locale.languageCode}: mostra password recenti e contenuti al primo frame',
      (tester) async {
        // given
        final platform = FakeSecureStorage.install();
        final l10n = lookupAppLocalizations(locale);
        final db = newTestDatabase();
        final group = db.createGroup(parent: db.root, name: 'Gruppo di prova');
        final recent = addTestEntry(db, group, {
          EntryFields.title: 'Voce recente',
        });
        addTestEntry(db, db.root, {EntryFields.title: 'Voce ordinaria'});
        final container = await newTestContainer();
        container
            .read(databaseSessionProvider.notifier)
            .open(
              DatabaseSession(
                file: const FileRef(
                  uri: 'file:///prova.kdbx',
                  name: 'prova.kdbx',
                ),
                database: db,
                recentPasswordIds: [itemIdOf(recent)],
              ),
            );

        // when: un solo frame, senza attendere altri aggiornamenti della Home.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: [
                ...GlobalMaterialLocalizations.delegates,
                ...AppLocalizations.localizationsDelegates,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildLightTheme(),
              home: const GroupView(),
            ),
          ),
        );

        // then
        expect(
          find.text(l10n.recentPasswordsTitle).hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Voce recente').hitTestable(), findsOneWidget);
        expect(find.text(group.name).hitTestable(), findsOneWidget);
        expect(find.text('Voce ordinaria').hitTestable(), findsOneWidget);
        expect(platform.options, isEmpty);
        final before = tester.getTopLeft(find.text('Voce recente'));
        final gapBefore =
            tester.getTopLeft(find.text('Voce ordinaria')).dy - before.dy;
        await tester.longPress(find.text('Voce ordinaria'));
        await tester.pumpAndSettle();
        expect(find.text(l10n.recentPasswordsTitle), findsOneWidget);
        expect(tester.getTopLeft(find.text('Voce recente')).dx, before.dx);
        expect(
          tester.getTopLeft(find.text('Voce ordinaria')).dy -
              tester.getTopLeft(find.text('Voce recente')).dy,
          gapBefore,
        );
        final recentTile = find.ancestor(
          of: find.text('Voce recente'),
          matching: find.byType(EntryTile),
        );
        expect(tester.widget<EntryTile>(recentTile).enabled, isFalse);
        expect(
          tester
              .widget<ExpandableSection>(find.byType(ExpandableSection))
              .enabled,
          isFalse,
        );
        await tester.tap(find.text('Voce recente'));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
        final check = tester.widget<Icon>(find.byIcon(Icons.check_circle));
        expect(
          check.color,
          Theme.of(tester.element(recentTile)).colorScheme.primary,
        );
        await tester.tap(find.text('Voce ordinaria'));
        await tester.pumpAndSettle();
        expect(tester.widget<EntryTile>(recentTile).enabled, isTrue);
      },
    );
  }
}
