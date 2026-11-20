import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/database/database_session.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/database/field_references.dart';
import '../../shared/storage/preferences.dart';
import 'autofill_channel.dart';
import 'autofill_matcher.dart';

/// Coppie dominio-app di cui l'utente si fida (D27), come
/// `AutoFillTrustedLinks` di Keepass2Android.
class AutofillTrustRepository {
  AutofillTrustRepository(this._prefs);

  static const storageKey = 'autofill.trusted_links';

  final SharedPreferences _prefs;

  bool isTrusted(String link) =>
      (_prefs.getStringList(storageKey) ?? const []).contains(link);

  Future<void> trust(String link) async {
    final links = {...?_prefs.getStringList(storageKey), link}.toList()..sort();
    await _prefs.setStringList(storageKey, links);
  }
}

final autofillTrustRepositoryProvider = Provider<AutofillTrustRepository>(
  (ref) => AutofillTrustRepository(ref.watch(sharedPreferencesProvider)),
);

/// `true` se le voci si cercano per il dominio dichiarato: browser noto,
/// coppia dominio-app ricordata o confermata per questa volta (D27). Altrimenti
/// si cerca per l'app.
final autofillUseDomainProvider =
    NotifierProvider<AutofillUseDomainNotifier, bool>(
      AutofillUseDomainNotifier.new,
    );

class AutofillUseDomainNotifier extends Notifier<bool> {
  @override
  bool build() {
    final request = ref.watch(autofillRequestProvider);
    final link = request.trustLink;
    if (link == null) return false;
    return request.isBrowser ||
        ref.watch(autofillTrustRepositoryProvider).isTrusted(link);
  }

  void useOnce() => state = true;

  Future<void> useAlways() async {
    final link = ref.read(autofillRequestProvider).trustLink;
    if (link == null) return;
    state = true;
    await ref.read(autofillTrustRepositoryProvider).trust(link);
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

/// Compilazione con la voce scelta.
final autofillPickViewModelProvider =
    AsyncNotifierProvider<AutofillPickViewModel, void>(
      AutofillPickViewModel.new,
    );

class AutofillPickViewModel extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Compila con la voce [uuid]; con [remember] prima la associa alla
  /// richiesta e salva il database (D28). Poi il database si chiude.
  Future<void> fill(KdbxUuid uuid, {bool remember = false}) async {
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
      if (remember) {
        await session.apply(
          rememberAutofillEdit(uuid, ref.read(autofillQueryProvider)),
        );
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
