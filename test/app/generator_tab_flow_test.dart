import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/database_navigation_bar.dart';
import 'package:keepass_mobile/app/router.dart';
import 'package:keepass_mobile/app/routes.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view.dart';
import 'package:keepass_mobile/features/password_generator/generator_view.dart';
import 'package:keepass_mobile/features/password_generator/generator_view_model.dart';
import 'package:keepass_mobile/features/password_generator/password_generator.dart';
import 'package:keepass_mobile/features/password_generator/pending_generated_password.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/item_edits.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_database.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('it'),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = newTestDatabase();
  database.createGroup(parent: database.root, name: 'Servizi');
  final trash = database.createGroup(parent: database.root, name: 'Cestino');
  database.meta.recycleBinUuid = trash.uuid;
  database.createGroup(parent: trash, name: 'Gruppo eliminato');
  final container = await newTestContainer();
  container
      .read(databaseSessionProvider.notifier)
      .open(
        DatabaseSession(
          file: const FileRef(uri: 'file:///prova.kdbx', name: 'prova.kdbx'),
          database: database,
        ),
      );
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        routerConfig: container.read(routerProvider),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _tab(String label) => find.descendant(
  of: find.byType(DatabaseNavigationBar),
  matching: find.text(label),
);

Finder _iconButton(String tooltip) => find
    .ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton))
    .first;

