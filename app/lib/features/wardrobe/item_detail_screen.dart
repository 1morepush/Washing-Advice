/// One item, and everything the app believes about it.
///
/// The organising idea is that a care instruction is worth nothing unless the
/// user can see where it came from. "Wash at 30°" is an order; "wash at 30°,
/// from the care label" is a fact they can check, and "wash at 30°, assumed"
/// is an invitation to scan the label. Every claim on this screen therefore
/// carries its provenance.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../widgets/back_navigation.dart';
import '../../widgets/item_thumbnail.dart';
import '../../widgets/status_message.dart';
import 'condition_sheet.dart';
import 'item_details.dart';
import 'report_wear_sheet.dart';

/// The bar's colour and the colour of its icons: the hero's tile, and the
/// page's ink or its ground, whichever has more contrast with that tile.
(Color, Color) _bar(BuildContext context, WardrobeItem? item) {
  final scheme = Theme.of(context).colorScheme;
  final tile = item == null
      ? context.rinse.well
      : ItemThumbnail.tileFor(context, item, floor: heroFloor);
  double ratio(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

  final ink = ratio(scheme.onSurface, tile) >= ratio(scheme.surface, tile)
      ? scheme.onSurface
      : scheme.surface;
  return (tile, ink);
}

class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({required this.id, super.key});

  final ItemId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemProvider(id));

    return Scaffold(
      appBar: AppBar(
        // The well the garment sits on, so the bar and the hero beneath it
        // read as one header rather than two bands with a seam between.
        backgroundColor: _bar(context, item.valueOrNull).$1,
        // Icons in whichever of the page's ink and ground reads better on the
        // tile: a lifted tile under a dark garment is light enough that the
        // usual pale icons would fade into it.
        foregroundColor: _bar(context, item.valueOrNull).$2,
        leading: backLeading(context, '/'),
        // The name is a heading in the body, under the picture, where it has
        // the whole width and as many lines as it needs (see [ItemDetails]);
        // repeating it here would only say it twice. While the item is still
        // loading the bar says what the page is.
        title: item.valueOrNull == null ? const Text('Item') : null,
        // Two icons, not five. Everything else moved into the body as a
        // labelled button, because five unlabelled glyphs squeezed the
        // garment's own name down to "Charco…" and left the most useful
        // actions unguessable — a scrubbing brush does not read as "ask about
        // a spill". The navigation menu this app used to have was
        // dropped for the same reason: unlabelled glyphs hide things.
        actions: [
          if (item.valueOrNull case final WardrobeItem value) ...[
            IconButton(
              onPressed: () => context.push('/item/${id.value}/edit'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
            ),
            // Behind an overflow menu rather than an icon beside the others:
            // this is the one action here with no undo, and it should never
            // be one accidental tap away from "Edit".
            PopupMenuButton<String>(
              onSelected: (choice) => switch (choice) {
                'wear' => showReportWearSheet(context, value),
                'check' => showConditionSheet(context, value),
                _ => _confirmAndDelete(context, ref, value),
              },
              itemBuilder: (menuContext) => [
                const PopupMenuItem(
                  value: 'wear',
                  child: Row(
                    children: [
                      Icon(Icons.report_problem_outlined),
                      SizedBox(width: 12),
                      Text('Report wear'),
                    ],
                  ),
                ),
                // Beside reporting it by hand rather than instead of it. The
                // form is exact and the camera is quick, and somebody who has
                // just found a hole should not have to photograph it to say so.
                const PopupMenuItem(
                  value: 'check',
                  child: Row(
                    children: [
                      Icon(Icons.photo_camera_outlined),
                      SizedBox(width: 12),
                      Text('Check for wear'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: Theme.of(menuContext).colorScheme.error,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Delete',
                        style: TextStyle(
                          color: Theme.of(menuContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: item.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StatusMessage.failure(
          title: 'Could not open this item',
          error: error,
        ),
        data: (value) => value == null
            ? const Center(child: Text('This item no longer exists.'))
            : ItemDetails(item: value),
      ),
    );
  }
}

/// Asks, then removes an item for good.
///
/// Separate from retiring — the lifecycle states on the edit screen (donated,
/// sold, discarded) that keep an item's history for statistics while taking it
/// out of the active wardrobe. This is for the record that should never have
/// existed at all: a duplicate, a scan of the wrong garment, a test entry.
///
/// "For good" from the user's side. Underneath, the row stays as a tombstone
/// — [LifecycleState.removed], hidden from every query — because a row that
/// is simply gone cannot be told to another device: the garment came back
/// from any phone that still had it, and from the server on a reinstall.
/// Kept as a state, the deletion is one more change that syncs.
Future<void> _confirmAndDelete(
  BuildContext context,
  WidgetRef ref,
  WardrobeItem item,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete this item?'),
      content: Text(
        '"${item.displayName}" and its photos will be gone for good. This '
        "can't be undone.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.errorContainer,
            foregroundColor: Theme.of(
              dialogContext,
            ).colorScheme.onErrorContainer,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;
  if (!context.mounted) return;

  // Every file this item ever produced: the originals and any cutout made
  // from them. Left behind, they are bytes nothing will ever read again —
  // and on a platform that already has a storage-quota problem, an orphaned
  // photo per deleted item is exactly the kind of thing that adds up.
  final images = ref.read(imageStoreProvider);
  for (final photo in item.photos.photos) {
    await images.delete(photo.uri);
    if (photo.cutoutUri case final String cutoutUri) {
      await images.delete(cutoutUri);
    }
  }

  // A garment that no longer exists cannot stay in a saved outfit — the same
  // cleanup retiring an item already relies on, including dropping an outfit
  // left with fewer than two members.
  await ref.read(outfitRepositoryProvider).removeItem(item.id);

  // Set directly rather than through `transitionTo`: deletion is not a
  // lifecycle transition anything should be able to refuse, and a duplicate
  // that had already been marked donated must still be deletable. The photo
  // paths go with the files — a row nothing will show has no use for them.
  final now = DateTime.now();
  await ref
      .read(wardrobeRepositoryProvider)
      .save(
        item.copyWith(
          lifecycle: LifecycleState.removed,
          photos: PhotoSet.empty,
          updatedAt: now,
        ),
      );
  await ref
      .read(eventLogProvider)
      .append(
        LifecycleChanged(
          id: EventId(ref.read(idGeneratorProvider).next()),
          itemId: item.id,
          occurredAt: now,
          recordedAt: now,
          to: LifecycleState.removed,
        ),
      );

  ref
    ..invalidate(itemProvider(item.id))
    ..invalidate(ownedItemsProvider)
    ..invalidate(ownedCountProvider)
    ..invalidate(coWearGraphProvider)
    ..invalidate(savedOutfitsProvider)
    ..invalidate(knownBrandsProvider);

  if (!context.mounted) return;
  context.go('/');
}
