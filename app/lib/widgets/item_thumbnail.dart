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

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import '../data/images/image_store.dart';

/// How many photographs' bytes are kept after nothing is showing them.
///
/// Enough for scrolling a row away and back, or popping to the previous page,
/// not to read the file again; bounded so that a wardrobe of two hundred
/// garments is not held in memory for the life of the process, which is what a
/// provider that never disposes amounts to. A count rather than a time: it
/// needs no timer, so it behaves the same under test and costs nothing idle.
final imageRetainCountProvider = Provider<int>((ref) => 24);

/// The most recently loaded photographs, oldest first.
final _recentImagesProvider = Provider<Queue<KeepAliveLink>>(
  (ref) => Queue<KeepAliveLink>(),
);

/// Bytes for one stored image, or null when it cannot be read.
///
/// Only the stores with no files to point at come this way (the browser and
/// the demo). On a phone the thumbnail hands the file to Flutter's image
/// cache instead, which decodes it at the size it is drawn at and evicts it
/// under pressure, so the full-size bytes never enter Dart at all.
///
/// Released once nothing is showing it, unless it is among the last
/// [imageRetainCountProvider] loaded.
final imageBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, uri) {
      final recent = ref.read(_recentImagesProvider);
      final link = ref.keepAlive();
      recent.add(link);
      // Closing the link of a photograph still on screen is harmless: its
      // listener keeps it alive, and it is released when that goes.
      while (recent.length > ref.read(imageRetainCountProvider)) {
        recent.removeFirst().close();
      }
      ref.onDispose(() => recent.remove(link));
      return ref.watch(imageStoreProvider).read(uri);
    });

/// Forgets decoded pixels for images that were rewritten under the same URI.
///
/// A re-cut cutout is written to the name it had before, on purpose, so the
/// URI alone cannot tell a cache that the picture changed. Providers are
/// invalidated by key; Flutter's image cache is keyed by path, so it is
/// cleared. Rare enough (a user pressed Save) that precision is not worth it.
void forgetDecodedImages() {
  final PaintingBinding binding;
  try {
    binding = PaintingBinding.instance;
  } on Error {
    // No engine bindings: a controller under a plain unit test, with nothing
    // drawn and so nothing cached.
    return;
  }
  binding.imageCache
    ..clear()
    ..clearLiveImages();
}

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

    final ImageProvider source;
    final store = ref.watch(imageStoreProvider);
    final path = switch (store) {
      FileBackedImageStore() => (store as FileBackedImageStore).pathFor(uri),
      _ => null,
    };
    if (path != null) {
      // Straight from disk: no bytes held by a provider, and a missing file
      // surfaces as an error below rather than as a null.
      source = FileImage(File(path));
    } else {
      final bytes = ref.watch(imageBytesProvider(uri)).valueOrNull;
      if (bytes == null) {
        // Covers both "still loading" and "gone". Showing the swatch in the
        // meantime avoids a row that pops from a grey box to a picture, and
        // avoids a spinner per row on a wardrobe of two hundred items.
        return _Swatch(palette: item.colors.value, size: size);
      }
      source = MemoryImage(bytes);
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final extent = _decodeExtent(context, constraints);
              return Image(
                // Decoded at the size it is drawn at, not the size it was
                // stored at. A scan is capped at 1600px, which is right for a
                // model reading a care label and about thirty times the
                // pixels a 56dp row needs — and an undecoded hint is the
                // difference between ~10MB of RGBA per row and a few hundred
                // kilobytes. Flutter's image cache is 100MB, so a wardrobe of
                // any size would otherwise evict and re-decode while the user
                // scrolls.
                //
                // `fit`, not the default `exact`: giving both dimensions to
                // `exact` decodes to precisely extent x extent whatever the
                // picture's shape, so a portrait photograph came out squashed
                // into a square before `BoxFit.contain` ever saw it. `fit`
                // scales the longer side to the extent and keeps the ratio.
                image: extent == null
                    ? source
                    : ResizeImage(
                        source,
                        width: extent,
                        height: extent,
                        policy: ResizeImagePolicy.fit,
                      ),
                // `contain`, never `cover`: a cutout has transparent margins
                // and the shape *is* the information. Cropping to fill a
                // square would cut the sleeves off the thing being recognised.
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                // A file is decoded after the first build, so until a frame
                // arrives the swatch stands in, as it does while bytes load.
                frameBuilder: (context, child, frame, sync) =>
                    sync || frame != null
                    ? child
                    : Center(
                        child: _Swatch(palette: item.colors.value, size: size),
                      ),
                errorBuilder: (_, _, _) =>
                    _Swatch(palette: item.colors.value, size: size),
              );
            },
          ),
        ),
      ),
    );
  }

  /// The pixel extent to decode to for the box this is being drawn in.
  ///
  /// Multiplied by the device pixel ratio because the box is in logical pixels
  /// and decoding to those would be visibly soft on any phone — every one of
  /// which has a ratio of 2 or 3.
  ///
  /// Returns null when the box is unbounded, which asks for the image at its
  /// stored size: guessing an extent for a box of unknown size risks decoding
  /// something smaller than it is about to be drawn.
  static int? _decodeExtent(BuildContext context, BoxConstraints constraints) {
    final extent = constraints.biggest.shortestSide;
    if (!extent.isFinite || extent <= 0) return null;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return (extent * ratio).ceil();
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
    //
    // Nor is the dark one the same size on true black. The lift is a fraction
    // of onSurface laid over whatever is behind the tile, so it climbs only as
    // far as there is ground to climb from. Over dark's blue-grey, 30% lands on
    // (80, 81, 87), a step above a charcoal garment's (60, 63, 68); over black
    // the same 30% is (68, 68, 70), square on top of it, and the jumper is gone
    // again. Garments do not get darker with the theme, so the lift has to land
    // in the same place, which over black takes 36%.
    final darkLift = scheme.hasTrueBlackGround ? 0.36 : 0.30;
    final lift = scheme.onSurface.withValues(
      alpha: isDarkTheme ? darkLift : 0.10,
    );

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
