/// The money on a listing, as the Sell tab says it.
///
/// Every figure here is the core's: the net comes from `DepopFees`, and the
/// text from `formatUsd`. What this adds is the sentence around them, kept in
/// one place so the card and the totals cannot word the same fact two ways.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

import 'listing_when.dart';

/// What a sale at [priceCents] leaves the seller, after Depop's fees and the
/// shipping discount they chose to cover, if any.
///
/// The core's `DepopFees.saleNet`, and the only way the Sell tab works out a
/// net: the cards, the sold totals and the editor all come through it, so they
/// cannot disagree.
SaleNet saleNetOf(int priceCents, {int? shippingDiscountCents}) => DepopFees.us
    .saleNet(priceCents, shippingDiscountCents: shippingDiscountCents);

/// What the seller is left with from a sale at [priceCents].
int netOf(int priceCents, {int? shippingDiscountCents}) => saleNetOf(
  priceCents,
  shippingDiscountCents: shippingDiscountCents,
).netCents;

/// `you get $28.56`, or `you get $24.56 after $4.00 shipping discount` when the
/// seller covers some of the postage. [verb] is `get` or `got`.
String _youGet(String verb, int priceCents, int? shippingDiscountCents) {
  final sale = saleNetOf(
    priceCents,
    shippingDiscountCents: shippingDiscountCents,
  );
  final discount = sale.hasDiscount
      ? ' after ${formatUsd(sale.shippingDiscountCents)} shipping discount'
      : '';
  return 'you $verb ${formatUsd(sale.netCents)}$discount';
}

/// `$30.00 · you get $28.56`: the asking price and what is left of it.
String askingLine(int priceCents, {int? shippingDiscountCents}) =>
    '${formatUsd(priceCents)} · '
    '${_youGet('get', priceCents, shippingDiscountCents)}';

/// `Sold for $34.00 · you got $32.43`.
String soldLine(int priceCents, {int? shippingDiscountCents}) =>
    'Sold for ${formatUsd(priceCents)} · '
    '${_youGet('got', priceCents, shippingDiscountCents)}';

/// The fee, said once at the foot of the list, with the day it was checked.
///
/// "You get" is only as good as the fee behind it, and a fee is something Depop
/// changes; so the figure and its date come from the same place as the sums.
String feeNote() =>
    '"You get" is what is left after Depop\'s fee of ${DepopFees.us.label} a '
    'sale, as of ${calendarDate(DepopFees.us.asOf)}. Check Depop\'s fee page: '
    'it may have changed.';
