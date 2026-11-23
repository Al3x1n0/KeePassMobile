import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../totp/totp.dart';

/// Orologio usato per i codici TOTP (sovrascrivibile nei test).
final totpClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Codice TOTP della voce con conto alla rovescia (EntryActivity di
/// Keepass2Android).
class TotpTile extends ConsumerStatefulWidget {
  const TotpTile({
    super.key,
    required this.config,
    required this.onCopy,
    this.masked = true,
  });

  final TotpConfig config;
  final ValueChanged<String> onCopy;

  /// Codice nascosto all'apertura (masktotp di Keepass2Android).
  final bool masked;

  @override
  ConsumerState<TotpTile> createState() => _TotpTileState();
}

class _TotpTileState extends ConsumerState<TotpTile> {
  static const _mask = '••••••';

  Timer? _timer;
  late bool _revealed = !widget.masked;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = ref.watch(totpClockProvider)();
    final code = widget.config.codeAt(now);
    final remaining = widget.config.secondsRemaining(now);
    final masked = !_revealed;

    return Semantics(
      onTapHint: l10n.entryCopy(l10n.entryTotp),
      child: ListTile(
        onTap: () =>
            widget.onCopy(widget.config.codeAt(ref.read(totpClockProvider)())),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
        title: Text(l10n.entryTotp, style: theme.textTheme.labelMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              excludeSemantics: masked,
              label: masked ? l10n.entryHiddenValue : null,
              child: Text(
                masked ? _mask : code,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                // I secondi sono già letti dal testo accanto.
                Expanded(
                  child: ExcludeSemantics(
                    child: LinearProgressIndicator(
                      value: remaining / widget.config.period,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Text(
                  l10n.entryTotpRemaining(remaining),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          tooltip: masked ? l10n.entryShow : l10n.entryHide,
          icon: Icon(masked ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _revealed = !_revealed),
        ),
      ),
    );
  }
}
