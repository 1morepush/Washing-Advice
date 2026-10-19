/// What to ask for a garment, and what is left of it after Depop's share.
///
/// This is the part of selling somebody acts on, so it lives here and not in a
/// widget or a model: deterministic, tested, and explained. Every step that
/// moves the price adds a sentence saying so, and the screen shows them all —
/// the same rule the laundry engine follows, for the same reason. A suggested
/// price nobody can argue with is a price nobody trusts.
///
/// The rule, in the order it is applied:
///
/// 1. **Sold beats asking.** What something sold for is what somebody paid; an
///    asking price is what somebody hopes for. With two or more sold prices
///    the suggestion is their middle, asked 12% higher to leave room for
///    offers.
/// 2. **Asking prices are not marked up.** Other sellers' asking prices already
///    include their room for offers, so a price built on them is the middle of
///    what they ask, and no more.
/// 3. **With no listings, the price new decides.** A share of what it costs in
///    a shop, by condition.
/// 4. **A used garment never costs more than it does new.** Capped at the price
///    of the *same* product; a similar one is a different product.
/// 5. **Rounded the way listings are priced**, to a whole dollar under $10 and
///    to $5 above.
///
/// What the seller paid for it plays no part. It is a sunk cost, not a market:
/// the person who paid $40 for a jumper that sells for $15 is not owed $40.
library;

import 'depop.dart';
import 'listing.dart';
import 'money.dart';

/// What Depop takes out of a sale.
///
/// For the US: no selling fee, which Depop dropped in 2024, and payment
/// processing of 3.3% of the sale plus $0.45. Those are the figures as they
/// were on [asOf]; they are constants in one place, dated, and shown beside the
/// payout so that a change is one edit and a wrong figure is visible. Check
/// Depop's fee page before relying on them.
///
/// Depop may also charge the 3.3% on the shipping a buyer pays. This does not
/// include that, so when a buyer pays for postage the payout can be a little
/// less than shown.
final class DepopFees {
  const DepopFees({
    required this.percent,
    required this.fixedCents,
    required int asOfYear,
    required int asOfMonth,
    required int asOfDay,
  })  : _year = asOfYear,
        _month = asOfMonth,
        _day = asOfDay;

  /// The US fees as of 17 October 2026.
  static const DepopFees us = DepopFees(
    percent: 0.033,
    fixedCents: 45,
    asOfYear: 2026,
    asOfMonth: 10,
    asOfDay: 17,
  );

  /// The share of the sale taken, as a fraction: `0.033` is 3.3%.
  final double percent;

  /// The fixed part of the fee, in US cents.
  final int fixedCents;

  final int _year;
  final int _month;
  final int _day;

  /// The day these figures were last checked against Depop's fee page.
  ///
  /// A date and not a [DateTime] field so that [us] can be a constant.
  DateTime get asOf => DateTime.utc(_year, _month, _day);

  /// The fee on a sale at [priceCents], to the nearest cent.
  int feeCents(int priceCents) => (priceCents * percent).round() + fixedCents;

  /// What the seller is left with from a sale at [priceCents].
  int netCents(int priceCents) => priceCents - feeCents(priceCents);

  /// The fee in words: `3.3% + $0.45`, with non-breaking spaces, so that it
  /// never wraps in the middle of a bracket on a narrow screen.
  String get label {
    var share = (percent * 100).toStringAsFixed(2);
    if (share.contains('.')) share = share.replaceFirst(RegExp(r'\.?0+$'), '');
    return '$share%\u00a0+\u00a0${formatUsd(fixedCents)}';
  }
}

/// What a suggested price was built on.
enum PriceBasis {
  /// Two or more sales of the same or a similar item.
  soldComparables,

  /// What similar items are listed for, with fewer than two sales to go on.
  askingComparables,

  /// A share of what it costs new, because nothing comparable was found.
  retailEstimate,

  /// Nothing to go on.
  none,
}

/// A price to ask, with the working shown.
final class PriceSuggestion {
  const PriceSuggestion({
    required this.listPriceCents,
    required this.basis,
    required this.lowCents,
    required this.highCents,
    required this.comparablesUsed,
    required this.reasons,
    required this.netCents,
    required this.belowWorthwhileNet,
  });

