import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../database/item_edits.dart';
import '../storage/file_storage.dart';
import 'entry_icon.dart';

class IconPickerDialog extends ConsumerWidget {
  const IconPickerDialog({super.key, required this.selected, this.database});
  final KdbxIcon selected;
  final KdbxDatabase? database;

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      final file = await ref.read(filePickerServiceProvider).pick();
      if (file == null) return;
      unawaited(ref.read(fileStorageProvider).release(file.ref));
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty || bytes.length > 1024 * 1024) {
        throw const FormatException();
      }
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 96,
        targetHeight: 96,
      );
      final frame = await codec.getNextFrame();
      final encoded = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      frame.image.dispose();
      codec.dispose();
      if (encoded == null) throw const FormatException();
      if (!context.mounted) return;
      Navigator.pop(
        context,
        IconChoice(
          icon: selected,
          customId: KdbxUuid.random(
            prohibited: database?.meta.customIcons.keys.toSet() ?? {},
          ),
          data: encoded.buffer.asUint8List(
            encoded.offsetInBytes,
            encoded.lengthInBytes,
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.iconImportError)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.entryEditChooseIcon),
      content: SizedBox(
        width: double.maxFinite,
        child: GridView.extent(
          shrinkWrap: true,
          maxCrossAxisExtent: AppSpacing.l * 2,
          children: [
            for (final entry
                in (database?.meta.customIcons.entries ??
                    <MapEntry<KdbxUuid, KdbxCustomIcon>>[]))
              IconButton(
                tooltip: l10n.iconCustom,
                icon: CustomIconPreview(bytes: entry.value.data),
                onPressed: () => Navigator.pop(
                  context,
                  IconChoice(icon: selected, customId: entry.key),
                ),
              ),
            for (final icon in KdbxIcon.values)
              IconButton(
                tooltip: l10n.entryEditIconNumber(icon.index),
                isSelected: icon == selected,
                color: icon == selected ? scheme.primary : null,
                icon: Icon(kdbxIconData(icon)),
                onPressed: () => Navigator.pop(context, IconChoice(icon: icon)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _import(context, ref),
          child: Text(l10n.iconImport),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

class CustomIconPreview extends StatefulWidget {
  const CustomIconPreview({super.key, required this.bytes});
  final List<int> bytes;
  @override
  State<CustomIconPreview> createState() => _CustomIconPreviewState();
}

class _CustomIconPreviewState extends State<CustomIconPreview> {
  ui.Image? image;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CustomIconPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      generation++;
      image?.dispose();
      image = null;
      _load();
    }
  }

  Future<void> _load() async {
    final currentGeneration = generation;
    if (widget.bytes.isEmpty || widget.bytes.length > 1024 * 1024) return;
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        Uint8List.fromList(widget.bytes),
        targetWidth: 96,
        targetHeight: 96,
      );
      final frame = await codec.getNextFrame();
      if (!mounted || currentGeneration != generation) {
        frame.image.dispose();
        return;
      }
      setState(() => image = frame.image);
    } catch (_) {
    } finally {
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    generation++;
    image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => image == null
      ? const Icon(Icons.image_not_supported_outlined)
      : RawImage(image: image, width: 24, height: 24);
}
