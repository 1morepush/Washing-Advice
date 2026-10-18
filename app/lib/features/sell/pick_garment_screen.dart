/// Choosing a garment from the wardrobe to sell.
///
/// The garments a person still owns, least worn first: those are what people
/// sell, and a list in the wardrobe's own order would bury them among the
/// favourites. Each row says how often the garment has been worn, since that is
/// why it is where it is.
///
/// Picking one starts its listing from here, behind a dialog, and leaves this
/// screen once the editor is ready, so Back from the editor is Sell and not
/// this list again.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../widgets/back_navigation.dart';
import '../../widgets/rinse_kit.dart';
import '../../widgets/status_message.dart';
import 'list/listing_clock.dart';
import 'list/new_listing_sheet.dart' show newFromPhotosRoute;
import 'start/garment_choice_tile.dart';
import 'listing_controller.dart';
import 'start/least_worn.dart';
import 'start/start_listing.dart';

class PickGarmentScreen extends ConsumerWidget {
  const PickGarmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = ref.watch(ownedItemsProvider);
    final now = ref.watch(listingClockProvider)();

    return Scaffold(
      appBar: AppBar(
        leading: backLeading(context, '/sell'),
        title: const AppBarTitle('Choose a garment'),
      ),
      body: owned.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StatusMessage.failure(
          title: 'Could not load your wardrobe',
          error: error,
        ),
        data: (items) => items.isEmpty
            ? const _NothingToChoose()
            : _Garments(items: leastWornFirst(items), now: now),
      ),
    );
  }
}

class _Garments extends ConsumerWidget {
  const _Garments({required this.items, required this.now});

  final List<WardrobeItem> items;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      // The explanation is the first row, so it scrolls away with the list and
      // does not hold a share of a small screen for good.
      itemCount: items.length + 1,
      separatorBuilder: (_, index) => index == 0
          ? const SizedBox.shrink()
          : Divider(height: 1, indent: 88, color: context.rinse.lineSoft),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Worn least first: the ones you are likeliest to sell. Tap one '
              'to start its listing.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        final item = items[index - 1];
        return GarmentChoiceTile(
          key: ValueKey(item.id.value),
          item: item,
          now: now,
          // Leaves the picker behind once the listing is ready: it has done
          // its job, and a listing's Back should land on Sell.
          onTap: () => unawaited(
            startListingForGarment(
              context,
              ref.read(listingControllerProvider),
              item.id,
              fromTask: true,
            ),
          ),
        );
      },
    );
  }
}

/// A wardrobe with nothing in it has nothing to choose from, and says what to
/// do instead.
class _NothingToChoose extends StatelessWidget {
  const _NothingToChoose();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconBadge(Icons.checkroom_outlined),
            const SizedBox(height: 16),
            Text(
              'Nothing in your wardrobe yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Add garments to your wardrobe to sell them from here, or '
              'photograph something to sell now.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => leaveTaskFor(context, newFromPhotosRoute),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Photograph something to sell'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
