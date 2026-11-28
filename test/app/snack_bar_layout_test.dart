import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/database_navigation_bar.dart';
import 'package:keepass_mobile/app/database_navigation_shell.dart';
import 'package:keepass_mobile/app/routes.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/entry/entry_view.dart';
import 'package:keepass_mobile/features/group/group_view.dart';
import 'package:keepass_mobile/features/password_generator/generator_view.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/ui/app_snack_bar.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_database.dart';

Finder _surface() => find.descendant(
  of: find.byType(SnackBar),
  matching: find.byWidgetPredicate(
    (widget) => widget is Material && widget.shape is RoundedRectangleBorder,
  ),
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('it'));
  for (final dark in [false, true]) {
    for (final page in ['generator', 'group', 'entry']) {
      for (final keyboard in [false, true]) {
        testWidgets(
          '$page scuro $dark tastiera $keyboard: feedback flottante senza sovrapposizioni',
          (tester) async {
            // given
            tester.view.physicalSize = const Size(360, 720);
            tester.view.devicePixelRatio = 1;
            tester.view.viewPadding = const FakeViewPadding(bottom: 24);
            tester.view.padding = FakeViewPadding(bottom: keyboard ? 0 : 24);
            tester.view.viewInsets = FakeViewPadding(
              bottom: keyboard ? 240 : 0,
            );
            addTearDown(tester.view.reset);
            FakeClipboard(tester.binding);
            final db = newTestDatabase();
            final entry = addTestEntry(db, db.root, {
              EntryFields.title: 'Prova',
              EntryFields.userName: 'utente-di-prova',
            });
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
                  ),
                );
            final Widget child = switch (page) {
              'generator' => const GeneratorView(showDatabaseNavigation: true),
              'group' => const GroupView(),
              _ => EntryView(entryId: itemIdOf(entry)),
            };
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  theme: dark ? buildDarkTheme() : buildLightTheme(),
                  locale: const Locale('it'),
                  localizationsDelegates: [
                    ...GlobalMaterialLocalizations.delegates,
                    ...AppLocalizations.localizationsDelegates,
                  ],
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: page == 'entry'
                      ? child
                      : DatabaseNavigationShell(
                          location: page == 'generator'
                              ? AppRoutes.generate
                              : AppRoutes.database,
                          child: child,
                        ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final context = tester.element(find.byWidget(child));
            final messenger = ScaffoldMessenger.of(context);
            final theme = Theme.of(context);
            expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
            final scheme = theme.colorScheme;
            final light = scheme.inverseSurface.computeLuminance();
            final foreground = scheme.onInverseSurface.computeLuminance();
            final ratio = light > foreground
                ? (light + .05) / (foreground + .05)
                : (foreground + .05) / (light + .05);
            expect(ratio, greaterThanOrEqualTo(4.5));

            // when: usa la vera azione di copia dove disponibile.
            Future<void> copy({bool settle = true}) async {
              if (page == 'generator') {
                await tester.tap(
                  find.byTooltip(l10n.entryCopy(l10n.entryPassword)),
                );
              } else if (page == 'entry') {
                await tester.tap(
                  find.widgetWithText(ListTile, l10n.entryUserName),
                );
              } else {
                messenger.showAppSnackBar(
                  const SnackBar(content: Text('Feedback')),
                );
              }
              if (settle) {
                await tester.pumpAndSettle();
              } else {
                await tester.pump();
              }
            }

            await copy();
            final bounds = tester.getRect(_surface());
            final material = tester.widget<Material>(_surface());
            expect(
              (material.shape! as RoundedRectangleBorder).borderRadius,
              BorderRadius.circular(16),
            );
            expect(bounds.left, 16);
            expect(bounds.right, 344);
            expect(
              bounds.bottom,
              lessThanOrEqualTo(720 - (keyboard ? 240 : 24) - 16),
            );
            if (page != 'entry') {
              final capsule = find.descendant(
                of: find.byType(DatabaseNavigationBar),
                matching: find.byType(BackdropFilter),
              );
              expect(
                bounds.bottom,
                lessThanOrEqualTo(tester.getRect(capsule).top - 16),
              );
            }
            if (page == 'group') {
              expect(
                bounds.bottom,
                lessThanOrEqualTo(
                  tester.getRect(find.byType(FloatingActionButton)).top - 16,
                ),
              );
            }

            // then: l'ultimo messaggio sostituisce subito quello corrente e la coda.
            messenger.showSnackBar(const SnackBar(content: Text('In attesa')));
            for (var tap = 0; tap < 3; tap++) {
              await copy(settle: false);
            }
            await tester.pumpAndSettle();
            expect(find.text('In attesa'), findsNothing);
            messenger.removeCurrentSnackBar();
            await tester.pumpAndSettle();
            expect(find.byType(SnackBar), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
