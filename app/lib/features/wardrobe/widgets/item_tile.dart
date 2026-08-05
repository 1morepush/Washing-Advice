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
    final shown = [
      for (final color in palette.colors.take(2)) Color(0xFF000000 | color.rgb),
    ];

    // Three cases, and they must stay separate: a gradient needs at least two
    // colours and asserts on one, which crashed every single-colour garment —
    // that is, nearly all of them.
    return Container(
      width: 44,
      height: 44,
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
          ? Icon(Icons.checkroom, size: 20, color: scheme.onSurfaceVariant)
          : null,
    );
  }
}
