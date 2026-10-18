/// The price: what the core suggests and why, and what the person asks.
///
/// Turning comparables into a price is arithmetic with rules, and the rules
/// live in the core, tested, with a sentence for every step that moved the
/// number. This shows the number large and every one of those sentences under
/// it. A suggested price nobody can argue with is a price nobody trusts, so it
/// is never a bare figure: the reasons are the product, and the figure is what
/// they add up to.
///
/// **The suggestion is offered, never applied.** "Use $30.00" sets the price;
/// nothing sets it by itself. What to ask is the seller's call and the number
/// they type is the one that stands.
///
/// **Under it is the payout.** Depop takes a share of every sale, and the
/// figure that decides whether a sale is worth the postage is what is left, not
/// what is asked. It is shown beside the price, with the fees it was worked out
/// from and the day those were last checked, because a fee that has changed
/// since is a payout that is wrong.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../widgets/notice.dart';
import '../../../widgets/rinse_kit.dart';
import 'amount_input.dart';
import 'edit_session.dart';
import 'fields.dart';

/// Below this, in cents, what is left of a sale is hardly worth the postage.
///
/// The same line the core draws for its own suggestion
/// (`PriceSuggestion.belowWorthwhileNet`), applied here to the price the person
/// typed, which the core never sees.
const int worthwhileNetCents = 500;

/// What the garment cost, in cents, when it was bought in US dollars; else
/// null.
///
/// Only dollars. A price paid in euros is not a figure that can be put beside
/// a Depop price without an exchange rate, and the core's rule is to carry
/// none rather than invent one.
int? paidCentsOf(WardrobeItem? garment) {
  final purchase = garment?.purchase;
  if (purchase == null) return null;
  if (purchase.currencyCode.toUpperCase() != 'USD') return null;
  return purchase.priceMinorUnits > 0 ? purchase.priceMinorUnits : null;
}

/// The core's suggestion for [listing], from everything it has to go on.
///
/// What a search found counts only if it found: a search that did not answer
/// has no comparables, and passing its empty lists would say the same as
/// passing nothing.
PriceSuggestion suggestionFor(Listing listing, {int? paidCents}) {
  final search = listing.priceSearch;
  final found = search != null && search.status == PriceSearchStatus.ok;

  return suggestPrice(
    comparables: found ? search.comparables : const [],
    retail: found ? search.retail : const [],
    typedComparableCents: listing.typedComparableCents,
    typedComparablesSold: listing.typedComparablesSold,
    condition: listing.condition,
    paidCents: paidCents,
  );
}

/// The suggested price, large, with its range and every reason.
class SuggestionBlock extends StatelessWidget {
  const SuggestionBlock({
    required this.suggestion,
    required this.price,
    required this.onUse,
    super.key,
  });

  final PriceSuggestion suggestion;

  /// What the person is asking now, to tell when the suggestion is already it.
  final int? price;

  /// Sets the price to the suggestion.
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggested = suggestion.listPriceCents;
    final low = suggestion.lowCents;
    final high = suggestion.highCents;

    return InsetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SubHeading('Suggested price'),
          if (suggested != null) ...[
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                formatUsd(suggested),
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          if (low != null && high != null) ...[
            const SizedBox(height: 4),
            QuietText(
              low == high
                  ? 'The price seen was ${formatUsd(low)}.'
                  : 'Prices seen range from ${formatUsd(low)} to '
                        '${formatUsd(high)}.',
            ),
          ],
          const SizedBox(height: 8),
          for (final reason in suggestion.reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(reason, style: theme.textTheme.bodyMedium),
            ),
          if (suggested != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonal(
                onPressed: price == suggested ? null : onUse,
                child: Text('Use ${formatUsd(suggested)}'),
              ),
            ),
            if (price == suggested) ...[
              const SizedBox(height: 4),
              const QuietText("That's the price you have."),
            ],
          ],
        ],
      ),
    );
  }
}

/// The price the person asks, and what is left of it after Depop's fees.
class YourPrice extends StatelessWidget {
  const YourPrice({
    required this.listing,
    required this.session,
    required this.suggestion,
    super.key,
  });

  final Listing listing;
  final ListingEditSession session;
  final PriceSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const fees = DepopFees.us;
    final price = listing.priceCents;
    final net = price == null ? null : fees.netCents(price);

    // Either the price they typed leaves too little, or the one suggested
    // would. The first is said first: it is the one they are looking at.
    final String? warning;
    if (net != null && net < worthwhileNetCents) {
      warning =
          "You'd get only ${formatUsd(net)} after Depop's fees. Is it worth "
          'the postage? Bundling it with something else may be.';
    } else if (suggestion.belowWorthwhileNet) {
      warning =
          'The suggested price would leave only '
          "${formatUsd(suggestion.netCents ?? 0)} after Depop's fees. "
          'Bundling it with something else may be worth it.';
    } else {
      warning = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ParsedField<int>(
          key: const ValueKey('price'),
          value: price,
          parse: parseUsdInput,
          format: usdInputText,
          label: 'Your price',
          prefixText: r'$',
          invalidMessage: 'Use an amount like 32 or 32.50.',
          onChanged: (cents) => session.edit(
            (listing) => cents == null
                ? listing.copyWith(clearPrice: true)
                : listing.copyWith(priceCents: cents),
          ),
        ),
        const SizedBox(height: 8),
        if (net != null) ...[
          Text(
            "You get ${formatUsd(net)} after Depop's fees (${fees.label})",
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          QuietText(
            'Fees as of '
            '${MaterialLocalizations.of(context).formatShortDate(fees.asOf)}'
            " — check Depop's fee page.",
          ),
        ] else
          const QuietText(
            "Type the price you'll ask, and you'll see what you get after "
            "Depop's fees.",
          ),
        if (warning != null) ...[
          const SizedBox(height: 12),
          Notice(
            icon: Icons.local_shipping_outlined,
            warning: true,
            text: warning,
          ),
        ],
      ],
    );
  }
}
