import '../../shared/database/database_errors.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/database/database_session.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/database/field_references.dart';
import '../../shared/storage/preferences.dart';
import 'autofill_channel.dart';
import 'autofill_matcher.dart';

/// Destinatari confermati per un'app Android e una firma specifiche.
class AutofillTrustRepository {
  AutofillTrustRepository(this._prefs);

  static const storageKey = 'autofill.signed_trusted_links';

  final SharedPreferences _prefs;

  bool isTrusted(String link) =>
      (_prefs.getStringList(storageKey) ?? const []).contains(link);

  bool isAppTrusted(AutofillRequest request) =>
      request.appTrustLinks.any(isTrusted);

  Future<void> trustApp(AutofillRequest request) async {
    if (request.canRememberApp) await trust(request.appTrustLinks.last);
  }

  Future<void> trust(String link) async {
    final links = {...?_prefs.getStringList(storageKey), link}.toList()..sort();
    await _prefs.setStringList(storageKey, links);
  }
}

final autofillTrustRepositoryProvider = Provider<AutofillTrustRepository>(
  (ref) => AutofillTrustRepository(ref.watch(sharedPreferencesProvider)),
);

/// Usa il dominio dichiarato dopo una conferma dell'utente.
final autofillUseDomainProvider =
    NotifierProvider<AutofillUseDomainNotifier, bool>(
      AutofillUseDomainNotifier.new,
    );

class AutofillUseDomainNotifier extends Notifier<bool> {
  @override
  bool build() {
    final request = ref.watch(autofillRequestProvider);
    if (!request.canRememberDomain) return false;
    return request.trustLinks.any(
      ref.watch(autofillTrustRepositoryProvider).isTrusted,
    );
  }

  void useOnce() => state = true;

  Future<void> useAlways() async {
    final request = ref.read(autofillRequestProvider);
    if (!request.canRememberDomain) return;
    state = true;
    await ref
        .read(autofillTrustRepositoryProvider)
        .trust(request.trustLinks.last);
  }
}

/// Richiesta con cui cercare: il dominio, se si usa, o l'app.
final autofillQueryProvider = Provider<String>((ref) {
  final request = ref.watch(autofillRequestProvider);
  final domain = request.webDomain;
  return ref.watch(autofillUseDomainProvider) && domain != null
      ? domain
      : request.appQuery;
});

/// Voci proposte per la richiesta; `null` con il database chiuso.
final autofillMatchesProvider = Provider<List<KdbxEntry>?>((ref) {
  final session = ref.watch(databaseSessionProvider);
  if (session == null) return null;
  return autofillMatches(session.database, ref.watch(autofillQueryProvider));
});

/// `true` dopo la risposta al sistema: la schermata sta per chiudersi.
final autofillDoneProvider = NotifierProvider<AutofillDoneNotifier, bool>(
  AutofillDoneNotifier.new,
);

class AutofillDoneNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void done() => state = true;
}

/// Conferma data dall'utente per la scelta corrente.
enum AutofillChoice { direct, once, rememberEntry, rememberApp }

/// Compilazione con la voce scelta.
final autofillPickViewModelProvider =
    AsyncNotifierProvider<AutofillPickViewModel, void>(
      AutofillPickViewModel.new,
    );

class AutofillPickViewModel extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Compila con la voce [uuid], dopo l'eventuale conferma del destinatario.
  Future<void> fill(
    KdbxUuid uuid, {
    AutofillChoice choice = AutofillChoice.direct,
  }) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = ref.read(databaseSessionProvider.notifier);
      if (session.isSaving) throw const DatabaseBusyException();
      final initialDatabase = ref.read(databaseSessionProvider)?.database;
      final initialEntry = initialDatabase == null
          ? null
          : findEntryByUuid(initialDatabase, uuid);
      if (initialEntry == null) throw const DatabaseLockedException();
      final request = ref.read(autofillRequestProvider);
      final query = ref.read(autofillQueryProvider);
      final appTarget = query == request.appQuery;
      final trust = ref.read(autofillTrustRepositoryProvider);
      if (choice == AutofillChoice.direct &&
          (!isExactAutofillMatch(initialEntry, query) ||
              (appTarget && !trust.isAppTrusted(request)))) {
        throw StateError('destinatario autofill da confermare');
      }
      if (choice == AutofillChoice.rememberApp &&
          (!appTarget ||
              !request.canRememberApp ||
              !isExactAutofillMatch(initialEntry, query))) {
        throw StateError('destinatario autofill non associabile');
      }
      String resolved(
        KdbxDatabase db,
        KdbxEntry item,
        String key,
        bool needed,
      ) {
        if (!needed) return '';
        final result = resolveEntryField(db, item, key);
        if (!result.valid) throw FieldReferenceException(result.issue!);
        return result.text;
      }

      // Prima di qualunque associazione persistente, valida i campi richiesti.
      resolved(
        initialDatabase!,
        initialEntry,
        EntryFields.userName,
        request.hasUserName,
      );
      resolved(
        initialDatabase,
        initialEntry,
        EntryFields.password,
        request.hasPassword,
      );
      if (choice == AutofillChoice.rememberEntry) {
        await session.apply(rememberAutofillEdit(uuid, query));
      }
      if (appTarget &&
          (choice == AutofillChoice.rememberApp ||
              choice == AutofillChoice.rememberEntry) &&
          !trust.isAppTrusted(request)) {
        await trust.trustApp(request);
      }
      final database = ref.read(databaseSessionProvider)?.database;
      final entry = database == null ? null : findEntryByUuid(database, uuid);
      if (entry == null) throw const DatabaseLockedException();
      final userName = resolved(
        database!,
        entry,
        EntryFields.userName,
        request.hasUserName,
      );
      final secret = resolved(
        database,
        entry,
        EntryFields.password,
        request.hasPassword,
      );
      if (userName.isEmpty && secret.isEmpty) {
        throw const AutofillNoFillableFieldsException();
      }
      await ref
          .read(autofillChannelProvider)
          .fill(
            userName: request.hasUserName && userName.isNotEmpty
                ? userName
                : null,
            password: request.hasPassword && secret.isNotEmpty ? secret : null,
          );
      // Prima del blocco: niente ritorno alla scelta del database.
      ref.read(autofillDoneProvider.notifier).done();
      session.lock();
    });
  }

  /// Chiude senza compilare.
  Future<void> cancel() async {
    ref.read(autofillDoneProvider.notifier).done();
    ref.read(databaseSessionProvider.notifier).lock();
    await ref.read(autofillChannelProvider).cancel();
  }
}
