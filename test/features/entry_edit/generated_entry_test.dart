import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view_model.dart';
import 'package:keepass_mobile/features/password_generator/generator_view_model.dart';
import 'package:keepass_mobile/features/password_generator/password_generator.dart';
import 'package:keepass_mobile/features/password_generator/pending_generated_password.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creazione da Genera: voce standard con password, anche con modelli presenti', () async {
    final database = newTestDatabase();
    database.meta.defaultUser = 'cliente';
    final templates = database.createGroup(
      parent: database.root,
      name: 'Modelli',
    );
    database.meta.entryTemplatesGroup = templates.uuid;
    addTestEntry(database, templates, {
      EntryFields.title: 'Modello',
      EntryFields.password: 'password-modello-sintetica',
      'Campo modello': 'Da non copiare',
    });
    final container = await newTestContainer();
    const file = FileRef(uri: 'file:///prova.kdbx', name: 'prova.kdbx');
    container
        .read(databaseSessionProvider.notifier)
        .open(DatabaseSession(file: file, database: database));
    container
        .read(pendingGeneratedPasswordProvider.notifier)
        .replace(file, defaultGeneratorOptions, 'generata-sintetica');
    final target = EntryEditTarget.create(
      itemIdOf(database.root),
      fromGenerator: true,
    );

    final initial = container.read(entryInitialDraftProvider(target))!;

    expect(initial.password, 'generata-sintetica');
    expect(initial.userName, 'cliente');
    expect(initial.title, isEmpty);
    expect(initial.custom, isEmpty);
    expect(initial.attachments, isEmpty);
    expect(container.read(pendingGeneratedPasswordProvider), isNotNull);
  });

  test(
    'salvataggio effettivo: file riapribile con password e stato RAM azzerato',
    () async {
      final (file, database) = await saveToTempFile(newTestDatabase());
      addTearDown(() => file.parent.deleteSync(recursive: true));
      final container = await newTestContainer(file: file, database: database);
      container.listen(tabGeneratorViewModelProvider, (_, _) {});
      final generated = container.read(tabGeneratorViewModelProvider).value;
      await Future<void>.delayed(Duration.zero);
      final protected = container
          .read(pendingGeneratedPasswordProvider)!
          .protectedValue;
      final target = EntryEditTarget.create(
        itemIdOf(database.root),
        fromGenerator: true,
      );
      container.listen(entryEditViewModelProvider(target), (_, _) {});
      final initial = container.read(entryInitialDraftProvider(target))!;

      final id = await container
          .read(entryEditViewModelProvider(target).notifier)
          .save(
            EntryDraft(title: 'Servizio sintetico', password: initial.password),
          );

      expect(id, isNotNull);
      final reopened = await reopenFile(file);
      final saved = findEntry(reopened, id!)!;
      expect(entryField(saved, EntryFields.password), generated);
      expect(saved.fields[EntryFields.password], isA<ProtectedTextField>());
      expect(container.read(pendingGeneratedPasswordProvider), isNull);
      expect(protected.bytes.every((value) => value == 0), isTrue);
      expect(container.read(tabGeneratorViewModelProvider).value, isEmpty);
      container.read(tabGeneratorViewModelProvider.notifier).regenerate();
      expect(container.read(tabGeneratorViewModelProvider).isValid, isTrue);
    },
  );

  test(
    'salvataggio fallito: password in sospeso disponibile per riprovare',
    () async {
      final database = newTestDatabase();
      final container = await newTestContainer();
      const file = FileRef(
        uri: 'file:///inesistente/prova.kdbx',
        name: 'prova.kdbx',
      );
      container
          .read(databaseSessionProvider.notifier)
          .open(DatabaseSession(file: file, database: database));
      container
          .read(pendingGeneratedPasswordProvider.notifier)
          .replace(file, defaultGeneratorOptions, 'generata-sintetica');
      final target = EntryEditTarget.create(
        itemIdOf(database.root),
        fromGenerator: true,
      );
      container.listen(entryEditViewModelProvider(target), (_, _) {});

      final id = await container
          .read(entryEditViewModelProvider(target).notifier)
          .save(
            const EntryDraft(
              title: 'Servizio sintetico',
              password: 'generata-sintetica',
            ),
          );

      expect(id, isNull);
      expect(
        container.read(pendingGeneratedPasswordProvider)!.protectedValue.text,
        'generata-sintetica',
      );
    },
  );
}
