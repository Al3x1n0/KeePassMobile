import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../entry_edit/entry_edit_view_model.dart';
import 'autofill_channel.dart';
import 'autofill_pick_view_model.dart';

class AutofillSaveView extends ConsumerStatefulWidget {
  const AutofillSaveView({super.key});

  @override
  ConsumerState<AutofillSaveView> createState() => _AutofillSaveViewState();
}

class _AutofillSaveViewState extends ConsumerState<AutofillSaveView> {
  bool _saving = false;
  bool _attempted = false;
  Object? _error;

  String? _validDomain(AutofillRequest request) {
    final domain = request.webDomain;
    if (!request.isBrowser ||
        domain == null ||
        !RegExp(r'^[a-z0-9.-]+$').hasMatch(domain) ||
        !domain.contains('.') ||
        domain.startsWith('.') ||
        domain.endsWith('.') ||
        domain.contains('..')) {
      return null;
    }
    return domain;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _attempted = true;
      _error = null;
    });
    try {
      final request = ref.read(autofillRequestProvider);
      final session = ref.read(databaseSessionProvider);
      if (session == null) {
        throw const DatabaseLockedException();
      }
      final password = await ref
          .read(autofillChannelProvider)
          .takeSavePassword();
      if (password == null ||
          password.isEmpty ||
          ref.read(databaseSessionProvider) != session) {
        throw const DatabaseLockedException();
      }
      final domain = _validDomain(request);
      final useDomain = domain != null;
      final target = domain ?? request.packageName;
      final uuid = KdbxUuid.random(
        prohibited: session.database.root.allItems.map((i) => i.uuid).toSet(),
      );
      final draft = EntryDraft(
        title: target,
        userName: request.userName ?? '',
        password: password,
        url: useDomain ? 'https://$domain' : '',
        custom: useDomain
            ? const []
            : [
                CustomFieldDraft(
                  key: 'AndroidApp1',
                  value: request.appQuery,
                  protected: false,
                ),
              ],
      );
      await ref
          .read(databaseSessionProvider.notifier)
          .apply(createEntryEdit(session.database.root.uuid, uuid, draft));
      ref.read(autofillDoneProvider.notifier).done();
      ref.read(databaseSessionProvider.notifier).lock();
      await ref.read(autofillChannelProvider).cancel();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final request = ref.watch(autofillRequestProvider);
    final session = ref.watch(databaseSessionProvider);
    final target = _validDomain(request) ?? request.packageName;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.autofillSaveTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.autofillSaveDescription),
          ListTile(
            title: Text(l10n.autofillSaveTarget),
            subtitle: Text(target),
          ),
          ListTile(
            title: Text(l10n.autofillSaveUser),
            subtitle: Text(request.userName ?? ''),
          ),
          ListTile(
            title: Text(l10n.autofillSaveDatabase),
            subtitle: Text(session?.file.name ?? ''),
          ),
          ListTile(
            title: Text(l10n.autofillSavePassword),
            subtitle: const Text('••••••••'),
          ),
          if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  describeSaveError(l10n, _error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                Text(l10n.autofillSaveRetry),
              ],
            ),
          if (_saving) const LinearProgressIndicator(),
          FilledButton(
            onPressed: _saving || _attempted ? null : _save,
            child: Text(l10n.autofillSaveConfirm),
          ),
          TextButton(
            onPressed: _saving
                ? null
                : () =>
                      ref.read(autofillPickViewModelProvider.notifier).cancel(),
            child: Text(l10n.autofillClose),
          ),
        ],
      ),
    );
  }
}
