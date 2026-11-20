import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/ui/master_key_form.dart';
import 'create_database_view_model.dart';

/// Creazione di un database: password con conferma, file chiave facoltativo e
/// posizione scelta con il selettore del sistema.
class CreateDatabaseView extends ConsumerWidget {
  const CreateDatabaseView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(createDatabaseViewModelProvider);
    final busy = state.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.createDatabaseTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: appFormMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MasterKeyForm(
                    enabled: !busy,
                    submitLabel: l10n.createDatabaseButton,
                    info: l10n.createDatabaseInfo,
                    onSubmit: (password, keyFile) => ref
                        .read(createDatabaseViewModelProvider.notifier)
                        .create(password: password, keyFile: keyFile),
                  ),
                  FormStatus(
                    busy: busy,
                    busyText: l10n.createDatabaseInProgress,
                    error: switch (state) {
                      AsyncError(:final error) => describeCreateError(
                        l10n,
                        error,
                      ),
                      _ => null,
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