  /// The price to list at, in US cents. Null when there was nothing to go on.
  final int? listPriceCents;

  final PriceBasis basis;

  /// The cheapest and dearest comparable behind it, unrounded. Null when there
  /// were no comparables.
  final int? lowCents;
  final int? highCents;

  /// How many comparable prices the suggestion rests on.
  final int comparablesUsed;

  /// Why, one plain sentence each, in the order the working went.
  final List<String> reasons;

  /// What the seller is left with at [listPriceCents] after Depop's fees.
  final int? netCents;

  /// Whether that is so little the sale is hardly worth the postage — a
  /// prompt to bundle it with something else.
  final bool belowWorthwhileNet;
}

/// The mark-up on sold prices, in percent, to leave room for offers.
///
/// Inside the 10–15% band the Depop briefing recommends.
const int _soldMarkupPercent = 12;

/// Below this, in cents, a sale is hardly worth the trip to the post office.
const int worthwhileNetCents = 500;

/// Suggests a price for something, from the evidence there is.
///
/// * [comparables] are listings for the same or a similar item, as found by a
///   price search. The same product is preferred: similar ones are added only
///   when there are fewer than two of the same.
/// * [typedComparableCents] are prices the person saw themselves after
///   following the links, in cents, and [typedComparablesSold] says whether
///   they were what things sold for. Both join the comparables.
/// * [retail] is what it costs new. It sets a ceiling for a used garment and,
///   when there is nothing else, a starting point.
/// * [condition] is how worn it is, as Depop grades it. Null means not graded,
///   and is treated as ordinary used wear.
/// * [paidCents] is what the seller paid. It is shown and then ignored: a price
///   paid is a sunk cost, not a market.
///
/// Never throws. With nothing to go on the price is null and the reasons say
/// where to look.
PriceSuggestion suggestPrice({
  required List<SaleComparable> comparables,
  List<int> typedComparableCents = const [],
  bool typedComparablesSold = false,
  required List<RetailReference> retail,
  required DepopCondition? condition,
  int? paidCents,
  DepopFees fees = DepopFees.us,
}) {
  final reasons = <String>[];

  // Which listings count: the same product if there are at least two of it,
  // otherwise anything alike. A single match is not a market, and nine similar
  // listings are better evidence than one identical one.
  final usable = [
    for (final c in comparables)
      if (c.priceCents > 0) c,
  ];
  final same = [
    for (final c in usable)
      if (c.match == ComparableMatch.same) c,
  ];
  final chosen = same.length >= 2 ? same : usable;

  final pool = <({int cents, bool sold})>[
    for (final c in chosen) (cents: c.priceCents, sold: c.sold == true),
    for (final cents in typedComparableCents)
      if (cents > 0) (cents: cents, sold: typedComparablesSold),
  ];
  final all = [for (final p in pool) p.cents];
  final sold = [
    for (final p in pool)
      if (p.sold) p.cents,
  ];

  final shops = [
    for (final r in retail)
      if (r.priceCents > 0) r,
  ];
  final sameShopPrices = [
    for (final r in shops)
      if (r.match == ComparableMatch.same) r.priceCents,
  ];

  int? raw;
  PriceBasis basis;
  var used = 0;

  if (sold.length >= 2) {
    final middle = median(sold);
    raw = _percentOf(middle, 100 + _soldMarkupPercent);
    basis = PriceBasis.soldComparables;
    used = sold.length;
    reasons
      ..add('${sold.length} sold for ${_span(sold, middle: middle)}.')
      ..add(
        'Asking $_soldMarkupPercent% above that leaves room for offers.',
      );
  } else if (all.isNotEmpty) {
    raw = median(all);
    basis = PriceBasis.askingComparables;
    used = all.length;
    reasons.addAll(_askingReasons(all: all, soldCount: sold.length));
  } else if (shops.isNotEmpty) {
    final fromSame = sameShopPrices.isNotEmpty;
    final priceNew = _lowest(
      fromSame ? sameShopPrices : [for (final r in shops) r.priceCents],
    );
    final percent = _percentOfNew(condition);
    raw = _percentOf(priceNew, percent);
    basis = PriceBasis.retailEstimate;
    reasons
      ..add('No comparable listings found.')
      ..add(
        'Estimated at $percent% of the price new (${formatUsd(priceNew)})'
        '${condition == null ? '' : ' for ${condition.label}'}.',
      );
    if (!fromSame) {
      reasons.add('That price is for a similar item, not this exact one.');
    }
  } else {
    basis = PriceBasis.none;
    reasons.add('No prices found yet — check the links to Depop and eBay.');
  }

  int? listed;
  if (raw != null) {
    listed = roundListPrice(raw);

    // A used garment is not worth more than a new one. Only the same product
    // sets the ceiling: a similar item is a different thing with a different
    // price. And rounding to the nearest can step over it — $63.50 rounds to
    // $65 — so the check is on the rounded price as well as the raw one.
    final ceiling =
        condition == DepopCondition.brandNew || sameShopPrices.isEmpty
            ? null
            : _lowest(sameShopPrices);
    if (ceiling != null && (raw > ceiling || listed > ceiling)) {
      final nearest = roundListPrice(ceiling);
      listed = nearest <= ceiling ? nearest : roundListPriceDown(ceiling);
      reasons.add('Capped at the price new (${formatUsd(ceiling)}).');
    }
  }

  final net = listed == null ? null : fees.netCents(listed);
  var belowWorthwhile = false;
  if (net != null && net < worthwhileNetCents) {
    belowWorthwhile = true;
    reasons.add(
      "After Depop's fees you'd get ${formatUsd(net)} — "
      'worth bundling with something else?',
    );
  }

  if (paidCents != null && paidCents > 0) {
    reasons.add('You paid ${formatUsd(paidCents)}.');
  }

  return PriceSuggestion(
    listPriceCents: listed,
    basis: basis,
    lowCents: all.isEmpty ? null : _lowest(all),
    highCents: all.isEmpty ? null : _highest(all),
    comparablesUsed: used,
    reasons: List<String>.unmodifiable(reasons),
    netCents: net,
    belowWorthwhileNet: belowWorthwhile,
  );
}

