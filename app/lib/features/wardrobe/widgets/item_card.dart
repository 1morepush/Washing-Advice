/// One garment in the grid.
///
/// The grid exists because of cutouts and would not be worth having without
/// them. A grid of photographs taken on assorted beds is a patchwork of
/// backgrounds with clothes somewhere inside; a grid of garments on
/// transparency is a rail you can scan the way you would scan an actual
/// wardrobe — by shape and colour, before reading a single word.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../widgets/item_thumbnail.dart';

class ItemCard extends StatelessWidget {
  const ItemCard({
    required this.item,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    super.key,
  });

  final WardrobeItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether this garment is one of the ones currently picked out.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      // Tinted rather than ticked. A cell is mostly picture, and a badge in the
      // corner competes with the two that are already there for care labels and
      // favourites.
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Center(
                      child: ItemThumbnail(item: item, size: double.infinity),
                    ),
                  ),
                  // Overlaid rather than given their own row: the picture is
                  // what the grid is for, and a badge strip under every tile
                  // would take that space from all of them to serve a few.
                  Positioned(
                    top: 4,
                    right: 4,
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
                            color: theme.colorScheme.tertiary,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
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
      ),
    );
  }
}
