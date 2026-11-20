import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/item_edits.dart';
import '../../shared/ui/entry_icon.dart';
import '../../shared/ui/database_item_icon.dart';
import '../../shared/ui/icon_picker_dialog.dart';

/// Bozza locale; nessun salvataggio se la finestra viene annullata.
class GroupEditDialog extends StatefulWidget {
  const GroupEditDialog({super.key, this.initial, this.group, this.database});
  final GroupDraft? initial;
  final KdbxGroup? group;
  final KdbxDatabase? database;
  @override
  State<GroupEditDialog> createState() => _GroupEditDialogState();
}

class _GroupEditDialogState extends State<GroupEditDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late KdbxIcon _icon = widget.initial?.icon ?? KdbxIcon.folder;
  IconChoice? _iconChoice;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState?.validate() ?? false) {
      Navigator.of(context).pop(
        GroupDraft(
          name: _name.text.trim(),
          icon: _icon,
          iconChoice: _iconChoice,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.initial == null ? l10n.groupCreate : l10n.groupEdit),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                enableIMEPersonalizedLearning: false,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(AppLimits.fieldName),
                ],
                decoration: InputDecoration(labelText: l10n.groupName),
                validator: (value) => value == null || value.trim().isEmpty
                    ? l10n.groupNameRequired
                    : null,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: AppSpacing.m),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _iconChoice?.customId != null
                    ? CustomIconPreview(
                        bytes:
                            _iconChoice!.data ??
                            widget
                                .database!
                                .meta
                                .customIcons[_iconChoice!.customId]!
                                .data,
                      )
                    : _iconChoice == null &&
                          widget.group != null &&
                          _icon == widget.initial?.icon
                    ? DatabaseItemIcon(
                        item: widget.group!,
                        database: widget.database,
                      )
                    : Icon(kdbxIconData(_icon)),
                title: Text(l10n.entryIcon),
                trailing: TextButton(
                  child: Text(l10n.entryEditChooseIcon),
                  onPressed: () async {
                    final icon = await showDialog<IconChoice>(
                      context: context,
                      builder: (_) => IconPickerDialog(
                        selected: _icon,
                        database: widget.database,
                      ),
                    );
                    if (mounted && icon != null) {
                      setState(() {
                        _icon = icon.icon;
                        _iconChoice = icon;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.entryEditSave)),
      ],
    );
  }
}
