/// The garments in an outfit, laid out side by side.
///
/// Shared by the two tabs that show outfits nobody has saved yet — the ones
/// the core built and the ones a model proposed. They are different in kind and
/// deliberately kept on separate tabs, but a shirt is a shirt: drawing it two
/// slightly different ways would make the difference between the tabs look like
/// a difference between the clothes.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../widgets/item_thumbnail.dart';

class OutfitPieces extends StatelessWidget {
  const OutfitPieces({required this.items, super.key});

  final List<WardrobeItem> items;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final item in items)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _Piece(item: item),
          ),
        ),
    ],
  );
}

class _Piece extends StatelessWidget {
  const _Piece({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => context.go('/item/${item.id.value}'),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ItemThumbnail(item: item, size: double.infinity),
          ),
          const SizedBox(height: 8),
          Text(
            item.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            item.type.value.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
