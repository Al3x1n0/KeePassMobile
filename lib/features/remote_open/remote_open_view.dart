import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../../shared/storage/webdav_client.dart';
import '../../shared/ui/size_format.dart';
import '../../shared/ui/selection_sheet.dart';
import '../../shared/ui/ssh_key_field.dart';
import '../../shared/ui/sensitive_text_editing.dart';
import '../unlock/unlock_view_model.dart';
import 'remote_open_view_model.dart';

/// "Apri da server": modulo di connessione WebDAV (anche Nextcloud e
/// ownCloud), poi le cartelle del server; un file apre lo sblocco.
class RemoteOpenView extends ConsumerStatefulWidget {
  const RemoteOpenView({super.key, this.additional = false});
  final bool additional;

  @override
  ConsumerState<RemoteOpenView> createState() => _RemoteOpenViewState();
}

class _RemoteOpenViewState extends ConsumerState<RemoteOpenView> {
  final _address = TextEditingController();
  final _user = TextEditingController();
  final _secret = TextEditingController();
  final _privateKey = TextEditingController();
  bool _useKey = false;
  var _type = RemoteServerType.webDav;
  bool _remember = false;
  bool _obscure = true;

  @override
  void dispose() {
    _privateKey
      ..clear()
      ..dispose();
    _address.dispose();
    _user.dispose();
    _secret
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _connect() {
    if (_address.text.trim().isEmpty || _user.text.trim().isEmpty) return;
    ref
        .read(remoteOpenViewModelProvider.notifier)
        .connect(
          type: _type,
          address: _address.text,
          credentials: RemoteCredentials(
            userName: _user.text.trim(),
            password: _secret.text,
            privateKey: _type == RemoteServerType.sftp && _useKey
                ? _privateKey.text
                : null,
          ),
          remember: _remember,
        );
  }

  Future<void> _pick(RemoteEntry entry) async {
    final picked = await ref
        .read(remoteOpenViewModelProvider.notifier)
        .pick(entry);
    if (picked == null || !mounted) return;
    _secret.clear();
    _privateKey.clear();
    await context.push(
      widget.additional ? AppRoutes.additionalUnlock : AppRoutes.unlock,
      extra: UnlockArgs(
        database: picked,
        additional: widget.additional,
        lockGeneration: ref
            .read(databaseSessionProvider.notifier)
            .lockGeneration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(remoteOpenViewModelProvider);
    final viewModel = ref.read(remoteOpenViewModelProvider.notifier);
    return PopScope(
      canPop: !state.connected,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        state.canGoUp ? viewModel.up() : viewModel.disconnect();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            state.connected
                ? _folderName(state.directory!, l10n)
                : l10n.remoteOpenTitle,
          ),
          actions: [
            if (state.canGoUp)
              IconButton(
                tooltip: l10n.remoteUp,
                icon: const Icon(Icons.drive_folder_upload_outlined),
                onPressed: state.busy ? null : viewModel.up,
              ),
          ],
          bottom: state.busy
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(4),
                  child: LinearProgressIndicator(),
                )
              : null,
        ),
        body: SafeArea(
          child: state.connected ? _browser(state, l10n) : _form(state, l10n),
        ),
      ),
    );
  }

  static String _folderName(Uri directory, AppLocalizations l10n) {
    final segments = directory.pathSegments.where((s) => s.isNotEmpty);
    return segments.isEmpty ? directory.host : segments.last;
  }

  Widget _error(Object? error, AppLocalizations l10n) {
    if (error == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Semantics(
        liveRegion: true,
        child: Text(
          describeRemoteError(l10n, error),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }

  Widget _form(RemoteBrowserState state, AppLocalizations l10n) {
    final busy = state.busy;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: appFormMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: !busy,
                title: Text(l10n.remoteServerType),
                subtitle: Text(switch (_type) {
                  RemoteServerType.webDav => l10n.remoteServerWebDav,
                  RemoteServerType.nextcloud => l10n.remoteServerNextcloud,
                  RemoteServerType.sftp => l10n.remoteServerSftp,
                  RemoteServerType.ownCloud => l10n.remoteServerOwnCloud,
                }),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy
                    ? null
                    : () async {
                        final type = await showSelectionSheet<RemoteServerType>(
                          context: context,
                          title: l10n.remoteServerType,
                          selected: _type,
                          options: {
                            RemoteServerType.webDav: l10n.remoteServerWebDav,
                            RemoteServerType.nextcloud:
                                l10n.remoteServerNextcloud,
                            RemoteServerType.sftp: l10n.remoteServerSftp,
                            RemoteServerType.ownCloud:
                                l10n.remoteServerOwnCloud,
                          },
                        );
                        if (!mounted || type == null) return;
                        setState(() {
                          _type = type;
                          _privateKey.clear();
                          _secret.clear();
                          _useKey = false;
                        });
                      },
              ),
              const SizedBox(height: AppSpacing.m),
              TextField(
                controller: _address,
                enabled: !busy,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(AppLimits.remoteAddress),
                ],
                decoration: InputDecoration(
                  labelText: l10n.remoteAddress,
                  hintText: _type == RemoteServerType.sftp
                      ? l10n.remoteAddressHintSftp
                      : _type == RemoteServerType.webDav
                      ? l10n.remoteAddressHintWebDav
                      : l10n.remoteAddressHintCloud,
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              TextField(
                controller: _user,
                enabled: !busy,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(AppLimits.remoteUserName),
                ],
                decoration: InputDecoration(labelText: l10n.remoteUserName),
              ),
              const SizedBox(height: AppSpacing.m),
              if (_type == RemoteServerType.sftp)
                SshKeyField(
                  controller: _privateKey,
                  useKey: _useKey,
                  enabled: !busy,
                  onUseKey: (v) => setState(() {
                    _useKey = v;
                    _privateKey.clear();
                    _secret.clear();
                  }),
                ),
              SensitiveTextEditing(
                child: TextField(
                  selectionControls: SensitiveTextEditing.selectionControls,
                  controller: _secret,
                  enabled: !busy,
                  obscureText: _obscure,
                  autocorrect: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(AppLimits.masterPassword),
                  ],
                  onSubmitted: (_) => _connect(),
                  decoration: InputDecoration(
                    labelText: _type == RemoteServerType.sftp && _useKey
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
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.remoteRemember),
                subtitle: Text(l10n.remoteRememberHint),
                value: _remember,
                onChanged: busy ? null : (v) => setState(() => _remember = v),
              ),
              const SizedBox(height: AppSpacing.m),
              FilledButton(
                onPressed: busy ? null : _connect,
                child: Text(l10n.remoteConnect),
              ),
              _error(state.error, l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _browser(RemoteBrowserState state, AppLocalizations l10n) {
    final viewModel = ref.read(remoteOpenViewModelProvider.notifier);
    return ListView(
      children: [
        _error(state.error, l10n),
        if (state.entries.isEmpty && state.error == null)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Text(l10n.remoteEmptyFolder, textAlign: TextAlign.center),
          ),
        for (final entry in state.entries)
          ListTile(
            leading: Icon(
              entry.isDirectory
                  ? Icons.folder_outlined
                  : Icons.description_outlined,
            ),
            title: Text(entry.name),
            subtitle: switch (entry.size) {
              final size? when !entry.isDirectory => Text(
                formatBytes(context, size),
              ),
              _ => null,
            },
            onTap: state.busy
                ? null
                : () =>
                      entry.isDirectory ? viewModel.open(entry) : _pick(entry),
          ),
      ],
    );
  }
}
