import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../database/database_session.dart';
import '../database/linked_databases.dart';
import '../storage/file_storage.dart';
import 'selection_sheet.dart';

typedef _LinkedTarget = ({FileRef file, FileRef? keyFile});

/// Aggiunge un collegamento dal database corrente a un altro database aperto.
Future<void> addLinkedDatabase(BuildContext context, WidgetRef ref) async {
  final sessions = ref.read(databaseSessionProvider.notifier);
  final parent = ref.read(databaseSessionProvider)?.file;
  if (parent == null || sessions.isSaving) return;
  final generation = sessions.lockGeneration;
  final available = <_LinkedTarget>[
    for (final session in sessions.openSessions)
      if (session.file != parent)
        (file: session.file, keyFile: session.keyFile),
  ];
  if (available.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final navigator = Navigator.of(context);
  final password = TextEditingController();
  Route<_LinkedTarget>? pickerRoute;
  final route = DialogRoute<({_LinkedTarget child, String password})>(
    context: context,
    builder: (context) => _LinkForm(
      available: available,
      password: password,
      onPickerRoute: (route) => pickerRoute = route,
    ),
  );
  final listener = ref.listenManual<DatabaseSession?>(databaseSessionProvider, (
    _,
    next,
  ) {
    if (next != null) return;
    final picker = pickerRoute;
    if (picker != null && picker.isActive) navigator.removeRoute(picker);
    if (route.isActive) navigator.removeRoute(route);
  });
  try {
    final result = await navigator.push(route);
    if (result == null ||
        !context.mounted ||
        ref.read(databaseSessionProvider)?.file != parent ||
        sessions.lockGeneration != generation) {
      return;
    }
    try {
      await sessions.apply(
        addLinkedDatabaseEdit(
          parent: parent,
          child: result.child.file,
          keyFile: result.child.keyFile,
          password: result.password,
        ),
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
      }
    }
  } finally {
    listener.close();
    password.clear();
    password.dispose();
  }
}

class _LinkForm extends StatefulWidget {
  const _LinkForm({
    required this.available,
    required this.password,
    required this.onPickerRoute,
  });
  final List<_LinkedTarget> available;
  final TextEditingController password;
  final ValueChanged<Route<_LinkedTarget>> onPickerRoute;

  @override
  State<_LinkForm> createState() => _LinkFormState();
}

class _LinkFormState extends State<_LinkForm> {
  late _LinkedTarget child = widget.available.first;

  Future<void> _selectTarget() async {
    FocusScope.of(context).unfocus();
    final target = await showSelectionSheet<_LinkedTarget>(
      context: context,
      title: AppLocalizations.of(context).databasesTitle,
      selected: child,
      options: {
        for (final target in widget.available) target: target.file.name,
      },
      onRoute: widget.onPickerRoute,
    );
    if (mounted && target != null) setState(() => child = target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.linkedDatabaseAdd),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(child.file.name),
            trailing: const Icon(Icons.keyboard_arrow_down),
            onTap: _selectTarget,
          ),
          TextField(
            controller: widget.password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(AppLimits.masterPassword),
            ],
            decoration: InputDecoration(labelText: l10n.linkedDatabasePassword),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            child: child,
            password: widget.password.text,
          )),
          child: Text(l10n.entryEditSave),
        ),
      ],
    );
  }
}
