import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/entry_tile.dart';
import 'favorites_view_model.dart';

class FavoritesView extends ConsumerWidget {
  const FavoritesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(favoriteEntriesProvider);
    if (entries == null) return const Scaffold();
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.favoritesTitle)),
      body: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: Text(l10n.favoritesEmpty, textAlign: TextAlign.center),
              ),
            )
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (_, index) => EntryTile(entry: entries[index]),
            ),
    );
  }
}
