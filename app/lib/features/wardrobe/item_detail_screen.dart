/// One item, and everything the app believes about it.
///
/// The organising idea is that a care instruction is worth nothing unless the
/// user can see where it came from. "Wash at 30°" is an order; "wash at 30°,
/// from the care label" is a fact they can check, and "wash at 30°, assumed"
/// is an invitation to scan the label. Every claim on this screen therefore
/// carries its provenance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/back_navigation.dart';
import '../../widgets/status_message.dart';
import 'condition_sheet.dart';
import 'item_details.dart';
import 'report_wear_sheet.dart';

/// How tall the bar has to be to hold a three-line name at the current type
/// size.
///
/// Derived rather than fixed. `toolbarHeight` is in logical pixels and does
/// not follow the text scale, so a height that fits three lines by default
/// clips the last one as soon as somebody turns their type up — and the larger
/// the type, the more likely the name needed three lines in the first place.
double _titleHeight(BuildContext context) {
  final style = Theme.of(context).textTheme.titleMedium;
  final scaled = MediaQuery.textScalerOf(context)
      .scale(style?.fontSize ?? 16.0);
  // Three lines at the style's own line spacing, plus the padding the bar
  // keeps above and below its title.
  return (scaled * (style?.height ?? 1.4) * 3) + 24;
}

class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({required this.id, super.key});

  final ItemId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemProvider(id));

    return Scaffold(
      appBar: AppBar(
        leading: backLeading(context, '/'),
        // The name gets the room it needs. A garment's name is the one thing
        // on this screen that says *which* garment it is, and a single line
        // cut "Black koi graphic tee" down to "Black koi graphic t…" — losing
        // precisely the word that tells it from every other black tee. The
        // distinguishing word is as often at the end as the start, so
        // truncation is not a graceful degradation here.
        //
        // Three lines rather than two because two is not enough at a larger
        // text size, which is exactly when someone needs the name legible.
        // The bar grows with the type for the same reason: a fixed height
        // would clip the third line the moment it was used.
        toolbarHeight: _titleHeight(context),
        title: Text(
          item.valueOrNull?.displayName ?? 'Item',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          // A step down from the default, so a wrapped name reads as a title
          // rather than as a paragraph in the chrome.
          style: Theme.of(context).textTheme.titleMedium,
        ),
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
            foregroundColor: Theme.of(dialogContext)
                .colorScheme
                .onErrorContainer,
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
