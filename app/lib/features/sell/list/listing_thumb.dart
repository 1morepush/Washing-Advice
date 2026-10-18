/// The picture a listing is known by: its cover, or the silhouette of what it is.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../core/theme.dart';
import '../../../widgets/garment_glyph.dart';
import '../../../widgets/rinse_kit.dart';
import '../../../widgets/stored_image.dart';

class ListingThumb extends StatelessWidget {
  const ListingThumb({required this.listing, this.size = 72, super.key});

  final Listing listing;
  final double size;

  /// The photograph that stands for [listing]: the one marked as its cover,
  /// else the first it has.
  ///
  /// A listing made from a garment starts with the garment's own photographs
  /// in the order the garment keeps them, and the one it shows is not always
  /// the front. The cover is what a buyer will see first, so it is what the
  /// seller should see here.
  static ListingPhoto? coverOf(Listing listing) {
    for (final photo in listing.photos) {
      if (photo.shot == ListingShot.cover) return photo;
    }
    return listing.photos.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final cover = coverOf(listing);
    final silhouette = _Silhouette(type: listing.itemType);

    // Clipped to the tile's corner: a photograph, unlike a cutout, fills its
    // box, and would otherwise square off the rounded well it sits on.
    return GarmentWell(
      size: size,
      child: ClipRRect(
        borderRadius: context.rinse.tileBorderRadius,
        child: cover == null
            ? silhouette
            : StoredImage(uri: cover.uri, fallback: silhouette),
      ),
    );
  }
}

/// What a listing with no picture shows: a drawing of the kind of thing it is.
///
/// Neutral rather than coloured. A listing keeps Depop's colour names, which
/// are words, and the drawing is better plain than tinted to a guess.
class _Silhouette extends StatelessWidget {
  const _Silhouette({required this.type});

  final ItemType type;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: 0.74,
    heightFactor: 0.74,
    child: GarmentGlyph(
      kind: glyphKindFor(type),
      fill: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
      edge: context.rinse.garmentEdge,
    ),
  );
}
