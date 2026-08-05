/// The picture shown for an item in a list.
///
/// Prefers the background-removed cutout, which is the entire reason cutouts
/// exist: a column of garments floating on the page can be scanned at a
/// glance, whereas a column of photographs taken on assorted beds and carpets
/// cannot — every row shares a busy background and the eye has to hunt for the
/// clothing in each one.
///
/// Falls back to the colour swatch, which needs no files at all and is drawn
/// from the CIELAB palette the app actually stored. That fallback is not a
/// consolation prize: it is what the wardrobe looked like before this feature,
/// and it still works when the image is missing, the cutout failed, or the
/// user restored a backup that carried the database but not the pictures.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../core/providers.dart';

/// Bytes for one stored image, or null when it cannot be read.
final imageBytesProvider = FutureProvider.family<Uint8List?, String>(
  (ref, uri) => ref.watch(imageStoreProvider).read(uri),
);

class ItemThumbnail extends ConsumerWidget {
  const ItemThumbnail({required this.item, this.size = 56, super.key});

  final WardrobeItem item;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uri = item.photos.displayImageUri;
    if (uri == null) return _Swatch(palette: item.colors.value, size: size);

    final bytes = ref.watch(imageBytesProvider(uri)).valueOrNull;
    if (bytes == null) {
      // Covers both "still loading" and "gone". Showing the swatch in the
      // meantime avoids a row that pops from a grey box to a picture, and
      // avoids a spinner per row on a wardrobe of two hundred items.
      return _Swatch(palette: item.colors.value, size: size);
    }

    return SizedBox(
      width: size,
      height: size,
      child: Image.memory(
        bytes,
        // `contain`, never `cover`: a cutout has transparent margins and the
        // shape *is* the information. Cropping to fill a square would cut the
        // sleeves off the thing the user is trying to recognise.
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) =>
            _Swatch(palette: item.colors.value, size: size),
      ),
    );
  }
}

/// The item's colours, as the app stored them.
///
/// Drawn from the CIELAB palette rather than from a photo: it works before any
/// image has loaded, and it shows what the app *believes* the colour to be,
/// which is what decides which pile the garment lands in. A swatch that
/// disagrees with the photo beside it is a bug worth seeing.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette, required this.size});

  final ColorPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // At most two, largest coverage first. A five-way gradient on a 44-pixel
    // circle communicates nothing.
    final shown = [
      for (final color in palette.colors.take(2)) Color(0xFF000000 | color.rgb),
    ];

    // Three cases, and they must stay separate: a gradient needs at least two
    // colours and asserts on one, which crashed every single-colour garment —
    // that is, nearly all of them.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant),
        color: switch (shown.length) {
          0 => scheme.surfaceContainerHighest,
          1 => shown.first,
          _ => null,
        },
        gradient: shown.length < 2
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: shown,
                // A hard split rather than a blend: the two colours are
                // separate facts about the garment, and blending them invents
                // a third that is on none of it.
                stops: const [0.5, 0.5],
              ),
      ),
      child: shown.isEmpty
          ? Icon(
              Icons.checkroom,
              size: size * 0.45,
              color: scheme.onSurfaceVariant,
            )
          : null,
    );
  }
}
