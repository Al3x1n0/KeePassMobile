import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../../shared/storage/file_storage.dart';
import '../../shared/ui/master_key_form.dart';
import 'change_master_key_view_model.dart';

/// Cambio della chiave principale del database aperto.
class ChangeMasterKeyView extends ConsumerWidget {
  const ChangeMasterKeyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(changeMasterKeyViewModelProvider);
    final busy = state.isLoading;

    Future<void> change(
      String currentPassword,
      String password,
      PickedFile? keyFile,
    ) async {
      final messenger = ScaffoldMessenger.of(context);
      final viewModel = ref.read(changeMasterKeyViewModelProvider.notifier);
      final changed = await viewModel.change(
        currentPassword: currentPassword,
        password: password,
        keyFile: keyFile,
      );
      if (!changed || !context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            viewModel.biometricDisabled
                ? l10n.changeKeyDoneBiometricOff
                : l10n.changeKeyDone,
          ),
        ),
      );
      context.pop();
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.changeKeyTitle)),
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
                    passwordLabel: l10n.changeKeyNewPassword,
                    submitLabel: l10n.changeKeyButton,
                    info: l10n.changeKeyInfo,
                    requireCurrentPassword: true,
                    allowEmptyCurrentPassword:
                        ref.watch(databaseSessionProvider)?.keyFile != null,
                    onSubmit: (_, _) {},
                    onSubmitWithCurrent: change,
                  ),
                  FormStatus(
                    busy: busy,
                    busyText: l10n.changeKeyInProgress,
                    error: switch (state) {
                      AsyncError(:final error) => switch (error) {
                        InvalidCurrentMasterKeyException() =>
                          l10n.changeKeyWrongCurrentPassword,
                        KeyFileUnavailableException() =>
                          l10n.errorKeyFileUnavailable,
                        _ => describeSaveError(l10n, error),
                      },
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
