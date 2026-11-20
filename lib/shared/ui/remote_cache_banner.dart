import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../database/database_errors.dart';
import '../database/database_session.dart';

/// Avviso persistente: la copia locale non equivale a un upload completato.
class RemoteCacheBanner extends ConsumerWidget {
  const RemoteCacheBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      databaseSessionProvider.select((s) => s?.cacheStatus),
    );
    if (status == null ||
        (!status.offline &&
            !status.pending &&
            status.available &&
            status.error == null &&
            !status.synchronizing)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final message = status.synchronizing
        ? l10n.syncInProgress
        : status.pending
        ? l10n.cachePending
        : status.offline
        ? l10n.cacheOffline
        : !status.available
        ? l10n.cacheUnavailable
        : l10n.cacheSyncFailed;
    final reason = status.error == null
        ? null
        : describeSaveError(l10n, status.error!);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_off_outlined),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(
                reason == null || reason == message
                    ? message
                    : '$message\n$reason',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
