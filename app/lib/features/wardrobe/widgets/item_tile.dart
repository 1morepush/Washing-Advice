/// One row in the wardrobe list.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../widgets/confidence_chip.dart';
import '../../../widgets/item_thumbnail.dart';

class ItemTile extends StatelessWidget {
  const ItemTile({
    required this.item,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    super.key,
  });

  final WardrobeItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether this row is one of the garments currently picked out.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer,
      // The thumbnail is the row's identity, so the tick replaces it rather
      // than crowding in beside it — the same swap a mail app makes, and the
      // reason a selected row reads as selected at a glance.
      leading: selected
          ? CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              child: Icon(Icons.check, color: theme.colorScheme.onPrimary),
            )
          : ItemThumbnail(item: item),
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