void main() {
  final l10n = lookupAppLocalizations(const Locale('it'));

  testWidgets('Genera: barra persistente, copia sicura e ritorno tra le tab', (
    tester,
  ) async {
    final clipboard = FakeClipboard(TestDefaultBinaryMessengerBinding.instance);
    final container = await _pump(tester);
    final bar = tester.element(find.byType(DatabaseNavigationBar));

    await tester.tap(_tab(l10n.navigationGenerate));
    await tester.pumpAndSettle();

    expect(tester.element(find.byType(DatabaseNavigationBar)), same(bar));
    expect(
      tester
          .widget<DatabaseNavigationBar>(find.byType(DatabaseNavigationBar))
          .generatorSelected,
      isTrue,
    );
    expect(find.byType(BackButton), findsNothing);
    expect(find.text(l10n.generatorUse), findsNothing);
    expect(find.byTooltip(l10n.generatorSaveAsEntry), findsOneWidget);
    final copy = find.byTooltip(l10n.entryCopy(l10n.entryPassword));
    final regenerate = find.byTooltip(l10n.generatorRegenerate);
    expect(
      tester.getCenter(copy).dx,
      lessThan(tester.getCenter(regenerate).dx),
    );
    final generated = container.read(tabGeneratorViewModelProvider).value;
    await tester.tap(copy);
    await tester.pump();
    expect(clipboard.text, generated);
    expect(clipboard.clearAfter, const Duration(seconds: 30));
    expect(find.text(l10n.entryCopied(30)), findsOneWidget);

    await tester.tap(_tab(l10n.settingsTitle));
    await tester.pumpAndSettle();
    await tester.tap(_tab(l10n.navigationGenerate));
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(DatabaseNavigationBar)), same(bar));
    expect(container.read(tabGeneratorViewModelProvider).value, generated);
    await tester.tap(_tab(l10n.navigationHome));
    await tester.pumpAndSettle();
    expect(container.read(routerProvider).state.uri.path, AppRoutes.database);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'floppy: sceglie anche root, esclude cestino e precompila la voce',
    (tester) async {
      final container = await _pump(tester);
      await tester.tap(_tab(l10n.navigationGenerate));
      await tester.pumpAndSettle();
      final generated = container.read(tabGeneratorViewModelProvider).value;
      final database = container.read(databaseSessionProvider)!.database;

      await tester.tap(find.byTooltip(l10n.generatorSaveAsEntry));
      await tester.pumpAndSettle();
      expect(find.text(l10n.generatorChooseGroup), findsOneWidget);
      expect(find.widgetWithText(ListTile, database.root.name), findsOneWidget);
      expect(find.text('${database.root.name} / Servizi'), findsOneWidget);
      expect(find.textContaining('Cestino'), findsNothing);
      expect(find.textContaining('Gruppo eliminato'), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, database.root.name));
      await tester.pumpAndSettle();

      final editor = tester.widget<EntryEditView>(find.byType(EntryEditView));
      expect(editor.target.groupId, itemIdOf(database.root));
      expect(editor.target.templateId, isNull);
      expect(editor.target.fromGenerator, isTrue);
      final password = find.widgetWithText(TextFormField, l10n.entryPassword);
      expect(
        tester.widget<TextFormField>(password).controller!.text,
        generated,
      );
      expect(find.byType(DatabaseNavigationBar), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(GeneratorView), findsOneWidget);
      expect(container.read(tabGeneratorViewModelProvider).value, generated);
      expect(
        container.read(pendingGeneratedPasswordProvider)!.protectedValue.text,
        generated,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selettore modale: Usa restituisce il valore senza barra', (
    tester,
  ) async {
    final container = await _pump(tester);
    final result = container
        .read(routerProvider)
        .push<String>(AppRoutes.generator);
    await tester.pumpAndSettle();
    expect(find.byType(DatabaseNavigationBar), findsNothing);
    expect(find.byTooltip(l10n.generatorSaveAsEntry), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    final generated = container.read(generatorViewModelProvider).value;
    await tester.tap(find.text(l10n.generatorUse));
    await tester.pumpAndSettle();
    expect(await result, generated);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('it'), const Locale('en')]) {
    testWidgets(
      'Genera ${locale.languageCode}: compatta con testo 2x e disabilitata senza valore',
      (tester) async {
        final strings = lookupAppLocalizations(locale);
        final container = await _pump(
          tester,
          locale: locale,
          textScaler: TextScaler.linear(2),
        );
        await tester.tap(_tab(strings.navigationGenerate));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final options in [
          const GeneratorOptions(
            charset: CharsetOptions(
              length: 256,
              groups: {CharGroup.lowerCase, CharGroup.digits},
            ),
          ),
          generatorProfiles['Passphrase7']!,
        ]) {
          container
              .read(tabGeneratorViewModelProvider.notifier)
              .update(options);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        final list = find.descendant(
          of: find.byType(GeneratorView),
          matching: find.byType(ListView),
        );
        await tester.drag(list, const Offset(0, -2200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        );
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(
          tester
              .getRect(
                find.widgetWithText(ChoiceChip, strings.generatorCasePascal),
              )
              .bottom,
          lessThan(tester.getRect(find.byType(DatabaseNavigationBar)).top),
        );
        container
            .read(tabGeneratorViewModelProvider.notifier)
            .update(const GeneratorOptions());
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(_iconButton(strings.generatorSaveAsEntry))
              .onPressed,
          isNull,
        );
        await tester.drag(list, const Offset(0, 5000));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                _iconButton(strings.entryCopy(strings.entryPassword)),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('destinazioni nuova voce: nessuna esclusione della root o del gruppo corrente', () {
    final db = newTestDatabase();
    final child = db.createGroup(parent: db.root, name: 'Servizi');
    final trash = db.createGroup(parent: db.root, name: 'Cestino');
    db.meta.recycleBinUuid = trash.uuid;
    final deleted = db.createGroup(parent: trash, name: 'Eliminato');
    expect(
      entryCreationDestinations(db).map((group) => group.id),
      containsAll([itemIdOf(db.root), itemIdOf(child)]),
    );
    expect(
      entryCreationDestinations(db).map((group) => group.id),
      isNot(contains(itemIdOf(trash))),
    );
    expect(
      entryCreationDestinations(db).map((group) => group.id),
      isNot(contains(itemIdOf(deleted))),
    );
  });
}
