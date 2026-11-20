import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:kpasslib/kpasslib.dart';

import 'entry_icon.dart';

/// Icona del database, decodificata solo in memoria e senza cache globale.
class DatabaseItemIcon extends StatefulWidget {
  const DatabaseItemIcon({
    super.key,
    required this.item,
    required this.database,
    this.expired = false,
    this.recycleBin = false,
  });

  final KdbxItem item;
  final KdbxDatabase? database;
  final bool expired;
  final bool recycleBin;

  @override
  State<DatabaseItemIcon> createState() => _DatabaseItemIconState();
}

class _DatabaseItemIconState extends State<DatabaseItemIcon> {
  static const _maxBytes = 1024 * 1024;
  ui.Image? _image;
  List<int>? _bytes;
  int _generation = 0;

  List<int>? get _iconBytes {
    if (widget.expired || widget.recycleBin) return null;
    final id = widget.item.customIcon;
    if (id == null) return null;
    final bytes = widget.database?.meta.customIcons[id]?.data;
    return bytes == null || bytes.isEmpty || bytes.length > _maxBytes
        ? null
        : bytes;
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant DatabaseItemIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_bytes, _iconBytes)) _reload();
  }

  void _reload() {
    final generation = ++_generation;
    _image?.dispose();
    _image = null;
    final bytes = _bytes = _iconBytes;
    if (bytes != null) _decode(bytes, generation);
  }

  Future<void> _decode(List<int> bytes, int generation) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
        targetWidth: 96,
        targetHeight: 96,
      );
      final frame = await codec.getNextFrame();
      if (!mounted || generation != _generation) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      // Dati non validi: resta visibile l'icona standard.
    } finally {
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    _bytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image != null) {
      return RawImage(image: image, width: 24, height: 24, fit: BoxFit.contain);
    }
    final icon = widget.recycleBin
        ? Icons.delete_outline
        : kdbxIconData(widget.expired ? KdbxIcon.expired : widget.item.icon);
    return Icon(icon);
  }
}
