import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../storage/remote_storage.dart';
import 'app_snack_bar.dart';

/// Scelta di una chiave privata SSH, solo in memoria finché non si ricorda
/// il file remoto. L'accesso al file passa dal servizio di storage.
class SshKeyField extends ConsumerWidget {
  const SshKeyField({
    super.key,
    required this.controller,
    required this.useKey,
    required this.onUseKey,
    this.enabled = true,
  });

  final TextEditingController controller;
  final bool useKey;
  final ValueChanged<bool> onUseKey;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.sshUseKey),
          value: useKey,
          onChanged: enabled ? onUseKey : null,
        ),
        if (useKey)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.m),
            child: TextField(
              controller: controller,
              enabled: enabled,
              obscureText: true,
              readOnly: true,
              enableInteractiveSelection: false,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              inputFormatters: [
                LengthLimitingTextInputFormatter(AppLimits.sshPrivateKey),
              ],
              decoration: InputDecoration(
                labelText: l10n.sshPrivateKey,
                suffixIcon: IconButton(
                  tooltip: l10n.sshChooseKey,
                  icon: const Icon(Icons.attach_file),
                  onPressed: !enabled
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final key = await ref.read(sshKeyPickerProvider)();
                            if (context.mounted && key != null) {
                              controller.text = key;
                            }
                          } on Object {
                            if (context.mounted) {
                              messenger.showAppSnackBar(
                                SnackBar(content: Text(l10n.errorSshKey)),
                              );
                            }
                          }
                        },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
