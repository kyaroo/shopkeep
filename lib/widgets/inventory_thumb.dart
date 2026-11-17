import 'dart:typed_data';

import 'package:flutter/material.dart';

/// The inventory row's image slot.
///
/// Always 44x44, photo or not. The slot must never size itself to its content:
/// `ListTile` reserves the leading widget's intrinsic width, so a wider
/// no-photo widget shifts the whole text column right and truncates the
/// product name. This replaces a stock pill that measured 87px in French
/// against the photo's 44px — the name's column collapsed from 311px to 53px.
///
/// The stock status itself lives on the subtitle line, where it costs the name
/// nothing.
class InventoryThumb extends StatelessWidget {
  const InventoryThumb({super.key, this.photo});

  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(6));

    if (photo == null) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: radius,
        ),
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Image.memory(
        photo!,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        cacheWidth: 132,
      ),
    );
  }
}
