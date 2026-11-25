import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../app/theme.dart';
import '../../app/routes.dart';
import '../../l10n/app_localizations.dart';
import '../database/kdbx_items.dart';
import '../database/database_session.dart';
import '../database/field_references.dart';
import '../settings/app_settings.dart';
import 'database_item_icon.dart';
import 'entry_color.dart';

/// Riga di una voce negli elenchi (gruppo e ricerca). Il nome utente compare
/// solo con l'impostazione "Nome utente negli elenchi".
class EntryTile extends ConsumerWidget {
  const EntryTile({
    super.key,
    required this.entry,
    this.groupName,
    this.additionalInfo,
    this.databaseOverride,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.showChevron = true,
  });

  final KdbxEntry entry;

  /// Nome del gruppo, mostrato nei risultati di ricerca.
  final String? groupName;
  final String? additionalInfo;
  final KdbxDatabase? databaseOverride;

  /// Tocco sulla riga; se manca apre la voce.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool enabled;

  /// Se mostrare la freccia verso il dettaglio della voce.
  final bool showChevron;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final showUserName = ref.watch(
      appSettingsProvider.select((s) => s.showUserNameInList),
    );
    final textSize = ref
        .watch(appSettingsProvider.select((s) => s.listTextSize))
        .toDouble();
    final database =
        databaseOverride ?? ref.watch(databaseSessionProvider)?.database;
    final title = visibleEntryTitle(database, entry);
    final resolvedUserName = showUserName && database != null
        ? resolveEntryField(database, entry, EntryFields.userName)
        : null;
    final userName =
        resolvedUserName != null &&
            resolvedUserName.valid &&
            !resolvedUserName.protected
        ? resolvedUserName.text
        : '';
    final expired = isExpired(entry, DateTime.now());
    // Voce scaduta: icona dedicata e testo barrato, come PwEntryView.
    final strike = expired
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;
    final details = [
      if (userName.isNotEmpty) userName,
      if (groupName case final g? when g.isNotEmpty) g,
      if (additionalInfo case final info? when info.isNotEmpty) info,
    ];
    final tile = ListTile(
      enabled: enabled,
      leading: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: DatabaseItemIcon(
          item: entry,
          database: database,
          expired: expired,
        ),
      ),
      title: Text(
        title.isEmpty ? l10n.entryUntitled : title,
        style: (strike ?? const TextStyle()).copyWith(fontSize: textSize),
      ),
      subtitle: details.isEmpty
          ? null
          : Text(
              details.join(' · '),
              style: (strike ?? const TextStyle()).copyWith(
                fontSize: (textSize * .75).roundToDouble(),
              ),
            ),
      trailing: selected
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
          : showChevron
          ? const Icon(Icons.chevron_right)
          : null,
      onTap: !enabled
          ? null
          : onTap ?? () => context.push(AppRoutes.entry(itemIdOf(entry))),
      onLongPress: enabled ? onLongPress : null,
      selected: selected,
    );
    final color = adaptEntryColor(entry.background);
    if (color == null) return tile;
    return Stack(
      children: [
        tile,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: AppEntryColorLayout.stripeWidth,
          child: IgnorePointer(
            child: Semantics(
              label: l10n.entryColorIndicator(color.label(l10n)),
              child: Opacity(
                opacity: enabled ? 1 : 0.38,
                child: ColoredBox(color: color.color),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