/// What share of the price new a used garment is worth, by condition.
///
/// Exhaustive, so a condition Depop adds has to be given a share before it can
/// be priced. Not graded is treated as ordinary used wear.
int _percentOfNew(DepopCondition? condition) => switch (condition) {
      null => 40,
      DepopCondition.brandNew => 70,
      DepopCondition.likeNew => 50,
      DepopCondition.usedExcellent => 40,
      DepopCondition.usedGood => 30,
      DepopCondition.usedFair => 20,
    };

/// [cents] times [percent]/100, to the nearest cent, halves up.
///
/// Whole-number arithmetic: a price multiplied as a double can land a hair
/// under a half-cent and round the wrong way.
int _percentOf(int cents, int percent) => (cents * percent + 50) ~/ 100;

int _lowest(List<int> values) => values.reduce((a, b) => a < b ? a : b);

int _highest(List<int> values) => values.reduce((a, b) => a > b ? a : b);

/// `$25.00–$32.00 (middle $28.00)`, or just `$30.00` when they are all alike.
String _span(List<int> prices, {required int middle}) {
  final low = _lowest(prices);
  final high = _highest(prices);
  if (low == high) return formatUsd(low);
  return '${formatUsd(low)}–${formatUsd(high)} (middle ${formatUsd(middle)})';
}

/// The sentences that explain a price built on asking prices.
///
/// [soldCount] is 0 or 1 here — two sales would have been priced as sold. One
/// sale is kept in the working but not trusted on its own, and the sentences
/// say which of the prices it was.
List<String> _askingReasons({required List<int> all, required int soldCount}) {
  final count = all.length;
  final askingCount = count - soldCount;
  final span = _span(all, middle: median(all));

  final reasons = <String>[
    if (soldCount == 0 && count == 1)
      '1 listing asks ${formatUsd(all.single)}.'
    else if (soldCount == 0)
      '$count listings ask $span.'
    else if (askingCount == 0)
      '1 listing sold for ${formatUsd(all.single)}.'
    else
      '1 sold and $askingCount ${askingCount == 1 ? 'asks' : 'ask'}, $span.',
    if (count == 1) 'Only one comparable — a rough guide.',
    if (askingCount == 0)
      'Not marked up: one sale is too little to say how much room offers need.'
    else
      "Not marked up: other sellers' asking prices already leave room for "
          'offers.',
  ];
  return reasons;
}
