/// A photograph from the image store, drawn.
///
/// The one way a stored photograph is loaded: a garment in a list, a picture on
/// a listing, anything that holds a URI the [ImageStore] issued. There used to
/// be exactly one such place, inside the garment thumbnail, and it has a good
/// deal of care in it — the file handed to Flutter and never read into Dart,
/// the bytes of a browser's photographs held only as long as they are wanted,
/// a missing picture quietly standing aside. A second widget that loaded images
/// its own way would have to get all of that right again, and would not stay
/// right when the first changed. So this is the first, taken out.
///
/// What it does not do is decide what a missing photograph looks like, or what
/// surrounds one: the caller says (`fallback`), because a garment's silhouette
/// is no use on a listing's photograph and the reverse.
library;

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
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
/// the demo). On a phone [StoredImage] hands the file to Flutter's image cache
/// instead, which decodes it at the size it is drawn at and evicts it under
/// pressure, so the full-size bytes never enter Dart at all.
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

/// The stored photograph at [uri], filling the space it is given.
///
/// [fallback] is shown in its place while the picture is on its way and when it
/// never arrives — the file is gone, the bytes are, or they are not an image.
/// Showing it for the first of those as well as the others is deliberate: a
/// list of two hundred photographs should not flash a spinner per row, and
/// "still loading" and "lost" look alike for as long as they need to. None of
/// them is an error on screen.
///
/// Decoded at the size it is drawn at and not the size it was stored at. A scan
/// is capped at 1600 pixels, which is right for a model reading a label and
/// about thirty times the pixels a 56 dp row needs; the difference is ten
/// megabytes of RGBA per row against a few hundred kilobytes, and Flutter's
/// image cache is a hundred, so a wardrobe of any size would otherwise evict
/// and re-decode while somebody scrolls.
class StoredImage extends ConsumerWidget {
  const StoredImage({
    required this.uri,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.semanticLabel,
    super.key,
  });

  /// The URI the image store issued.
  final String uri;

  /// Drawn instead of the photograph until it arrives, and if it does not.
  final Widget fallback;

  /// How the photograph fills its box.
  ///
  /// [BoxFit.cover] by default, the way a photograph on a listing is shown: the
  /// whole box, a little cropped. The garment thumbnail asks for
  /// [BoxFit.contain] instead, since a cutout's transparent margins and its
  /// shape *are* the information, and cropping to fill a square would cut the
  /// sleeves off the thing being recognised.
  final BoxFit fit;

  /// Where the photograph sits when [fit] crops it.
  final AlignmentGeometry alignment;

  final FilterQuality filterQuality;

  /// What a screen reader says for the photograph, when it is more than
  /// decoration.
  final String? semanticLabel;

  /// How much larger than its box a photograph is decoded when [fit] is
  /// [BoxFit.cover].
  ///
  /// Cropping to fill scales a picture until its *shorter* side meets the box,
  /// which leaves the longer one running past it. Decoding the longer side to
  /// the box's would therefore draw a portrait photograph a third larger than
  /// it was decoded, and soft. Half as much again covers the proportions
  /// cameras take (3:4 and 2:3, either way up) without drawing anything larger
  /// than it was decoded.
  static const _coverHeadroom = 1.5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ImageProvider source;
    final store = ref.watch(imageStoreProvider);
    final path = switch (store) {
      final FileBackedImageStore files => files.pathFor(uri),
      _ => null,
    };
    if (path != null) {
      // Straight from disk: no bytes held by a provider, and a missing file
      // surfaces as an error below rather than as a null.
      source = FileImage(File(path));
    } else {
      final bytes = ref.watch(imageBytesProvider(uri)).valueOrNull;
      // Covers both "still loading" and "gone". Showing the fallback in the
      // meantime avoids a row that pops from a grey box to a picture, and
      // avoids a spinner per row on a wardrobe of two hundred items.
      if (bytes == null) return fallback;
      source = MemoryImage(bytes);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = _decodeExtent(context, constraints);
        return Image(
          // `fit`, not the default `exact`: giving both dimensions to `exact`
          // decodes to precisely extent x extent whatever the picture's shape,
          // so a portrait photograph came out squashed into a square before
          // the box's own fit ever saw it. `fit` scales the longer side to the
          // extent and keeps the ratio.
          image: extent == null
              ? source
              : ResizeImage(
                  source,
                  width: extent,
                  height: extent,
                  policy: ResizeImagePolicy.fit,
                ),
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          semanticLabel: semanticLabel,
          // A file is decoded after the first build, so until a frame arrives
          // the fallback stands in, as it does while bytes load.
          frameBuilder: (context, child, frame, sync) =>
              sync || frame != null ? child : fallback,
          errorBuilder: (_, _, _) => fallback,
        );
      },
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
  int? _decodeExtent(BuildContext context, BoxConstraints constraints) {
    final box = constraints.biggest;
    final side = fit == BoxFit.cover && box.longestSide.isFinite
        ? box.longestSide * _coverHeadroom
        : box.shortestSide;
    if (!side.isFinite || side <= 0) return null;
    return (side * MediaQuery.devicePixelRatioOf(context)).ceil();
  }
}
