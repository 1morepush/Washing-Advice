/// The money on a listing, as the Sell tab says it.
///
/// Every figure here is the core's: the net comes from `DepopFees`, and the
/// text from `formatUsd`. What this adds is the sentence around them, kept in
/// one place so the card and the totals cannot word the same fact two ways.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

import 'listing_when.dart';

/// What the seller is left with from a sale at [priceCents], after Depop's fees.
int netOf(int priceCents) => DepopFees.us.netCents(priceCents);

/// `$30.00 · you get $28.56`: the asking price and what is left of it.
String askingLine(int priceCents) =>
    '${formatUsd(priceCents)} · you get ${formatUsd(netOf(priceCents))}';

/// `Sold for $34.00 · you got $32.43`.
String soldLine(int priceCents) =>
    'Sold for ${formatUsd(priceCents)} · you got '
    '${formatUsd(netOf(priceCents))}';

/// The fee, said once at the foot of the list, with the day it was checked.
///
/// "You get" is only as good as the fee behind it, and a fee is something Depop
/// changes; so the figure and its date come from the same place as the sums.
String feeNote() =>
    '"You get" is what is left after Depop\'s fee of ${DepopFees.us.label} a '
    'sale, as of ${calendarDate(DepopFees.us.asOf)}. Check Depop\'s fee page: '
    'it may have changed.';
