/// One row in the wardrobe list.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../widgets/confidence_chip.dart';
import '../../../widgets/item_thumbnail.dart';

class ItemTile extends StatelessWidget {
  const ItemTile({required this.item, this.onTap, super.key});

  final WardrobeItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      leading: ItemThumbnail(item: item),
      title: Text(
        item.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [item.type.value.label, item.composition.value.label].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Only the things that need doing get a badge. A row decorated with
          // every fact the app knows is a row nobody reads.
          if (item.needsCareTagScan)
            Tooltip(
              message: 'Scan the care label',
              child: Icon(
                Icons.document_scanner_outlined,
                size: 20,
                color: theme.colorScheme.tertiary,
              ),
            ),
          if (item.isFavorite)
            Icon(Icons.star, size: 20, color: theme.colorScheme.tertiary),
          const SizedBox(width: 4),
          ConfidenceChip.of(item.type, compact: true),
        ],
      ),
    );
  }
}
