/// Prices the person found themselves.
///
/// The search will not find everything. A Depop page that is not indexed is
/// invisible to it, and a sale is only called a sale when the page says so, so
/// the person who follows the links below and sees what a few of these went
/// for knows something the search does not. They type it here, and it is fed
/// to the suggestion with the rest.
///
/// One switch says whether they were what things *sold* for, and it applies to
/// all of them. It is not asked of each price: nobody types five prices and
/// then answers five questions, and mixed evidence is better entered in two
/// goes. It matters, though — a sold price outranks an asking price when the
/// core works out what to ask, so the switch changes the suggestion.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'amount_input.dart';
import 'edit_session.dart';
import 'fields.dart';

class TypedPrices extends StatelessWidget {
  const TypedPrices({required this.listing, required this.session, super.key});

  final Listing listing;
  final ListingEditSession session;

  @override
  Widget build(BuildContext context) {
    final prices = listing.typedComparableCents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SubHeading('Prices you found'),
        const SizedBox(height: 4),
        const QuietText(
          'Saw a price on Depop or eBay? Add it, in dollars. It counts '
          'towards the suggestion.',
        ),
        if (prices.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (index, cents) in prices.indexed)
                InputChip(
                  label: Text(formatUsd(cents)),
                  onDeleted: () => session.edit(
                    (listing) => listing.copyWith(
                      typedComparableCents: [
                        for (final (i, held)
                            in listing.typedComparableCents.indexed)
                          if (i != index) held,
                      ],
                    ),
                  ),
                  deleteButtonTooltipMessage: 'Remove ${formatUsd(cents)}',
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        _AmountEntry(
          onAdd: (cents) => session.edit(
            (listing) => listing.copyWith(
              typedComparableCents: [...listing.typedComparableCents, cents],
            ),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('These sold'),
          subtitle: const Text(
            'Switch on if these are what things sold for, not asking prices. '
            'Sold prices count for more.',
          ),
          value: listing.typedComparablesSold,
          onChanged: (sold) => session.edit(
            (listing) => listing.copyWith(typedComparablesSold: sold),
          ),
        ),
      ],
    );
  }
}

/// A box for a price and the button that adds it.
///
/// Its text is its own until it is added, and it is cleared when it is. What
/// cannot be read as a price is not added, and the box says so under it.
class _AmountEntry extends StatefulWidget {
  const _AmountEntry({required this.onAdd});

  final ValueChanged<int> onAdd;

  @override
  State<_AmountEntry> createState() => _AmountEntryState();
}

class _AmountEntryState extends State<_AmountEntry> {
  final TextEditingController _controller = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;

    final cents = parseUsdInput(text);
    setState(() => _invalid = cents == null);
    if (cents == null) return;

    widget.onAdd(cents);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,$ ]')),
            LengthLimitingTextInputFormatter(12),
          ],
          decoration: InputDecoration(
            labelText: 'A price you saw',
            prefixText: r'$',
            errorText: _invalid ? 'Use an amount like 32 or 32.50.' : null,
            errorMaxLines: 3,
          ),
          onChanged: (_) {
            if (_invalid) setState(() => _invalid = false);
          },
          onSubmitted: (_) => _add(),
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: FilledButton.tonal(
          onPressed: _add,
          child: Semantics(
            label: 'Add this price',
            excludeSemantics: true,
            child: const Text('Add'),
          ),
        ),
      ),
    ],
  );
}
