import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../shared/database/database_session.dart';
import '../../shared/storage/file_storage.dart';
import 'password_generator.dart';

/// Password della tab Genera ancora da salvare, custodita solo nel processo.
@immutable
class PendingGeneratedPassword {
  const PendingGeneratedPassword({
    required this.file,
    required this.options,
    required this.protectedValue,
  });

  final FileRef file;
  final GeneratorOptions options;

  /// Buffer posseduto dal notifier: chi lo legge non deve azzerarlo.
  final ProtectedData protectedValue;
}

/// Custodia RAM indipendente dalle route e dai provider autoDispose delle viste.
/// Non contiene mai chiavi o credenziali di apertura del database.
final pendingGeneratedPasswordProvider =
    NotifierProvider<
      PendingGeneratedPasswordNotifier,
      PendingGeneratedPassword?
    >(PendingGeneratedPasswordNotifier.new);

class PendingGeneratedPasswordNotifier
    extends Notifier<PendingGeneratedPassword?> {
  ProtectedData? _ownedValue;
  bool _retainOnNextLock = false;

  @override
  PendingGeneratedPassword? build() {
    ref.listen(databaseSessionProvider, (previous, next) {
      final pending = state;
      if (pending == null) return;
      if (next != null) {
        if (next.file != pending.file) clear();
      } else {
        final retain = _retainOnNextLock;
        _retainOnNextLock = false;
        if (!retain) clear();
      }
    });
    ref.onDispose(() {
      _ownedValue?.clear();
      _ownedValue = null;
    });
    return null;
  }

  /// Sostituisce il valore corrente senza scrivere alcuna preferenza.
  void replace(FileRef file, GeneratorOptions options, String value) {
    if (ref.read(databaseSessionProvider)?.file != file ||
        !options.isValid ||
        value.isEmpty) {
      clear();
      return;
    }
    final protected = ProtectedData.fromString(value);
    _retainOnNextLock = false;
    _ownedValue?.clear();
    _ownedValue = protected;
    state = PendingGeneratedPassword(
      file: file,
      options: options,
      protectedValue: protected,
    );
  }

  /// Valore disponibile esclusivamente per il database indicato.
  ProtectedData? valueFor(FileRef file) =>
      state?.file == file ? state?.protectedValue : null;

  /// Autorizza una sola continuità attraverso il blocco automatico corrente.
  void prepareAutomaticLock(FileRef file) {
    final pending = state;
    if (pending == null || pending.file != file) return;
    _retainOnNextLock = true;
  }

  /// Salvataggio, blocco manuale o abbandono del database: azzera i buffer.
  void clear() {
    _retainOnNextLock = false;
    _ownedValue?.clear();
    _ownedValue = null;
    state = null;
  }
}
