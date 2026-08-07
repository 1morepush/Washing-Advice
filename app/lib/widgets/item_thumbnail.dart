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
  const ItemThumbnail({
    required this.item,
    this.size = 56,
    this.backdrop = true,
    super.key,
  });

  final WardrobeItem item;
  final double size;

  /// Whether to tint the space behind a cutout.
  ///
  /// On by default because a cutout is transparent, and transparency takes the
  /// colour of whatever is behind it — so a white shirt on a pale card simply
  /// disappears, which is the exact failure the feature exists to prevent.
  final bool backdrop;

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

    // `size` may be `double.infinity` in a grid cell, where the parent decides
    // the box. `SizedBox` handles that by taking all the space offered.
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backdrop ? _backdropFor(context) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: EdgeInsets.all(size.isFinite ? size * 0.06 : 6),
          child: Image.memory(
            bytes,
            // `contain`, never `cover`: a cutout has transparent margins and
            // the shape *is* the information. Cropping to fill a square would
            // cut the sleeves off the thing being recognised.
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) =>
                _Swatch(palette: item.colors.value, size: size),
          ),
        ),
      ),
    );
  }

  /// A tone that the garment will stand out against.
  ///
  /// Chosen from the item's [ColorClass] — the same classification the sorter
  /// uses to decide which pile it goes in. It already answers exactly the
  /// question being asked here: is this thing pale enough to vanish against a
  /// light surface, or dark enough to vanish against a dark one?
  ///
  /// Deliberately subtle. This is a legibility aid, not a design feature, and
  /// a grid of strongly tinted tiles would compete with the garments in them.
  Color _backdropFor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    // The two lifts are not the same size, and that is not an oversight.
    // Darkening a near-white surface by 10% moves it a long way perceptually;
    // lightening a near-black one by 10% barely moves it at all, and lands
    // almost exactly on a charcoal garment — which is how the first version of
    // this made a charcoal jumper disappear in dark mode.
    final lift = scheme.onSurface.withValues(alpha: isDarkTheme ? 0.30 : 0.10);

    return switch (item.colorClass) {
      // Pale garments need something to sit against in a light theme; in a
      // dark one they already stand out.
      ColorClass.whites ||
      ColorClass.lights => isDarkTheme ? scheme.surfaceContainerHighest : lift,
      // The reverse case: charcoal and black against a dark surface.
      ColorClass.darks => isDarkTheme ? lift : scheme.surfaceContainerHighest,
      // Saturated colours read against anything neutral.
      ColorClass.brights => scheme.surfaceContainerHighest,
    };
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
    // A circle needs a real diameter; in a grid cell the size is unbounded, so
    // the swatch takes what it is given and stays square.
    final diameter = size.isFinite ? size : null;
    // At most two, largest coverage first. A five-way gradient on a 44-pixel
    // circle communicates nothing.
    final shown = [
      for (final color in palette.colors.take(2)) Color(0xFF000000 | color.rgb),
    ];

    // Three cases, and they must stay separate: a gradient needs at least two
    // colours and asserts on one, which crashed every single-colour garment —
    // that is, nearly all of them.
    return Container(
      width: diameter,
      height: diameter,
      constraints: diameter == null
          ? const BoxConstraints(maxWidth: 96, maxHeight: 96)
          : null,
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
              size: (diameter ?? 96) * 0.45,
              color: scheme.onSurfaceVariant,
            )
          : null,
    );
  }
}
