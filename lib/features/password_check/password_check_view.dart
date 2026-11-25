import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/database_navigation_shell.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/ui/entry_tile.dart';
import '../../shared/ui/expandable_section.dart';
import 'password_check_view_model.dart';
import 'password_strength.dart';

class PasswordCheckView extends ConsumerStatefulWidget {
  const PasswordCheckView({super.key});

  @override
  ConsumerState<PasswordCheckView> createState() => _PasswordCheckViewState();
}

class _PasswordCheckViewState extends ConsumerState<PasswordCheckView> {
  final _duplicates = GlobalKey();
  final _weak = GlobalKey();
  final _protected = GlobalKey();

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppNavigationLayout.transitionDuration,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final report = ref.watch(passwordCheckReportProvider);
    final database = ref.watch(databaseSessionProvider)?.database;
    Widget note(String text) =>
        Padding(padding: const EdgeInsets.all(AppSpacing.m), child: Text(text));
    Widget entry(String id, {String? detail}) {
      final item = database == null ? null : findEntry(database, id);
      if (item == null) return const SizedBox.shrink();
      return EntryTile(entry: item, additionalInfo: detail);
    }

    if (report == null) return const SizedBox.shrink();
    final empty =
        report.analyzedPasswordEntriesCount == 0 &&
        report.protectedFieldNotices.isEmpty;
    final attention =
        report.duplicateGroups.isNotEmpty ||
        report.weakEntries.any(
          (e) => e.strength.level == PasswordStrengthLevel.veryWeak,
        );
    final improve = !attention && report.weakEntries.isNotEmpty;
    final color = empty
        ? colors.onSurfaceVariant
        : attention
        ? colors.error
        : improve
        ? (theme.brightness == Brightness.dark
              ? Colors.orange.shade300
              : Colors.orange.shade800)
        : (theme.brightness == Brightness.dark
              ? Colors.green.shade300
              : Colors.green.shade700);
    final title = empty
        ? l10n.checkEmpty
        : attention
        ? l10n.checkAttention
        : improve
        ? l10n.checkImprove
        : l10n.checkAllGood;
    Widget counter(String label, int count, GlobalKey target) => Tooltip(
      message: '$label: $count',
      child: OutlinedButton(
        onPressed: count == 0 ? null : () => _scrollTo(target),
        child: Text('$label: $count', textAlign: TextAlign.center),
      ),
    );
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(l10n.navigationCheck),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: DatabaseNavigationShell.bottomBar(
        context,
        checkSelected: true,
      ),
      body: Builder(
        builder: (context) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.m,
            AppSpacing.m,
            AppSpacing.m,
            AppSpacing.m + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        empty
                            ? Icons.info_outline
                            : attention
                            ? Icons.gpp_bad_outlined
                            : improve
                            ? Icons.gpp_maybe_outlined
                            : Icons.verified_user_outlined,
                        color: color,
                        size: 40,
                      ),
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: color,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      Text(
                        l10n.checkSummary(report.analyzedPasswordEntriesCount),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      Wrap(
                        spacing: AppSpacing.s,
                        runSpacing: AppSpacing.s,
                        children: [
                          counter(
                            l10n.checkDuplicates,
                            report.duplicateGroups.fold(
                              0,
                              (sum, g) => sum + g.entryIds.length,
                            ),
                            _duplicates,
                          ),
                          counter(
                            l10n.checkWeak,
                            report.weakEntries.length,
                            _weak,
                          ),
                          if (report.protectedFieldNotices.isNotEmpty)
                            counter(
                              l10n.checkOtherProtected,
                              report.protectedFieldNotices.length,
                              _protected,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              note(l10n.checkExclusions('{REF:...} / {S:...}')),
              if (report.duplicateGroups.isNotEmpty)
                ExpandableSection(
                  key: _duplicates,
                  title: l10n.checkDuplicates,
                  children: [
                    for (final group in report.duplicateGroups) ...[
                      note(l10n.checkSharedCount(group.entryIds.length)),
                      for (final id in group.entryIds) entry(id),
                    ],
                  ],
                ),
              if (report.weakEntries.isNotEmpty)
                ExpandableSection(
                  key: _weak,
                  title: l10n.checkWeak,
                  children: [
                    for (final item in report.weakEntries)
                      entry(
                        item.entryId,
                        detail:
                            '${item.strength.level == PasswordStrengthLevel.veryWeak ? l10n.checkVeryWeak : l10n.checkWeakLevel} · ${_reason(l10n, item.strength.reason)}',
                      ),
                  ],
                ),
              if (report.protectedFieldNotices.isNotEmpty)
                ExpandableSection(
                  key: _protected,
                  title: l10n.checkOtherProtected,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.m),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: colors.onSurfaceVariant,
                          ),
                          Text(l10n.checkProtectedExplanation),
                        ],
                      ),
                    ),
                    for (final item in report.protectedFieldNotices)
                      entry(
                        item.entryId,
                        detail: [
                          item.fieldName,
                          if (item.strength.isWeak)
                            _reason(l10n, item.strength.reason),
                          if (item.reused) l10n.checkReused,
                        ].join(' · '),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _reason(AppLocalizations l10n, PasswordWeaknessReason? reason) =>
    switch (reason) {
      PasswordWeaknessReason.tooShort => l10n.checkTooShort,
      PasswordWeaknessReason.digitsOnly => l10n.checkDigitsOnly,
      PasswordWeaknessReason.lowVariety => l10n.checkLowVariety,
      PasswordWeaknessReason.commonPattern => l10n.checkCommonPattern,
      PasswordWeaknessReason.limitedComplexity => l10n.checkLimitedComplexity,
      null => '',
    };
