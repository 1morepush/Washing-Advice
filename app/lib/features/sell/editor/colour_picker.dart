/// The colours of a listing, picked from Depop's short list.
///
/// Depop's colour filter is a list of nineteen words and not a paint chart, so
/// a buyer filtering by grey finds a garment only if it was listed as grey —
/// not charcoal, not marl. A listing carries at most two, and a third is not
/// quietly dropped: it is refused out loud, because a tap that does nothing
/// reads as a screen that has stopped working.
///
/// The colours the app already knows for a garment are mapped to these by the
/// core when the listing is made; this is where they are corrected.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'edit_session.dart';
import 'fields.dart';

class ColourPicker extends StatefulWidget {
  const ColourPicker({required this.listing, required this.session, super.key});

  final Listing listing;
  final ListingEditSession session;

  @override
  State<ColourPicker> createState() => _ColourPickerState();
}

class _ColourPickerState extends State<ColourPicker> {
  /// Said under the chips after a third colour was tried, until the next tap.
  bool _full = false;

  void _toggle(DepopColour colour, bool picked) {
    final colours = widget.listing.colours;

    if (picked && colours.length >= depopColourLimit) {
      setState(() => _full = true);
      return;
    }

    setState(() => _full = false);
    widget.session.edit(
      (listing) => listing.copyWith(
        colours: picked
            ? [...listing.colours, colour]
            : [
                for (final held in listing.colours)
                  if (held != colour) held,
              ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = widget.listing.colours;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SubHeading('Colors'),
        const SizedBox(height: 4),
        const QuietText(
          'Pick up to $depopColourLimit. Buyers filter by these, so use '
          "Depop's words.",
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final colour in DepopColour.values)
              FilterChip(
                label: Text(colour.label),
                selected: colours.contains(colour),
                onSelected: (on) => _toggle(colour, on),
              ),
          ],
        ),
        if (_full) ...[
          const SizedBox(height: 8),
          Text(
            'Depop allows $depopColourLimit colors. Tap one you picked to '
            'remove it first.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.tertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
