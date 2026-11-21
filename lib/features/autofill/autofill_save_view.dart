import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../entry_edit/entry_edit_view_model.dart';
import 'autofill_channel.dart';
import 'autofill_pick_view.dart';
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

  Future<void> _save({
    required String? domain,
    required bool rememberApp,
  }) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _attempted = true;
      _error = null;
    });
    try {
      final request = ref.read(autofillRequestProvider);
      final trust = ref.read(autofillTrustRepositoryProvider);
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
      if (rememberApp) await trust.trustApp(request);
      if (!mounted) return;
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
    final useDomain = ref.watch(autofillUseDomainProvider);
    final domain = request.webDomain;
    final selectedDomain = useDomain ? domain : null;
    final rememberApp =
        selectedDomain == null &&
        request.canRememberApp &&
        !ref.watch(autofillTrustRepositoryProvider).isAppTrusted(request);
    final target = selectedDomain != null
        ? l10n.autofillSiteInApp(selectedDomain, request.packageName)
        : request.packageName;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.autofillSaveTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.autofillSaveDescription),
          if (domain != null && !useDomain)
            AutofillDomainWarning(request: request),
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
          if (rememberApp) Text(l10n.autofillRememberAppSignature),
          FilledButton(
            onPressed: _saving || _attempted
                ? null
                : () => _save(domain: selectedDomain, rememberApp: false),
            child: Text(l10n.autofillSaveConfirm),
          ),
          if (rememberApp)
            FilledButton.tonal(
              onPressed: _saving || _attempted
                  ? null
                  : () => _save(domain: selectedDomain, rememberApp: true),
              child: Text(l10n.autofillSaveAndRememberApp),
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
