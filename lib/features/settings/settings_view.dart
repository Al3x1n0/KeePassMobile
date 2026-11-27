import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/ui/app_dialog.dart';
import '../../app/database_navigation_shell.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/entry_templates.dart';
import '../../shared/database/item_edits.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/licenses/bundled_licenses.dart';
import '../../shared/security/device_security.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/ui/demo_database_dialog.dart';
import '../../shared/ui/expandable_section.dart';
import '../../shared/ui/linked_database_edit_dialog.dart';
import '../../shared/ui/selection_sheet.dart';
import '../../shared/ui/url_opener.dart';
import '../autofill/autofill_channel.dart';
import '../export/export_view_model.dart';
import '../file_select/demo_database.dart';
import 'settings_view_model.dart';

/// Impostazioni dell'app, raggiungibili con il database aperto o chiuso.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key, this.showDatabaseNavigation = false});

  final bool showDatabaseNavigation;

  /// Valore delle voci "mai" negli elenchi a scelta.
  static const _never = -1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsViewModelProvider);
    final appVersion = ref.watch(settingsAppVersionProvider).value;
    final session = showDatabaseNavigation
        ? ref.watch(databaseSessionProvider)
        : null;
    final rootId = session == null
        ? null
        : idOfUuid(session.database.root.uuid);
    final exporting =
        rootId != null &&
        ref.watch(exportDatabaseViewModelProvider.select((s) => s.isLoading));
    final installingTemplates =
        rootId != null &&
        ref.watch(itemActionsProvider(rootId).select((s) => s.isLoading));
    final canInstallTemplates = !installingTemplates && !exporting;
    final canLinkDatabase =
        session != null &&
        ref.watch(databaseSessionProvider.notifier).openSessions.length > 1;
    final showNavigation = showDatabaseNavigation && session != null;
    void update(AppSettings next) =>
        ref.read(settingsViewModelProvider.notifier).update(next);

    return Scaffold(
      extendBody: showNavigation,
      appBar: AppBar(
        automaticallyImplyLeading: !showNavigation,
        title: Text(l10n.settingsTitle),
      ),
      bottomNavigationBar: showNavigation
          ? DatabaseNavigationShell.bottomBar(context, settingsSelected: true)
          : null,
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.m,
          ),
          children: [
            if (rootId != null)
              ExpandableSection(
                key: const ValueKey('settings-database'),
                title: l10n.settingsDatabase,
                children: [
                  ListTile(
                    title: Text(l10n.dbSettingsTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.databaseSettings),
                  ),
                  ListTile(
                    title: Text(l10n.changeKeyTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.changeMasterKey),
                  ),
                  ListTile(
                    title: Text(l10n.exportTitle),
                    enabled: !exporting,
                    onTap: exporting
                        ? null
                        : () => _exportDatabase(context, ref),
                  ),
                  ListTile(
                    title: Text(l10n.templatesInstall),
                    subtitle: Text(l10n.templatesInstallHint),
                    enabled: canInstallTemplates,
                    onTap: canInstallTemplates
                        ? () => _addBuiltInTemplates(context, ref, rootId)
                        : null,
                  ),
                  if (canLinkDatabase)
                    ListTile(
                      title: Text(l10n.linkedDatabaseAdd),
                      subtitle: Text(l10n.linkedDatabaseAddHint),
                      onTap: () => addLinkedDatabase(context, ref),
                    ),
                ],
              ),
            ExpandableSection(
              key: const ValueKey('settings-security'),
              title: l10n.settingsSecurity,
              children: [
                _SelectionTile(
                  title: l10n.settingsClipboardTimeout,
                  value: l10n.settingsSeconds(
                    settings.clipboardTimeout.inSeconds,
                  ),
                  onTap: () async {
                    final duration = await showSelectionSheet<Duration>(
                      context: context,
                      title: l10n.settingsClipboardTimeout,
                      selected: settings.clipboardTimeout,
                      options: {
                        for (final d in AppSettings.clipboardTimeouts)
                          d: l10n.settingsSeconds(d.inSeconds),
                      },
                    );
                    if (context.mounted && duration != null) {
                      update(
                        ref
                            .read(settingsViewModelProvider)
                            .copyWith(clipboardTimeout: duration),
                      );
                    }
                  },
                ),
                _SelectionTile(
                  title: l10n.settingsLockTimeout,
                  value: _lockLabel(l10n, settings.lockTimeout),
                  onTap: () async {
                    final milliseconds = await showSelectionSheet<int>(
                      context: context,
                      title: l10n.settingsLockTimeout,
                      selected: settings.lockTimeout?.inMilliseconds ?? _never,
                      options: {
                        for (final d in AppSettings.lockTimeouts)
                          d?.inMilliseconds ?? _never: _lockLabel(l10n, d),
                      },
                    );
                    if (context.mounted && milliseconds != null) {
                      update(
                        ref
                            .read(settingsViewModelProvider)
                            .copyWith(
                              lockTimeout: milliseconds == _never
                                  ? null
                                  : Duration(milliseconds: milliseconds),
                            ),
                      );
                    }
                  },
                ),
                SwitchListTile(
                  title: Text(l10n.settingsLockInBackground),
                  subtitle: Text(l10n.settingsLockInBackgroundHint),
                  value: settings.lockInBackground,
                  onChanged: (v) =>
                      update(settings.copyWith(lockInBackground: v)),
                ),
                SwitchListTile(
                  title: Text(l10n.settingsLockOnScreenOff),
                  subtitle: Text(l10n.settingsLockOnScreenOffHint),
                  value: settings.lockOnScreenOff,
                  onChanged: (v) =>
                      update(settings.copyWith(lockOnScreenOff: v)),
                ),
                if (ref.watch(appSecurityProvider).supportsOpenNotification)
                  SwitchListTile(
                    title: Text(l10n.settingsOpenNotification),
                    subtitle: Text(l10n.settingsOpenNotificationHint),
                    value: settings.openNotification,
                    onChanged: (v) =>
                        update(settings.copyWith(openNotification: v)),
                  ),
                const _AutofillTile(),
                SwitchListTile(
                  title: Text(l10n.settingsSecureScreen),
                  subtitle: Text(l10n.settingsSecureScreenHint),
                  value: settings.secureScreen,
                  onChanged: (v) => update(settings.copyWith(secureScreen: v)),
                ),
                SwitchListTile(
                  title: Text(l10n.settingsExpireTan),
                  subtitle: Text(l10n.settingsExpireTanHint),
                  value: settings.expireTanOnOpen,
                  onChanged: (v) =>
                      update(settings.copyWith(expireTanOnOpen: v)),
                ),
              ],
            ),
            ExpandableSection(
              key: const ValueKey('settings-display'),
              title: l10n.settingsDisplay,
              children: [
                SwitchListTile(
                  title: Text(l10n.settingsMaskPassword),
                  value: settings.maskPassword,
                  onChanged: (v) => update(settings.copyWith(maskPassword: v)),
                ),
                SwitchListTile(
                  title: Text(l10n.settingsMaskTotp),
                  value: settings.maskTotp,
                  onChanged: (v) => update(settings.copyWith(maskTotp: v)),
                ),
                SwitchListTile(
                  title: Text(l10n.settingsShowUserName),
                  value: settings.showUserNameInList,
                  onChanged: (v) =>
                      update(settings.copyWith(showUserNameInList: v)),
                ),
                SwitchListTile(
                  title: Text(l10n.settingsShowGroupNameInSearch),
                  value: settings.showGroupNameInSearch,
                  onChanged: (v) =>
                      update(settings.copyWith(showGroupNameInSearch: v)),
                ),
                SwitchListTile(
                  title: Text(l10n.settingsShowGroupInEntry),
                  value: settings.showGroupInEntry,
                  onChanged: (v) =>
                      update(settings.copyWith(showGroupInEntry: v)),
                ),
                SwitchListTile(
                  title: Text(l10n.recentPasswordsTitle),
                  subtitle: Text(l10n.settingsRecentPasswordsHint),
                  value: settings.showRecentPasswords,
                  onChanged: (value) =>
                      update(settings.copyWith(showRecentPasswords: value)),
                ),
                _SelectionTile(
                  title: l10n.settingsRecentPasswordLimit,
                  value: settings.recentPasswordLimit.toString(),
                  onTap: () async {
                    final limit = await showSelectionSheet<int>(
                      context: context,
                      title: l10n.settingsRecentPasswordLimit,
                      selected: settings.recentPasswordLimit,
                      options: {
                        for (final limit in AppSettings.recentPasswordLimits)
                          limit: limit.toString(),
                      },
                    );
                    if (context.mounted && limit != null) {
                      update(
                        ref
                            .read(settingsViewModelProvider)
                            .copyWith(recentPasswordLimit: limit),
                      );
                    }
                  },
                ),
                _SelectionTile(
                  title: l10n.settingsListTextSize,
                  value: switch (settings.listTextSize) {
                    15 => l10n.settingsSizeSmall,
                    28 => l10n.settingsSizeLarge,
                    _ => l10n.settingsSizeMedium,
                  },
                  onTap: () async {
                    final size = await showSelectionSheet<int>(
                      context: context,
                      title: l10n.settingsListTextSize,
                      selected: settings.listTextSize,
                      options: {
                        15: l10n.settingsSizeSmall,
                        20: l10n.settingsSizeMedium,
                        28: l10n.settingsSizeLarge,
                      },
                    );
                    if (context.mounted && size != null) {
                      update(settings.copyWith(listTextSize: size));
                    }
                  },
                ),
                _SelectionTile(
                  title: l10n.settingsLanguage,
                  value: settings.languageCode == 'it'
                      ? 'Italiano'
                      : settings.languageCode == 'en'
                      ? 'English'
                      : l10n.settingsLanguageSystem,
                  onTap: () async {
                    final language = await showSelectionSheet<String>(
                      context: context,
                      title: l10n.settingsLanguage,
                      selected: settings.languageCode ?? 'system',
                      options: {
                        'system': l10n.settingsLanguageSystem,
                        'it': 'Italiano',
                        'en': 'English',
                      },
                    );
                    if (context.mounted && language != null) {
                      update(
                        ref
                            .read(settingsViewModelProvider)
                            .copyWith(
                              languageCode: language == 'system'
                                  ? null
                                  : language,
                            ),
                      );
                    }
                  },
                ),
                _SelectionTile(
                  title: l10n.settingsTheme,
                  value: switch (settings.themeMode) {
                    ThemeMode.system => l10n.settingsThemeSystem,
                    ThemeMode.light => l10n.settingsThemeLight,
                    ThemeMode.dark => l10n.settingsThemeDark,
                  },
                  onTap: () async {
                    final mode = await showSelectionSheet<ThemeMode>(
                      context: context,
                      title: l10n.settingsTheme,
                      selected: settings.themeMode,
                      options: {
                        ThemeMode.system: l10n.settingsThemeSystem,
                        ThemeMode.light: l10n.settingsThemeLight,
                        ThemeMode.dark: l10n.settingsThemeDark,
                      },
                    );
                    if (context.mounted && mode != null) {
                      ref
                          .read(settingsViewModelProvider.notifier)
                          .update(
                            ref
                                .read(settingsViewModelProvider)
                                .copyWith(themeMode: mode),
                          );
                    }
                  },
                ),
              ],
            ),
            ExpandableSection(
              key: const ValueKey('settings-files'),
              title: l10n.settingsFiles,
              children: [
                SwitchListTile(
                  title: Text(l10n.settingsRemoteCache),
                  subtitle: Text(l10n.settingsRemoteCacheHint),
                  value: settings.cacheRemoteFiles,
                  onChanged: (v) =>
                      update(settings.copyWith(cacheRemoteFiles: v)),
                ),
                const _RemoteCacheClearTile(),
                SwitchListTile(
                  title: Text(l10n.settingsRememberRecentFiles),
                  value: settings.rememberRecentFiles,
                  onChanged: (v) async {
                    if (!v &&
                        ref.read(demoDatabaseRepositoryProvider).isPresent) {
                      final confirmed = await showDemoDatabaseRemovalDialog(
                        context,
                        clearingRecents: true,
                      );
                      if (!confirmed || !context.mounted) return;
                    }
                    try {
                      await ref
                          .read(settingsViewModelProvider.notifier)
                          .update(
                            ref
                                .read(settingsViewModelProvider)
                                .copyWith(rememberRecentFiles: v),
                          );
                    } on Exception {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.errorGeneric)),
                      );
                    }
                  },
                ),
                // Il file chiave si ricorda solo insieme al database.
                SwitchListTile(
                  title: Text(l10n.settingsRememberKeyFile),
                  value:
                      settings.rememberRecentFiles && settings.rememberKeyFile,
                  onChanged: settings.rememberRecentFiles
                      ? (v) => update(settings.copyWith(rememberKeyFile: v))
                      : null,
                ),
              ],
            ),
            ExpandableSection(
              key: const ValueKey('settings-about'),
              title: l10n.settingsAbout,
              children: [
                ListTile(
                  title: Text(
                    MaterialLocalizations.of(context).licensesPageTitle,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    registerBundledLicenses();
                    showLicensePage(
                      context: context,
                      applicationName: 'KeePassMobile',
                      useRootNavigator: true,
                    );
                  },
                ),
                ListTile(
                  title: Text(l10n.settingsSourceCode),
                  subtitle: Text(l10n.settingsSourceCodeHost),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () async {
                    final opened = await ref
                        .read(urlOpenerProvider)
                        .open(
                          Uri.parse('https://github.com/Al3x1n0/KeePassMobile'),
                        );
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.entryUrlNoApp)),
                      );
                    }
                  },
                ),
                ListTile(
                  title: Text(l10n.settingsPrivacyPolicy),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () async {
                    final opened = await ref
                        .read(urlOpenerProvider)
                        .open(
                          Uri.parse(
                            'https://al3x1n0.github.io/KeePassMobile/privacy/',
                          ),
                        );
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.entryUrlNoApp)),
                      );
                    }
                  },
                ),
                LayoutBuilder(
                  builder: (context, constraints) => ListTile(
                    title: Text(l10n.settingsAppVersion),
                    trailing: SizedBox(
                      width: constraints.maxWidth * 0.4,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(appVersion ?? '—'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportDatabase(BuildContext context, WidgetRef ref) async {
    final name = await ref
        .read(exportDatabaseViewModelProvider.notifier)
        .export();
    if (!context.mounted || ref.read(databaseSessionProvider) == null) return;

    final l10n = AppLocalizations.of(context);
    final state = ref.read(exportDatabaseViewModelProvider);
    final message = switch ((name, state)) {
      (final n?, _) => l10n.exportDone(n),
      (_, AsyncError(:final error)) => describeSaveError(l10n, error),
      _ => null,
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _addBuiltInTemplates(
    BuildContext context,
    WidgetRef ref,
    String rootId,
  ) async {
    final file = ref.read(databaseSessionProvider)?.file;
    if (file == null) return;
    final sessions = ref.read(databaseSessionProvider.notifier);
    final generation = sessions.lockGeneration;
    bool isCurrentSession() =>
        sessions.lockGeneration == generation &&
        ref.read(databaseSessionProvider)?.file == file;

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: Text(l10n.templatesInstall),
        body: Text(l10n.templatesInstallConfirm),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          AppDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.dialogAdd),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted || !isCurrentSession()) return;

    final actions = itemActionsProvider(rootId);
    final installed = await ref
        .read(actions.notifier)
        .addBuiltInTemplates(
          BuiltInTemplateLabels(
            group: l10n.templateGroup,
            idCard: l10n.templateIdCard,
            wlan: l10n.templateWlan,
            note: l10n.templateNote,
            creditCard: l10n.templateCreditCard,
            membership: l10n.templateMembership,
            number: l10n.templateNumber,
            name: l10n.templateName,
            place: l10n.templatePlace,
            issueDate: l10n.templateIssueDate,
            holder: l10n.templateHolder,
          ),
        );
    if (!context.mounted || !isCurrentSession()) return;

    final message = switch ((installed, ref.read(actions))) {
      (true, _) => l10n.templatesInstallSuccess,
      (_, AsyncError(:final error)) => describeSaveError(l10n, error),
      _ => null,
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  static String _lockLabel(AppLocalizations l10n, Duration? d) => switch (d) {
    null => l10n.settingsLockNever,
    _ when d.inSeconds < 60 => l10n.settingsSeconds(d.inSeconds),
    _ => l10n.settingsMinutes(d.inMinutes),
  };
}

class _SelectionTile extends StatelessWidget {
  const _SelectionTile({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Row(
      children: [
        Expanded(flex: 3, child: Text(title)),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

/// "Compilazione automatica": stato del servizio e scelta nelle impostazioni di
/// sistema (solo Android 8+). Lo stato si rilegge al ritorno nell'app.
class _AutofillTile extends ConsumerStatefulWidget {
  const _AutofillTile();

  @override
  ConsumerState<_AutofillTile> createState() => _AutofillTileState();
}

class _AutofillTileState extends ConsumerState<_AutofillTile> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(autofillServiceStatusProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(autofillServiceStatusProvider).value;
    if (status == null || !status.supported) return const SizedBox.shrink();
    return ListTile(
      title: Text(l10n.settingsAutofill),
      subtitle: Text(
        status.enabled ? l10n.settingsAutofillOn : l10n.settingsAutofillOff,
      ),
      trailing: const Icon(Icons.open_in_new),
      onTap: () => ref.read(autofillSettingsProvider).openSystemSettings(),
    );
  }
}

class _RemoteCacheClearTile extends ConsumerStatefulWidget {
  const _RemoteCacheClearTile();

  @override
  ConsumerState<_RemoteCacheClearTile> createState() =>
      _RemoteCacheClearTileState();
}

class _RemoteCacheClearTileState extends ConsumerState<_RemoteCacheClearTile> {
  bool _busy = false;

  Future<void> _clear(AppLocalizations l10n) async {
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AppDialog(
          title: Text(l10n.settingsRemoteCacheClear),
          body: Text(l10n.settingsRemoteCacheClearConfirm),
          actions: [
            AppDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            AppDialogAction(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.entryDelete),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final complete = await ref
          .read(settingsViewModelProvider.notifier)
          .clearSynchronizedRemoteCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            complete
                ? l10n.settingsRemoteCacheClearDone
                : l10n.settingsRemoteCacheClearIncomplete,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(l10n.settingsRemoteCacheClear),
      enabled: !_busy,
      onTap: _busy ? null : () => _clear(l10n),
    );
  }
}
