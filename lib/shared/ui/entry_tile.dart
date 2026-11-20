import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../app/routes.dart';
import '../../l10n/app_localizations.dart';
import '../database/kdbx_items.dart';
import '../database/database_session.dart';
import '../database/field_references.dart';
import '../settings/app_settings.dart';
import 'database_item_icon.dart';

Color? _entryColor(String? value) {
  if (value == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
    return null;
  }
  return Color(0xff000000 | int.parse(value.substring(1), radix: 16));
}

/// Riga di una voce negli elenchi (gruppo e ricerca). Il nome utente compare
/// solo con l'impostazione "Nome utente negli elenchi".
class EntryTile extends ConsumerWidget {
  const EntryTile({
    super.key,
    required this.entry,
    this.groupName,
    this.databaseOverride,
    this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  final KdbxEntry entry;

  /// Nome del gruppo, mostrato nei risultati di ricerca.
  final String? groupName;
  final KdbxDatabase? databaseOverride;

  /// Tocco sulla riga; se manca apre la voce.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;

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
    ];
    return ListTile(
      tileColor: _entryColor(entry.background),
      textColor: _entryColor(entry.foreground),
      leading: DatabaseItemIcon(
        item: entry,
        database: database,
        expired: expired,
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
      onTap: onTap ?? () => context.push(AppRoutes.entry(itemIdOf(entry))),
      onLongPress: onLongPress,
      selected: selected,
    );
  }
}
