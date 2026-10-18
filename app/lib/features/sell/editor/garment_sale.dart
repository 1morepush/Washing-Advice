/// The last step of a sale: taking the garment out of the wardrobe.
///
/// A listing made from a garment in the wardrobe knows which one, and when it
/// sells, the garment is no longer owned. Marking it sold is the wardrobe's own
/// way of moving a garment on, so the move is in its history and the garment
/// stops turning up in the laundry and in outfits; it is never deleted, and its
/// wears and washes stay.
///
/// It is offered, never done for the person. A listing can be marked sold when
/// the money has not arrived, and it is the person who knows the garment has
/// left the house. What this shows follows the garment itself and not a record
/// of having tapped: opened a week later it still says the garment is sold, and
/// a garment given away in the meantime is not offered a sale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../core/providers.dart';
import '../../../widgets/notice.dart';
import 'edit_session.dart';
import 'fields.dart';

class GarmentSale extends ConsumerStatefulWidget {
  const GarmentSale({required this.listing, required this.session, super.key});

  final Listing listing;
  final ListingEditSession session;

  @override
  ConsumerState<GarmentSale> createState() => _GarmentSaleState();
}

class _GarmentSaleState extends ConsumerState<GarmentSale> {
  bool _marking = false;

  Future<void> _mark(WardrobeItem garment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmGarmentSold(garment: garment),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _marking = true);
    try {
      final sold = await widget.session.markGarmentSold();
      if (!sold && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                "The garment couldn't be marked as sold. It may have "
                'already left your wardrobe.',
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemId = widget.listing.itemId;
    if (itemId == null) return const SizedBox.shrink();

    // Nothing is said while the garment is being looked up, and nothing if it
    // cannot be: the sale of the listing does not wait on the wardrobe.
    final found = ref.watch(itemProvider(itemId));
    if (!found.hasValue) return const SizedBox.shrink();
    final garment = found.value;

    final theme = Theme.of(context);

    if (garment == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Notice(
          icon: Icons.info_outline,
          text:
              'The garment this was made from has been deleted, so there is '
              'nothing in your wardrobe to mark as sold.',
        ),
      );
    }

    if (garment.lifecycle == LifecycleState.sold) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Notice(
          icon: Icons.check_circle_outline,
          text: "Marked as sold — it's no longer in your wardrobe",
        ),
      );
    }

    if (!garment.lifecycle.isOwned) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Notice(
          icon: Icons.info_outline,
          text:
              '${garment.displayName} has already left your wardrobe '
              '(${garment.lifecycle.label.toLowerCase()}), so there is '
              'nothing to mark as sold.',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubHeading('Your wardrobe'),
          const SizedBox(height: 4),
          const QuietText(
            'Marking the garment as sold takes it out of your wardrobe, '
            'laundry and outfits. It stays in its history.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: _marking ? null : () => _mark(garment),
              child: Text(
                'Mark the ${garment.displayName} as sold',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks, and says what will happen, before a garment leaves the wardrobe.
class _ConfirmGarmentSold extends StatelessWidget {
  const _ConfirmGarmentSold({required this.garment});

  final WardrobeItem garment;

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text('Mark the ${garment.displayName} as sold?'),
    content: const Text(
      'It will leave your wardrobe, and stop showing up in your laundry and '
      'outfits. It stays in its history, with how often it was worn and '
      'washed.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Mark as sold'),
      ),
    ],
  );
}
