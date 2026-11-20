import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/storage/file_storage.dart';
import '../file_select/recent_files.dart';
import '../unlock/relock.dart';
import '../unlock/unlock_view_model.dart';
import 'autofill_channel.dart';

/// Scelta del database per la compilazione automatica: solo i file recenti
/// (il selettore di file resta nell'app). Con un solo file, o dopo un blocco,
/// lo sblocco si apre subito.
class AutofillFileSelectView extends ConsumerStatefulWidget {
  const AutofillFileSelectView({super.key});

  @override
  ConsumerState<AutofillFileSelectView> createState() =>
      _AutofillFileSelectViewState();
}

class _AutofillFileSelectViewState
    extends ConsumerState<AutofillFileSelectView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openAutomatically());
  }

  void _openAutomatically() {
    if (!mounted) return;
    final relock = ref.read(relockProvider.notifier).take();
    if (relock != null) {
      _open(relock);
      return;
    }
    final recents = ref.read(recentFilesRepositoryProvider).load();
    if (recents.length == 1) _open(_argsOf(recents.single));
  }

  static UnlockArgs _argsOf(RecentFile recent) => UnlockArgs(
    database: PickedFile(ref: recent.database),
    keyFile: switch (recent.keyFile) {
      final key? => PickedFile(ref: key),
      null => null,
    },
  );

  void _open(UnlockArgs args) => context.push(AppRoutes.unlock, extra: args);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recents = ref.watch(recentFilesRepositoryProvider).load();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.autofillClose,
          icon: const Icon(Icons.close),
          onPressed: () => ref.read(autofillChannelProvider).cancel(),
        ),
        title: Text(l10n.autofillChooseDatabase),
      ),
      body: recents.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: Text(
                  l10n.autofillNoRecentFiles,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final recent in recents)
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(recent.database.name),
                    subtitle: switch (recent.keyFile) {
                      final key? => Text(key.name),
                      null => null,
                    },
                    onTap: () => _open(_argsOf(recent)),
                  ),
              ],
            ),
    );
  }
}
