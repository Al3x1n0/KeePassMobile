import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../shared/storage/remote_storage.dart';
import '../shared/storage/webdav_client.dart';
import '../shared/ui/ssh_key_field.dart';
import 'router.dart';
import 'theme.dart';

BuildContext? _dialogContext(Ref ref) {
  final context = ref
      .read(routerProvider)
      .routerDelegate
      .navigatorKey
      .currentContext;
  return context != null && context.mounted ? context : null;
}

/// Credenziali del server sopra la schermata in corso (apertura o
/// salvataggio di un file remoto). Senza risposta: annullato.
RemoteCredentialsPrompt remoteCredentialsDialog(Ref ref) =>
    (file, {previous, failed = false}) async {
      final context = _dialogContext(ref);
      if (context == null) return null;
      return showDialog<RemoteCredentialsAnswer>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RemoteCredentialsDialog(
          server: Uri.tryParse(file.uri)?.host ?? file.name,
          ssh: Uri.tryParse(file.uri)?.scheme == 'sftp',
          previous: previous,
          failed: failed,
        ),
      );
    };

/// Conferma del certificato non riconosciuto dal sistema (D31), con
/// l'impronta da confrontare con quella del server.
CertificateTrustPrompt sshHostTrustDialog(Ref ref) =>
    _trustDialog(ref, ssh: true);

CertificateTrustPrompt certificateTrustDialog(Ref ref) => _trustDialog(ref);

CertificateTrustPrompt _trustDialog(Ref ref, {bool ssh = false}) =>
    (server, fingerprint) async {
      final context = _dialogContext(ref);
      if (context == null) return false;
      final l10n = AppLocalizations.of(context);
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.gpp_maybe_outlined),
          title: Text(ssh ? l10n.sshHostTitle : l10n.remoteCertificateTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ssh
                    ? l10n.sshHostBody(server)
                    : l10n.remoteCertificateBody(server),
              ),
              const SizedBox(height: AppSpacing.m),
              SelectableText(
                fingerprint,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.remoteCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.remoteCertificateAccept),
            ),
          ],
        ),
      );
      return accepted ?? false;
    };

/// Nome utente, password e "Ricorda le credenziali" per un server.
class RemoteCredentialsDialog extends StatefulWidget {
  const RemoteCredentialsDialog({
    super.key,
    required this.server,
    this.previous,
    this.failed = false,
    this.ssh = false,
  });

  final String server;
  final RemoteCredentials? previous;
  final bool failed;
  final bool ssh;

  @override
  State<RemoteCredentialsDialog> createState() =>
      _RemoteCredentialsDialogState();
}

class _RemoteCredentialsDialogState extends State<RemoteCredentialsDialog> {
  late final _user = TextEditingController(text: widget.previous?.userName);
  final _secret = TextEditingController();
  final _privateKey = TextEditingController();
  late bool _useKey = widget.previous?.privateKey != null;
  bool _remember = true;
  bool _obscure = true;

  @override
  void dispose() {
    _privateKey
      ..clear()
      ..dispose();
    _user.dispose();
    _secret
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _submit() {
    if (_user.text.trim().isEmpty) return;
    Navigator.of(context).pop(
      RemoteCredentialsAnswer(
        credentials: RemoteCredentials(
          userName: _user.text.trim(),
          password: _secret.text,
          privateKey: widget.ssh && _useKey ? _privateKey.text : null,
        ),
        remember: _remember,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.remoteCredentialsTitle(widget.server)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.failed) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.remoteCredentialsFailed,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.m),
            ],
            TextField(
              controller: _user,
              autofocus: widget.previous == null,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                LengthLimitingTextInputFormatter(AppLimits.remoteUserName),
              ],
              decoration: InputDecoration(
                labelText: l10n.remoteUserName,
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            if (widget.ssh)
              SshKeyField(
                controller: _privateKey,
                useKey: _useKey,
                onUseKey: (v) => setState(() {
                  _useKey = v;
                  _privateKey.clear();
                  _secret.clear();
                }),
              ),
            TextField(
              controller: _secret,
              autofocus: widget.previous != null,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                LengthLimitingTextInputFormatter(AppLimits.masterPassword),
              ],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: widget.ssh && _useKey
                    ? l10n.sshPassphrase
                    : l10n.remotePassword,
                suffixIcon: IconButton(
                  tooltip: _obscure
                      ? l10n.unlockShowPassword
                      : l10n.unlockHidePassword,
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.remoteRemember),
              subtitle: Text(l10n.remoteRememberHint),
              value: _remember,
              onChanged: (v) => setState(() => _remember = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.remoteCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.remoteSignIn)),
      ],
    );
  }
}
