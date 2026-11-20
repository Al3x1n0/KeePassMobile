import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/app/remote_dialogs.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/security/device_security.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:keepass_mobile/shared/storage/remote_storage.dart';
import 'package:keepass_mobile/shared/storage/remote_cache.dart';
import 'package:keepass_mobile/shared/storage/webdav_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_app_security.dart';
import '../helpers/fake_secure_storage.dart';
import '../helpers/fake_webdav_client.dart';
import '../helpers/fake_sftp_client.dart';
import '../helpers/memory_cache_documents.dart';
import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  const server = RemoteCredentials(
    userName: 'mario',
    password: 'server-segreta',
  );
  const fileUrl = 'https://dav.example/files/prova.kdbx';
  late Uint8List databaseBytes;

  setUpAll(() async {
    final db = newTestDatabase();
    addTestEntry(db, db.root, {EntryFields.title: 'Conto remoto'});
    databaseBytes = Uint8List.fromList(await db.save());
  });

  late FakeWebDavClient client;
  late FakeSftpClient sftp;
  late FakeSecureStorage secure;
  late SharedPreferences prefs;

  Future<void> start(WidgetTester tester) async {
    FakeClipboard(tester.binding);
    secure = FakeSecureStorage.install();
    client = FakeWebDavClient(accepted: server)
      ..files[fileUrl] = Uint8List.fromList(databaseBytes);
    sftp = FakeSftpClient(accepted: server)
      ..files['sftp://ssh.example/prova.kdbx'] = Uint8List.fromList(
        databaseBytes,
      );
    SharedPreferences.setMockInitialValues({});
    prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          remoteCacheStoreProvider.overrideWithValue(
            RemoteCacheStore(documents: MemoryCacheDocuments()),
          ),
          appSecurityProvider.overrideWithValue(FakeAppSecurity()),
          webDavClientProvider.overrideWithValue(client),
          sftpClientProvider.overrideWithValue(sftp),
          sshHostTrustPromptProvider.overrideWith(sshHostTrustDialog),
          remoteCredentialsPromptProvider.overrideWith(remoteCredentialsDialog),
          certificateTrustPromptProvider.overrideWith(certificateTrustDialog),
        ],
        child: const KeePassMobileApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> connectAndPick(
    WidgetTester tester, {
    required bool remember,
  }) async {
    await tester.tap(find.byTooltip(l10n.remoteOpenTitle));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, l10n.remoteAddress),
      'dav.example/files',
    );
    await tester.enterText(
      find.widgetWithText(TextField, l10n.remoteUserName),
      server.userName,
    );
    await tester.enterText(
      find.widgetWithText(TextField, l10n.remotePassword),
      server.password,
    );
    if (!remember) await tester.tap(find.text(l10n.remoteRemember));
    await tester.tap(find.text(l10n.remoteConnect));
    await pumpUntilFound(tester, find.text('prova.kdbx'));
    await tester.tap(find.text('prova.kdbx'));
    await pumpUntilFound(tester, find.text(l10n.unlockButton));
    await tester.pumpAndSettle();
  }

  Future<void> unlock(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(tester, find.text('Conto remoto'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    '"ricorda": apertura dal server, file tra i recenti, credenziali salvate',
    (tester) async {
      await start(tester);
      await connectAndPick(tester, remember: true);
      await unlock(tester);

      final recents = RecentFilesRepository(prefs, const FileStorage()).load();
      expect(recents.single.database.uri, fileUrl);
      expect(
        secure.data.keys,
        contains(
          RemoteCredentialStore.keyOf(
            const FileRef(uri: fileUrl, name: 'prova.kdbx'),
          ),
        ),
      );
      expect(client.calls, [
        'PROPFIND https://dav.example/files/',
        'GET $fileUrl',
      ]);

      // Blocco: lo sblocco dello stesso file legge con le credenziali salvate.
      await tester.tap(find.byTooltip(l10n.groupLock));
      await pumpUntilFound(tester, find.text(l10n.unlockButton));
      await tester.pumpAndSettle();
      await unlock(tester);

      expect(
        find.text(l10n.remoteCredentialsTitle('dav.example')),
        findsNothing,
      );
      expect(client.calls.where((c) => c.startsWith('GET')), hasLength(2));
    },
  );

  testWidgets(
    '"non ricordare": niente nell\'archivio, credenziali chieste dopo il blocco',
    (tester) async {
      await start(tester);
      await connectAndPick(tester, remember: false);
      await unlock(tester);
      expect(secure.data, isEmpty);

      await tester.tap(find.byTooltip(l10n.groupLock));
      await pumpUntilFound(tester, find.text(l10n.unlockButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), testMasterKey);
      await tester.tap(find.text(l10n.unlockButton));
      await pumpUntilFound(
        tester,
        find.text(l10n.remoteCredentialsTitle('dav.example')),
      );
      // Lo sblocco è in corso (indicatore animato): niente pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 300));

      final dialog = find.byType(RemoteCredentialsDialog);
      await tester.enterText(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(TextField, l10n.remoteUserName),
        ),
        server.userName,
      );
      await tester.enterText(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(TextField, l10n.remotePassword),
        ),
        server.password,
      );
      await tester.tap(
        find.descendant(of: dialog, matching: find.text(l10n.remoteRemember)),
      );
      await tester.tap(find.text(l10n.remoteSignIn));
      await pumpUntilFound(tester, find.text('Conto remoto'));

      expect(secure.data, isEmpty);
    },
  );

  testWidgets('credenziali rifiutate dal server: messaggio nel modulo', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byTooltip(l10n.remoteOpenTitle));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, l10n.remoteAddress),
      'https://dav.example/files/',
    );
    await tester.enterText(
      find.widgetWithText(TextField, l10n.remoteUserName),
      'mario',
    );
    await tester.enterText(
      find.widgetWithText(TextField, l10n.remotePassword),
      'sbagliata',
    );
    await tester.tap(find.text(l10n.remoteConnect));
    await pumpUntilFound(tester, find.text(l10n.errorRemoteAuth));

    expect(find.text('prova.kdbx'), findsNothing);
  });

  testWidgets('indirizzo http: rifiutato senza connettersi', (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip(l10n.remoteOpenTitle));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, l10n.remoteAddress),
      'http://dav.example/files/',
    );
    await tester.enterText(
      find.widgetWithText(TextField, l10n.remoteUserName),
      'mario',
    );
    await tester.tap(find.text(l10n.remoteConnect));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorRemoteInsecure), findsOneWidget);
    expect(client.calls, isEmpty);
  });
  testWidgets(
    'SFTP: conferma impronta, apre e blocca il database, blocca chiave cambiata',
    (tester) async {
      await start(tester);
      await tester.tap(find.byTooltip(l10n.remoteOpenTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.remoteServerType));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.remoteServerSftp).last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, l10n.remoteAddress),
        'ssh.example/',
      );
      await tester.enterText(
        find.widgetWithText(TextField, l10n.remoteUserName),
        server.userName,
      );
      await tester.enterText(
        find.widgetWithText(TextField, l10n.remotePassword),
        server.password,
      );
      await tester.tap(find.text(l10n.remoteConnect));
      await pumpUntilFound(tester, find.text(l10n.sshHostTitle));
      expect(find.text('ssh-ed25519 SHA256:synthetic'), findsOneWidget);
      await tester.tap(find.text(l10n.remoteCertificateAccept));
      await pumpUntilFound(tester, find.text('prova.kdbx'));
      await tester.tap(find.text('prova.kdbx'));
      await pumpUntilFound(tester, find.text(l10n.unlockButton));
      await tester.pumpAndSettle();
      await unlock(tester);
      final recents = RecentFilesRepository(prefs, const FileStorage()).load();
      expect(recents.single.database.uri, 'sftp://ssh.example/prova.kdbx');
      sftp.fingerprint = 'SHA256:changed';
      await tester.tap(find.byTooltip(l10n.groupLock));
      await pumpUntilFound(tester, find.text(l10n.unlockButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), testMasterKey);
      await tester.tap(find.text(l10n.unlockButton));
      await pumpUntilFound(tester, find.text(l10n.errorSshHostChanged));
      expect(find.text(l10n.sshHostTitle), findsNothing);
    },
  );
  testWidgets(
    'copia locale esplicita: sblocco senza contattare il server e avviso persistente',
    (tester) async {
      await start(tester);
      await connectAndPick(tester, remember: true);
      await unlock(tester);
      await tester.tap(find.byTooltip(l10n.groupLock));
      await pumpUntilFound(tester, find.text(l10n.unlockButton));
      await tester.pumpAndSettle();
      final calls = client.calls.length;
      await tester.tap(find.text(l10n.unlockFromCache));
      await tester.enterText(find.byType(TextField), testMasterKey);
      await tester.tap(find.text(l10n.unlockButton));
      await pumpUntilFound(tester, find.text('Conto remoto'));
      expect(client.calls.length, calls);
      expect(find.text(l10n.cacheOffline), findsOneWidget);
    },
  );
}
