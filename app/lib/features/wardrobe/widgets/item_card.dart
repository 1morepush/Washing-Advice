/// One garment in the grid.
///
/// The grid exists because of cutouts and would not be worth having without
/// them. A grid of photographs taken on assorted beds is a patchwork of
/// backgrounds with clothes somewhere inside; a grid of garments on
/// transparency is a rail you can scan the way you would scan an actual
/// wardrobe — by shape and colour, before reading a single word.
///
/// Rinse draws it as a soft square (the "well" the garment sits on) with the
/// name and type underneath on the page itself, not as a card: a card round
/// every tile would put a shadow behind two hundred things.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../core/theme.dart';
import '../../../widgets/item_thumbnail.dart';
import '../../../widgets/rinse_kit.dart';

class ItemCard extends StatelessWidget {
  const ItemCard({
    required this.item,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.copies = 1,
    super.key,
  });

  final WardrobeItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether this garment is one of the ones currently picked out.
  final bool selected;

  /// How many identical garments this cell stands for.
  final int copies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: context.rinse.tileBorderRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            // The ring is drawn over the tile rather than a badge laid on it:
            // a cell is mostly picture, and a tick competes with the two
            // badges that are already there for care labels and favourites.
            child: GarmentWell(
              selected: selected,
              color: Colors.transparent,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ItemThumbnail(item: item, size: double.infinity),
                  // Overlaid rather than given their own row: the picture is
                  // what the grid is for, and a badge strip under every tile
                  // would take that space from all of them to serve a few.
                  // Top left, because the care and favourite badges already
                  // own the right corner and a count that moved depending on
                  // what else was true would be hard to find twice.
                  if (copies > 1)
                    Positioned(top: 6, left: 6, child: CountBadge('×$copies')),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Row(
                      children: [
                        if (item.needsCareTagScan)
                          Icon(
                            Icons.document_scanner_outlined,
                            size: 18,
                            color: theme.colorScheme.tertiary,
                          ),
                        if (item.isFavorite)
                          Icon(
                            Icons.star,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  // The type, not the full composition. A grid cell has room
                  // for one line, and "Sweater" identifies the thing while
                  // "78% Cotton, 20% Polyester, 2% Elastane" truncates to
                  // "78% Cotton, 20% Poly…" and identifies nothing.
                  item.type.value.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
