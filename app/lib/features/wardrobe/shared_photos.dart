/// Files that more than one garment points at.
///
/// Until photos of people existed, every stored image belonged to exactly one
/// garment, so deleting a garment could delete every file its photos named. A
/// photo of somebody wearing a jumper, jeans and a hat is stored once and
/// referenced by all three, so that rule would break two garments' "Worn"
/// photos the moment the third was deleted.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

/// The stored files [item] names that some other garment names too.
///
/// Includes garments in every state, removed ones included: a removed
/// garment's photos are cleared when it is deleted, but one that was only
/// retired still shows its pictures.
Future<Set<String>> urisHeldByOthers(
  WardrobeRepository repository,
  WardrobeItem item,
) async {
  final others = await repository.query(
    const WardrobeQuery(includeRemoved: true),
  );
  final mine = {
    for (final photo in item.photos.photos) ...[
      photo.uri,
      if (photo.cutoutUri case final String cutout) cutout,
    ],
  };

  return {
    for (final other in others)
      if (other.id != item.id)
        for (final photo in other.photos.photos) ...[
          if (mine.contains(photo.uri)) photo.uri,
          if (photo.cutoutUri case final String cutout)
            if (mine.contains(cutout)) cutout,
        ],
  };
}
