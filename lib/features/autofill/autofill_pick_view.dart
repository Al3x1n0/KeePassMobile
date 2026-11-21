import 'package:material_ui/material_ui.dart';

import '../../shared/ui/remote_cache_banner.dart';
import '../../shared/database/database_session.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/ui/entry_tile.dart';
import '../search/search_view_model.dart';
import 'autofill_channel.dart';
import 'autofill_matcher.dart';
import 'autofill_pick_view_model.dart';

/// Scelta della voce da compilare (`ChooseForAutofillActivity` di
/// Keepass2Android): prima le voci dell'app o del sito, poi la ricerca su tutto
/// il database. Una voce scelta con la ricerca si può ricordare (D28).
class AutofillPickView extends ConsumerStatefulWidget {
  const AutofillPickView({super.key});

  @override
  ConsumerState<AutofillPickView> createState() => _AutofillPickViewState();
}

class _AutofillPickViewState extends ConsumerState<AutofillPickView> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _choose(KdbxEntry entry, {required bool matched}) async {
    final viewModel = ref.read(autofillPickViewModelProvider.notifier);
    if (ref.read(autofillPickViewModelProvider).isLoading ||
        (ref.read(databaseSessionProvider)?.cacheStatus.synchronizing ??
            false)) {
      return;
    }
    final query = ref.read(autofillQueryProvider);
    final request = ref.read(autofillRequestProvider);
    final appNeedsConfirmation =
        query == request.appQuery &&
        !ref.read(autofillTrustRepositoryProvider).isAppTrusted(request);
    final exact = matched && isExactAutofillMatch(entry, query);
    if (exact && !appNeedsConfirmation) {
      await viewModel.fill(entry.uuid);
      return;
    }
    final choice = await _confirm(
      entry,
      request,
      query,
      approximate: matched && !exact,
      confirmApp: exact && appNeedsConfirmation,
    );
    if (choice == null ||
        !mounted ||
        ref.read(autofillQueryProvider) != query) {
      return;
    }
    await viewModel.fill(entry.uuid, choice: choice);
  }

  Future<AutofillChoice?> _confirm(
    KdbxEntry entry,
    AutofillRequest request,
    String query, {
    required bool approximate,
    required bool confirmApp,
  }) {
    final l10n = AppLocalizations.of(context);
    final appTarget = query == request.appQuery;
    final target = appTarget
        ? request.packageName
        : l10n.autofillSiteInApp(query, request.packageName);
    final title = entryTitle(entry).isEmpty
        ? l10n.entryUntitled
        : entryTitle(entry);
    final rememberBody = l10n.autofillRememberBody(
      target,
      title,
      nextAutofillField(entry, query),
    );
    final message = switch ((confirmApp, approximate)) {
      (true, _) => l10n.autofillAppIdentityWarning(title, target),
      (_, true) => l10n.autofillApproximateBody(title, target),
      _ => rememberBody,
    };
    final description =
        !approximate &&
            appTarget &&
            request.canRememberApp &&
            !ref.read(autofillTrustRepositoryProvider).isAppTrusted(request)
        ? '$message\n\n${l10n.autofillRememberAppSignature}'
        : message;
    return showDialog<AutofillChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          approximate || confirmApp
              ? l10n.autofillApproximateTitle
              : l10n.autofillRememberTitle,
        ),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(AutofillChoice.once),
            child: Text(l10n.autofillFillOnly),
          ),
          if (confirmApp && request.canRememberApp)
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(AutofillChoice.rememberApp),
              child: Text(l10n.autofillFillAndRememberApp),
            ),
          if (!approximate && !confirmApp)
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(AutofillChoice.rememberEntry),
              child: Text(l10n.autofillFillAndRemember),
            ),
        ],
      ),
    );
  }

  /// Sito o app da mostrare, senza schema.
  static String _targetOf(String query) => query.startsWith(androidAppScheme)
      ? query.substring(androidAppScheme.length)
      : query;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final request = ref.watch(autofillRequestProvider);
    final useDomain = ref.watch(autofillUseDomainProvider);
    final query = ref.watch(autofillQueryProvider);
    final matches = ref.watch(autofillMatchesProvider) ?? const [];
    final results = _query.trim().isEmpty
        ? const <SearchResult>[]
        : ref.watch(searchResultsProvider(_query)) ?? const [];
    final state = ref.watch(autofillPickViewModelProvider);
    final domain = request.webDomain;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.autofillClose,
          icon: const Icon(Icons.close),
          onPressed: () =>
              ref.read(autofillPickViewModelProvider.notifier).cancel(),
        ),
        title: Text(l10n.autofillPickTitle),
      ),
      body: ListView(
        children: [
          const RemoteCacheBanner(),
          ListTile(
            leading: Icon(
              query.startsWith(androidAppScheme)
                  ? Icons.apps_outlined
                  : Icons.language_outlined,
            ),
            title: Text(l10n.autofillFor(_targetOf(query))),
            subtitle: useDomain ? Text(request.packageName) : null,
          ),
          if (domain != null && !useDomain)
            AutofillDomainWarning(request: request),
          if (state.isLoading) const LinearProgressIndicator(),
          if (state case AsyncError(:final error))
            Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  describeSaveError(l10n, error),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          _Section(l10n.autofillMatches),
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
              child: Text(l10n.autofillNoMatches),
            )
          else
            for (final entry in matches)
              EntryTile(
                entry: entry,
                onTap: () => _choose(entry, matched: true),
              ),
          _Section(l10n.autofillSearchAll),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
            child: TextField(
              controller: _search,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              textInputAction: TextInputAction.search,
              inputFormatters: [
                LengthLimitingTextInputFormatter(AppLimits.searchQuery),
              ],
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                labelText: l10n.autofillSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          for (final result in results)
            EntryTile(
              entry: result.entry,
              groupName: result.groupName,
              onTap: () => _choose(
                result.entry,
                matched: matches.contains(result.entry),
              ),
            ),
          const SizedBox(height: AppSpacing.l),
        ],
      ),
    );
  }
}

/// Chiede conferma per un dominio dichiarato dalla app destinataria.
class AutofillDomainWarning extends ConsumerWidget {
  const AutofillDomainWarning({super.key, required this.request});

  final AutofillRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notifier = ref.read(autofillUseDomainProvider.notifier);
    return Card(
      margin: const EdgeInsets.all(AppSpacing.m),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    l10n.autofillDomainWarning(
                      request.packageName,
                      request.webDomain!,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.s,
              children: [
                TextButton(
                  onPressed: notifier.useOnce,
                  child: Text(l10n.autofillUseDomainOnce),
                ),
                if (request.canRememberDomain)
                  FilledButton.tonal(
                    onPressed: notifier.useAlways,
                    child: Text(l10n.autofillUseDomainAlways),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.l,
        AppSpacing.m,
        AppSpacing.s,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
