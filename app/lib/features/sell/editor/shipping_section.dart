/// What the parcel will weigh, and how Depop gets it to a buyer.
///
/// The weight is an estimate and is shown as one. A seller buys the label
/// before the parcel is on a scale, and guessing wrong is not a refund but
/// postage due: the carrier weighs it, charges the difference, and the buyer
/// is left holding a parcel with a bill attached. So the line says "about",
/// gives the band the label falls in, and the sentence under it says what to
/// do about the guess.
///
/// The facts under that are Depop's, from the seller's briefing, and nothing in
/// the app computes them: the label is Depop's, a parcel is to go within about
/// five days, and the money arrives about two business days after the buyer
/// confirms it came.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../widgets/notice.dart';
import 'editor_text.dart';
import 'fields.dart';

class ShippingSection extends StatelessWidget {
  const ShippingSection({required this.listing, super.key});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final estimate = estimateShipping(listing.itemType);

    Widget fact(IconData icon, String text) => NoteRow(
      icon: icon,
      text: text,
      color: muted,
      iconSize: 18,
      gap: 10,
      bottomPadding: 10,
    );

    return EditorSection(
      title: 'Shipping',
      children: [
        Text(
          'About ${weightPhrase(estimate.ounces)} packed '
          '(${estimate.band} label)',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const QuietText(
          'Weigh it packed to be sure. A label for the wrong weight means '
          'postage due.',
        ),
        const SizedBox(height: 16),
        fact(Icons.local_shipping_outlined, "Depop's prepaid USPS label."),
        fact(Icons.schedule_outlined, 'Ship within about 5 days.'),
        fact(
          Icons.payments_outlined,
          "You're paid about 2 business days after delivery is confirmed.",
        ),
      ],
    );
  }
}
