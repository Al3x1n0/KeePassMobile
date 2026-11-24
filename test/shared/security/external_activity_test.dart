import 'dart:async';
import 'dart:typed_data';

import 'package:document_access/document_access.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/autofill/autofill_channel.dart';
import 'package:keepass_mobile/shared/security/external_activity.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';

class _Documents extends DocumentAccess {
  final picked = Completer<PickedDocument?>();
  final created = Completer<CreatedDocument?>();

  @override
  Future<PickedDocument?> pick() => picked.future;

  @override
  Future<CreatedDocument?> create({
    required String suggestedName,
    required Uint8List bytes,
  }) => created.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ExternalActivity activity;

  setUp(() => activity = ExternalActivity());
  tearDown(() => activity.dispose());

  test('annullamento e errore rilasciano lo scope in primo piano', () async {
    expect(await activity.run(() async => null), isNull);
    expect(activity.isActive, isFalse);

    await expectLater(
      activity.run(() async => throw StateError('canceled')),
      throwsStateError,
    );
    expect(activity.isActive, isFalse);
  });

  test('il completamento prima del resumed protegge il rientro', () async {
    final result = Completer<void>();
    final operation = activity.run(() => result.future);
    activity.appLifecycleChanged(AppLifecycleState.inactive);
    activity.appLifecycleChanged(AppLifecycleState.hidden);
    activity.appLifecycleChanged(AppLifecycleState.paused);

    result.complete();
    await operation;

    expect(activity.isActive, isTrue);
    activity.appLifecycleChanged(AppLifecycleState.hidden);
    activity.appLifecycleChanged(AppLifecycleState.inactive);
    expect(activity.isActive, isTrue);
    activity.appLifecycleChanged(AppLifecycleState.resumed);
    expect(activity.isActive, isFalse);
  });

  test(
    'scope iniziato mentre inactive: viene rilasciato al ritorno',
    () async {
      activity.appLifecycleChanged(AppLifecycleState.inactive);

      await activity.run(() async {});

      expect(activity.isActive, isTrue);
      activity.appLifecycleChanged(AppLifecycleState.resumed);
      expect(activity.isActive, isFalse);
    },
  );

  test(
    'scope sovrapposti: il primo risultato non rilascia il secondo',
    () async {
      final first = Completer<void>();
      final second = Completer<void>();
      final a = activity.run(() => first.future);
      final b = activity.run(() => second.future);
      first.complete();
      await a;
      expect(activity.isActive, isTrue);

      second.complete();
      await b;
      expect(activity.isActive, isFalse);
    },
  );

  test(
    'picker di apertura e creazione mantengono lo scope fino al ritorno',
    () async {
      final documents = _Documents();
      final picker = FilePickerService(documents, activity);
      final storage = FileStorage(documents, null, activity);
      final pick = picker.pick();
      final create = storage.create(
        suggestedName: 'test.kdbx',
        bytes: Uint8List(0),
      );
      expect(activity.isActive, isTrue);
      activity.appLifecycleChanged(AppLifecycleState.paused);

      documents.picked.complete(null);
      documents.created.complete(null);
      expect(await pick, isNull);
      expect(await create, isNull);
      expect(activity.isActive, isTrue);
      activity.appLifecycleChanged(AppLifecycleState.resumed);
      expect(activity.isActive, isFalse);
    },
  );

  testWidgets(
    'impostazioni lanciate: risposta immediata, esenzione fino al rientro',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        AutofillSettings.channel,
        (_) async => true,
      );
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(AutofillSettings.channel, null),
      );

      expect(await AutofillSettings(activity).openSystemSettings(), isTrue);
      expect(activity.isActive, isTrue);
      activity.appLifecycleChanged(AppLifecycleState.inactive);
      activity.appLifecycleChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 3));
      expect(activity.isActive, isTrue);

      activity.appLifecycleChanged(AppLifecycleState.resumed);
      expect(activity.isActive, isFalse);
    },
  );

  testWidgets('un lancio senza uscita non lascia esenzioni permanenti', (
    tester,
  ) async {
    expect(await activity.launch(() async => true), isTrue);
    expect(activity.isActive, isTrue);

    await tester.pump(const Duration(seconds: 2));

    expect(activity.isActive, isFalse);
    expect(await activity.launch(() async => false), isFalse);
    expect(activity.isActive, isFalse);
  });
}
