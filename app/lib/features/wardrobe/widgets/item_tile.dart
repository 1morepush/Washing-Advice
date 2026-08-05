/// One row in the wardrobe list.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../widgets/confidence_chip.dart';

class ItemTile extends StatelessWidget {
  const ItemTile({required this.item, this.onTap, super.key});

  final WardrobeItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      leading: _Swatch(palette: item.colors.value),
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

/// The item's colours, as the app actually stored them.
///
/// Drawn from the CIELAB palette rather than from a photo thumbnail: it works
/// before any image has loaded, and it shows what the app *believes* the colour
/// to be, which is the thing that decides which pile the garment lands in. A
/// swatch that disagrees with the photo is a bug worth seeing.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette});

  final ColorPalette palette;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // At most two, largest coverage first. A five-way gradient on a 44-pixel
    // circle communicates nothing.
    final shown = palette.colors.take(2).toList();

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant),
        color: shown.isEmpty ? scheme.surfaceContainerHighest : null,
        gradient: shown.isEmpty
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  for (final color in shown) Color(0xFF000000 | color.rgb),
                ],
                stops: shown.length == 1 ? null : const [0.5, 0.5],
              ),
      ),
      child: shown.isEmpty
          ? Icon(Icons.checkroom, size: 20, color: scheme.onSurfaceVariant)
          : null,
    );
  }
}
