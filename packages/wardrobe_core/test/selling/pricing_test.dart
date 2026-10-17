import 'dart:math';

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/selling_fixtures.dart';

/// A listing found by the search. Asking unless said to be sold.
SaleComparable found(
  int cents, {
  bool? sold,
  ComparableMatch match = ComparableMatch.same,
}) =>
    comparable(priceCents: cents, sold: sold, match: match);

RetailReference shop(
  int cents, {
  ComparableMatch match = ComparableMatch.same,
}) =>
    reference(priceCents: cents, match: match);

PriceSuggestion suggest({
  List<SaleComparable> comparables = const [],
  List<int> typed = const [],
  bool typedSold = false,
  List<RetailReference> retail = const [],
  DepopCondition? condition = DepopCondition.usedExcellent,
  int? paid,
  DepopFees fees = DepopFees.us,
}) =>
    suggestPrice(
      comparables: comparables,
      typedComparableCents: typed,
      typedComparablesSold: typedSold,
      retail: retail,
      condition: condition,
      paidCents: paid,
      fees: fees,
    );

/// The price a single asking listing at [cents] is rounded to.
int listedFrom(int cents) =>
    suggest(comparables: [found(cents)]).listPriceCents!;

void main() {
  group('DepopFees', () {
    test('are the US fees as checked on 17 October 2026', () {
      expect(DepopFees.us.percent, 0.033);
      expect(DepopFees.us.fixedCents, 45);
      expect(DepopFees.us.asOf, DateTime.utc(2026, 10, 17));
    });

    test('take 3.3% plus \$0.45: \$30 leaves \$28.56', () {
      expect(DepopFees.us.feeCents(3000), 144);
      expect(formatUsd(DepopFees.us.feeCents(3000)), r'$1.44');
      expect(DepopFees.us.netCents(3000), 2856);
      expect(formatUsd(DepopFees.us.netCents(3000)), r'$28.56');
    });

    test('work out the fee on other prices', () {
      expect(DepopFees.us.feeCents(1000), 78); // 33 + 45
      expect(DepopFees.us.netCents(1000), 922);
      expect(DepopFees.us.feeCents(10000), 375);
      expect(DepopFees.us.netCents(10000), 9625);
    });

    test('round a half cent up', () {
      // 3.3% of \$5 is 16.5 cents, and of \$15 is 49.5.
      expect(DepopFees.us.feeCents(500), 62); // 17 + 45
      expect(DepopFees.us.feeCents(1500), 95); // 50 + 45
      expect(DepopFees.us.feeCents(2500), 128); // 83 + 45
    });

    test('are never rounded the wrong way by floating point', () {
      // 3.3% is not exactly representable. Every price that lands on a half
      // cent must still round up, however far up the scale it is.
      for (var dollars = 5; dollars <= 100000; dollars += 10) {
        final cents = dollars * 100;
        final exact = (cents * 33 + 500) ~/ 1000; // whole-number arithmetic
        expect(
          DepopFees.us.feeCents(cents) - 45,
          exact,
          reason: '\$$dollars',
        );
      }
    });

    test('leave the seller with more for a higher price', () {
      var last = DepopFees.us.netCents(0);
      for (var cents = 1; cents <= 100000; cents++) {
        final net = DepopFees.us.netCents(cents);
        expect(net, greaterThanOrEqualTo(last), reason: '$cents');
        last = net;
      }
    });

    test('describe themselves in words', () {
      expect(DepopFees.us.label, r'3.3% + $0.45');
    });

    test('describe other fees in words too', () {
      DepopFees fees(double percent, int fixed) => DepopFees(
            percent: percent,
            fixedCents: fixed,
            asOfYear: 2027,
            asOfMonth: 1,
            asOfDay: 2,
          );

      expect(fees(0.05, 30).label, r'5% + $0.30');
      expect(fees(0.1, 0).label, r'10% + $0.00');
      expect(fees(0.0325, 45).label, r'3.25% + $0.45');
    });

    test('can be replaced when Depop changes them', () {
      const cheaper = DepopFees(
        percent: 0.1,
        fixedCents: 0,
        asOfYear: 2027,
        asOfMonth: 3,
        asOfDay: 1,
      );

      expect(cheaper.netCents(3000), 2700);
      expect(cheaper.asOf, DateTime.utc(2027, 3, 1));
    });
  });

  group('with two or more sales', () {
    test('asks the middle sold price plus 12%, rounded', () {
      final result = suggest(
        comparables: [
          found(2500, sold: true),
          found(3200, sold: true),
          found(2800, sold: true),
        ],
      );

      // The middle is \$28.00; 12% more is \$31.36, which rounds to \$30.
      expect(result.listPriceCents, 3000);
      expect(result.basis, PriceBasis.soldComparables);
    });

    test('says what it found and why it asks more', () {
      final result = suggest(
        comparables: [
          found(2500, sold: true),
          found(3200, sold: true),
          found(2800, sold: true),
        ],
      );

      expect(result.reasons.take(2), [
        '3 sold for \$25.00–\$32.00 (middle \$28.00).',
        'Asking 12% above that leaves room for offers.',
      ]);
    });

    test('two sales are enough, and their middle is the mean', () {
      final result = suggest(
        comparables: [found(2400, sold: true), found(3000, sold: true)],
      );

      // \$27.00 + 12% = \$30.24.
      expect(result.listPriceCents, 3000);
      expect(result.comparablesUsed, 2);
      expect(
          result.reasons.first, '2 sold for \$24.00–\$30.00 (middle \$27.00).');
    });

    test('the markup really is 12%', () {
      // \$40.00 + 12% = \$44.80, which rounds up to \$45. With no markup it
      // would stay at \$40.
      final result = suggest(
        comparables: [found(4000, sold: true), found(4000, sold: true)],
      );

      expect(result.listPriceCents, 4500);
    });

    test('sales at one price are said once', () {
      final result = suggest(
        comparables: [found(3000, sold: true), found(3000, sold: true)],
      );

      expect(result.reasons.first, '2 sold for \$30.00.');
      expect(result.listPriceCents, 3500);
    });

    test('an odd number of sales uses the one in the middle', () {
      final result = suggest(
        comparables: [
          found(1000, sold: true),
          found(3000, sold: true),
          found(9000, sold: true),
        ],
      );

      // The middle is \$30.00, whatever the \$90.00 is doing: \$33.60 -> \$35.
      expect(result.listPriceCents, 3500);
    });

    test('one outlier does not drag the price', () {
      final result = suggest(
        comparables: [
          found(2800, sold: true),
          found(3000, sold: true),
          found(3200, sold: true),
          found(40000, sold: true),
        ],
      );

      // The middle is \$31.00, not the \$119.50 a mean would give.
      expect(result.listPriceCents, 3500);
    });

    test('asking prices among them widen the range but not the price', () {
      final result = suggest(
        comparables: [
          found(3000, sold: true),
          found(3200, sold: true),
          found(5000),
        ],
      );

      expect(result.listPriceCents, 3500);
      expect(result.lowCents, 3000);
      expect(result.highCents, 5000);
      expect(result.comparablesUsed, 2);
      expect(
          result.reasons.first, '2 sold for \$30.00–\$32.00 (middle \$31.00).');
    });

    test('a listing whose page does not say it sold is not a sale', () {
      final result = suggest(
        comparables: [
          found(3000, sold: true),
          found(3200),
          found(3400, sold: false),
        ],
      );

      expect(result.basis, PriceBasis.askingComparables);
    });

    test('works out the payout after fees', () {
      final result = suggest(
        comparables: [found(2800, sold: true), found(2800, sold: true)],
      );

      // \$28.00 + 12% = \$31.36, which rounds to \$30.
      expect(result.listPriceCents, 3000);
      expect(result.netCents, 2856);
    });
  });

  group('with fewer than two sales', () {
    test('asks the middle of what is asked, with no markup', () {
      final result = suggest(
        comparables: [found(2000), found(2400), found(2600)],
      );

      expect(result.listPriceCents, 2500);
      expect(result.basis, PriceBasis.askingComparables);
      expect(result.comparablesUsed, 3);
      expect(result.lowCents, 2000);
      expect(result.highCents, 2600);
    });

    test('says what is asked and why it is not marked up', () {
      final result = suggest(
        comparables: [found(2000), found(2400), found(2600)],
      );

      expect(result.reasons.take(2), [
        '3 listings ask \$20.00–\$26.00 (middle \$24.00).',
        "Not marked up: other sellers' asking prices already leave room for "
            'offers.',
      ]);
    });

    test('an even number of prices is averaged', () {
      final result = suggest(comparables: [found(2000), found(3000)]);

      expect(result.listPriceCents, 2500);
      expect(
        result.reasons.first,
        '2 listings ask \$20.00–\$30.00 (middle \$25.00).',
      );
    });

    test('prices all alike are said once', () {
      final result = suggest(comparables: [found(3000), found(3000)]);

      expect(result.reasons.first, '2 listings ask \$30.00.');
      expect(result.listPriceCents, 3000);
    });

    test('one sale and one asking price are priced between them', () {
      // The case the whole screen is built around: one sold at \$32, one still
      // asking \$28, and a payout of \$28.56 on the \$30 in between.
      final result = suggest(
        comparables: [found(3200, sold: true), found(2800, sold: false)],
      );

      expect(result.listPriceCents, 3000);
      expect(result.basis, PriceBasis.askingComparables);
      expect(result.netCents, 2856);
      expect(result.reasons.take(2), [
        '1 sold and 1 asks, \$28.00–\$32.00 (middle \$30.00).',
        "Not marked up: other sellers' asking prices already leave room for "
            'offers.',
      ]);
    });

    test('one sale among several asking prices says which was which', () {
      final result = suggest(
        comparables: [found(3200, sold: true), found(2000), found(2200)],
      );

      expect(
        result.reasons.first,
        '1 sold and 2 ask, \$20.00–\$32.00 (middle \$22.00).',
      );
      // A single sale does not outrank the rest: the middle of everything.
      expect(result.listPriceCents, 2000);
    });

    test('one asking price is a rough guide, and says so', () {
      final result = suggest(comparables: [found(2800)]);

      expect(result.listPriceCents, 3000);
      expect(result.comparablesUsed, 1);
      expect(result.reasons.take(3), [
        '1 listing asks \$28.00.',
        'Only one comparable — a rough guide.',
        "Not marked up: other sellers' asking prices already leave room for "
            'offers.',
      ]);
    });

    test('one sale on its own is a rough guide, and not called an ask', () {
      final result = suggest(comparables: [found(3200, sold: true)]);

      expect(result.basis, PriceBasis.askingComparables);
      expect(result.listPriceCents, 3000);
      expect(result.reasons.take(3), [
        '1 listing sold for \$32.00.',
        'Only one comparable — a rough guide.',
        'Not marked up: one sale is too little to say how much room offers '
            'need.',
      ]);
    });

    test('one sale does not make the asking prices around it sales', () {
      final result = suggest(
        comparables: [found(3200, sold: true), found(2000), found(2200)],
      );

      expect(result.basis, PriceBasis.askingComparables);
    });
  });

  group('which comparables count', () {
    test('only the same product, when there are at least two of it', () {
      final result = suggest(
        comparables: [
          found(2500),
          found(2600),
          found(9900, match: ComparableMatch.similar),
        ],
      );

      expect(result.comparablesUsed, 2);
      expect(result.lowCents, 2500);
      expect(result.highCents, 2600);
    });

    test('similar ones join in when there are fewer than two of the same', () {
      final result = suggest(
        comparables: [
          found(2500),
          found(2700, match: ComparableMatch.similar),
          found(2900, match: ComparableMatch.similar),
        ],
      );

      expect(result.comparablesUsed, 3);
      expect(result.lowCents, 2500);
      expect(result.highCents, 2900);
    });

    test('similar ones are all there is when none is the same', () {
      final result = suggest(
        comparables: [
          found(2000, match: ComparableMatch.similar),
          found(3000, match: ComparableMatch.similar),
        ],
      );

      expect(result.comparablesUsed, 2);
      expect(result.listPriceCents, 2500);
    });

    test('a price of nothing is not a comparable', () {
      final result = suggest(
        comparables: [found(0), found(-500), found(2800)],
      );

      expect(result.comparablesUsed, 1);
      expect(result.lowCents, 2800);
    });
  });

  group('the person\'s own prices', () {
    test('count as asking prices unless they were sales', () {
      final result = suggest(typed: [2500, 2700]);

      expect(result.basis, PriceBasis.askingComparables);
      expect(result.listPriceCents, 2500); // middle \$26.00 -> \$25
      expect(result.comparablesUsed, 2);
    });

    test('count as sales when they were', () {
      final result = suggest(typed: [2800, 3000], typedSold: true);

      expect(result.basis, PriceBasis.soldComparables);
      // \$29.00 + 12% = \$32.48 -> \$30.
      expect(result.listPriceCents, 3000);
      expect(
          result.reasons.first, '2 sold for \$28.00–\$30.00 (middle \$29.00).');
    });

    test('change the answer: typed sales outrank what the search found', () {
      final withoutThem = suggest(comparables: [found(2000), found(2200)]);
      final withThem = suggest(
        comparables: [found(2000), found(2200)],
        typed: [3800, 4000],
        typedSold: true,
      );

      expect(withoutThem.basis, PriceBasis.askingComparables);
      expect(withThem.basis, PriceBasis.soldComparables);
      expect(withThem.listPriceCents, greaterThan(withoutThem.listPriceCents!));
    });

    test('join sales the search found to make two', () {
      final result = suggest(
        comparables: [found(3000, sold: true)],
        typed: [3200],
        typedSold: true,
      );

      expect(result.basis, PriceBasis.soldComparables);
      expect(result.comparablesUsed, 2);
    });

    test('typed asking prices do not turn a lone sale into two', () {
      final result = suggest(
        comparables: [found(3000, sold: true)],
        typed: [3200],
      );

      expect(result.basis, PriceBasis.askingComparables);
    });

    test('are a price on their own when the search found nothing', () {
      final result = suggest(typed: [3000]);

      expect(result.listPriceCents, 3000);
      expect(result.reasons.first, '1 listing asks \$30.00.');
    });

    test('join the pool after the same-or-similar choice is made', () {
      // Two of the same product: the similar one stays out, typed prices
      // or not.
      final result = suggest(
        comparables: [
          found(2500),
          found(2600),
          found(9900, match: ComparableMatch.similar),
        ],
        typed: [2700],
      );

      expect(result.highCents, 2700);
      expect(result.comparablesUsed, 3);
    });

    test('a typed price of nothing is ignored', () {
      final result = suggest(typed: [0, -100, 2800]);

      expect(result.comparablesUsed, 1);
      expect(result.lowCents, 2800);
    });
  });

  group('with no listings at all', () {
    final tenDollarsFromRetail = [shop(6000)];

    test('estimates a share of the price new, by condition', () {
      int listPriceFor(DepopCondition? condition) => suggest(
            retail: tenDollarsFromRetail,
            condition: condition,
          ).listPriceCents!;

      // Brand new is not capped by the price new; the rest are far below it.
      expect(listPriceFor(DepopCondition.brandNew), 4000); // 70% = \$42 -> \$40
      expect(listPriceFor(DepopCondition.likeNew), 3000); // 50% = \$30
      expect(listPriceFor(DepopCondition.usedExcellent), 2500); // 40% = \$24
      expect(listPriceFor(DepopCondition.usedGood), 2000); // 30% = \$18
      expect(listPriceFor(DepopCondition.usedFair), 1000); // 20% = \$12
      expect(listPriceFor(null), 2500); // not graded: 40%
    });

    test('says there were no listings and how it got the figure', () {
      final result = suggest(retail: [shop(6000)]);

      expect(result.basis, PriceBasis.retailEstimate);
      expect(result.reasons.take(2), [
        'No comparable listings found.',
        'Estimated at 40% of the price new (\$60.00) for Used - Excellent.',
      ]);
    });

    test('names the percentage that goes with the condition', () {
      expect(
        suggest(retail: [shop(6000)], condition: DepopCondition.likeNew)
            .reasons[1],
        'Estimated at 50% of the price new (\$60.00) for Like new.',
      );
      expect(
        suggest(retail: [shop(6000)], condition: DepopCondition.usedFair)
            .reasons[1],
        'Estimated at 20% of the price new (\$60.00) for Used - Fair.',
      );
    });

    test('leaves the condition out of the sentence when it is not graded', () {
      expect(
        suggest(retail: [shop(6000)], condition: null).reasons[1],
        'Estimated at 40% of the price new (\$60.00).',
      );
    });

    test('uses the cheapest place that sells the same thing', () {
      final result = suggest(
        retail: [
          shop(7000),
          shop(5000),
          shop(3000, match: ComparableMatch.similar),
        ],
      );

      expect(result.reasons[1], contains('(\$50.00)'));
      expect(result.listPriceCents, 2000); // 40% of \$50 = \$20
    });

    test('falls back to similar items, and says it is not this one', () {
      final result = suggest(
        retail: [
          shop(8000, match: ComparableMatch.similar),
          shop(6000, match: ComparableMatch.similar),
        ],
      );

      expect(
          result.reasons,
          contains('Estimated at 40% of the price new '
              '(\$60.00) for Used - Excellent.'));
      expect(result.reasons,
          contains('That price is for a similar item, not this exact one.'));
      expect(result.listPriceCents, 2500);
    });

    test('has no range, because there were no comparables', () {
      final result = suggest(retail: [shop(6000)]);

      expect(result.lowCents, isNull);
      expect(result.highCents, isNull);
      expect(result.comparablesUsed, 0);
    });

    test('ignores a shop price of nothing', () {
      final result = suggest(retail: [shop(0), shop(6000)]);

      expect(result.listPriceCents, 2500);
    });

    test('is only used when there is nothing else', () {
      final result = suggest(
        comparables: [found(2000), found(2200)],
        retail: [shop(6000)],
      );

      expect(result.basis, PriceBasis.askingComparables);
    });
  });

  group('with nothing to go on', () {
    final nothing = suggest();

    test('suggests no price', () {
      expect(nothing.listPriceCents, isNull);
      expect(nothing.basis, PriceBasis.none);
      expect(nothing.netCents, isNull);
      expect(nothing.belowWorthwhileNet, isFalse);
      expect(nothing.lowCents, isNull);
      expect(nothing.highCents, isNull);
      expect(nothing.comparablesUsed, 0);
    });

    test('says where to look', () {
      expect(nothing.reasons, [
        'No prices found yet — check the links to Depop and eBay.',
      ]);
    });

    test('still notes what was paid', () {
      expect(suggest(paid: 4000).reasons, [
        'No prices found yet — check the links to Depop and eBay.',
        'You paid \$40.00.',
      ]);
    });
  });

  group('never more than it costs new', () {
    test('caps a used garment at the price of the same thing new', () {
      final result = suggest(
        comparables: [found(8000), found(8200)],
        retail: [shop(6000)],
        condition: DepopCondition.usedGood,
      );

      expect(result.listPriceCents, 6000);
      expect(result.reasons, contains('Capped at the price new (\$60.00).'));
    });

    test('does not mention a cap when nothing was capped', () {
      final result = suggest(
        comparables: [found(5000), found(5200)],
        retail: [shop(6000)],
      );

      expect(result.listPriceCents, 5000);
      expect(result.reasons.where((r) => r.startsWith('Capped')), isEmpty);
    });

    test('does not cap something brand new', () {
      // New with tags can sell for what it cost, or more once it is sold out.
      final result = suggest(
        comparables: [found(8000), found(8200)],
        retail: [shop(6000)],
        condition: DepopCondition.brandNew,
      );

      expect(result.listPriceCents, 8000);
    });

    test('does not cap by a similar item, which is a different product', () {
      final result = suggest(
        comparables: [found(8000), found(8200)],
        retail: [shop(6000, match: ComparableMatch.similar)],
      );

      expect(result.listPriceCents, 8000);
    });

    test('caps by the cheapest place that sells the same thing', () {
      final result = suggest(
        comparables: [found(9000), found(9200)],
        retail: [
          shop(7000),
          shop(6000),
          shop(5000, match: ComparableMatch.similar)
        ],
      );

      expect(result.listPriceCents, 6000);
    });

    test('caps something that has not been graded too', () {
      final result = suggest(
        comparables: [found(8000), found(8200)],
        retail: [shop(6000)],
        condition: null,
      );

      expect(result.listPriceCents, 6000);
    });

    test('caps a price built on sales as well', () {
      final result = suggest(
        comparables: [found(7000, sold: true), found(7400, sold: true)],
        retail: [shop(6000)],
      );

      // The middle is \$72.00 and +12% is \$80.64, over the \$60.00 new.
      expect(result.basis, PriceBasis.soldComparables);
      expect(result.listPriceCents, 6000);
    });

    test('is not undone by rounding up past it', () {
      // \$63.50 is the price new. The asking price is \$63.50 too, and the
      // nearest multiple of \$5 to that is \$65 — over what it costs new.
      final result = suggest(
        comparables: [found(6300), found(6400)],
        retail: [shop(6350)],
      );

      expect(result.listPriceCents, 6000);
      expect(result.reasons, contains('Capped at the price new (\$63.50).'));
    });

    test('is not undone by rounding a price just under it up past it', () {
      final result = suggest(
        comparables: [found(6300), found(6300)],
        retail: [shop(6350)],
      );

      // \$63.00 rounds to \$65, which is over \$63.50.
      expect(result.listPriceCents, 6000);
    });

    test('says so after how the price was reached', () {
      final result = suggest(
        comparables: [found(8000), found(8200)],
        retail: [shop(6000)],
      );

      expect(result.reasons.indexOf('Capped at the price new (\$60.00).'),
          greaterThan(0));
      expect(result.reasons.first, startsWith('2 listings ask'));
    });
  });

  group('rounding the price to something a seller would list', () {
    test('under \$10 it is a whole dollar', () {
      expect(listedFrom(949), 900); // \$9.49 -> \$9
      expect(listedFrom(701), 700);
    });

    test('a half dollar goes up', () {
      expect(listedFrom(950), 1000); // \$9.50 -> \$10
      expect(listedFrom(750), 800);
    });

    test('from \$10 it is the nearest \$5', () {
      expect(listedFrom(1249), 1000); // \$12.49 -> \$10
      expect(listedFrom(1250), 1500); // \$12.50 -> \$15
      expect(listedFrom(1300), 1500);
      expect(listedFrom(2740), 2500);
    });

    test('is never below \$1', () {
      expect(listedFrom(45), 100);
      expect(listedFrom(1), 100);
    });

    test('leaves a price that is already a multiple of \$5', () {
      expect(listedFrom(2500), 2500);
      expect(listedFrom(10000), 10000);
    });

    test('rounds the middle of two prices, not each of them', () {
      // \$12.00 and \$13.00 have a middle of \$12.50, which goes up.
      expect(suggest(comparables: [found(1200), found(1300)]).listPriceCents,
          1500);
    });

    test('keeps the range exactly as found, unrounded', () {
      final result = suggest(comparables: [found(1249), found(2851)]);

      expect(result.lowCents, 1249);
      expect(result.highCents, 2851);
    });
  });

  group('what is left after fees', () {
    test('is worked out from the price to list at', () {
      final result = suggest(comparables: [found(3000)]);

      expect(result.netCents, DepopFees.us.netCents(3000));
      expect(result.netCents, 2856);
      expect(result.belowWorthwhileNet, isFalse);
    });

    test('is flagged when it is so little the sale is hardly worth it', () {
      final result = suggest(comparables: [found(500)]);

      // \$5.00 less \$0.17 and \$0.45.
      expect(result.listPriceCents, 500);
      expect(result.netCents, 438);
      expect(result.belowWorthwhileNet, isTrue);
      expect(
        result.reasons,
        contains(
          "After Depop's fees you'd get \$4.38 — worth bundling with "
          'something else?',
        ),
      );
    });

    test('is not flagged from \$6 up', () {
      final result = suggest(comparables: [found(600)]);

      expect(result.netCents, 535);
      expect(result.belowWorthwhileNet, isFalse);
      expect(
        result.reasons.where((r) => r.contains('worth bundling')),
        isEmpty,
      );
    });

    test('is flagged below \$5.00 and not at \$5.00 exactly', () {
      const flat = DepopFees(
        percent: 0,
        fixedCents: 100,
        asOfYear: 2027,
        asOfMonth: 1,
        asOfDay: 1,
      );

      // \$6 less \$1 is exactly \$5.00; \$5 less \$1 is \$4.00.
      expect(
        suggest(comparables: [found(600)], fees: flat).belowWorthwhileNet,
        isFalse,
      );
      expect(
        suggest(comparables: [found(500)], fees: flat).belowWorthwhileNet,
        isTrue,
      );
    });

    test('uses the fees it is given', () {
      const tenPercent = DepopFees(
        percent: 0.1,
        fixedCents: 0,
        asOfYear: 2027,
        asOfMonth: 1,
        asOfDay: 1,
      );
      final result = suggest(comparables: [found(3000)], fees: tenPercent);

      expect(result.netCents, 2700);
    });

    test('comes after how the price was reached and any cap', () {
      final result = suggest(
        comparables: [found(900), found(900)],
        retail: [shop(500)],
        paid: 2000,
      );

      // Capped to \$5.00, which leaves \$4.38.
      expect(result.reasons.last, 'You paid \$20.00.');
      final capped = result.reasons.indexWhere((r) => r.startsWith('Capped'));
      final bundling = result.reasons.indexWhere((r) => r.contains('bundling'));
      expect(capped, greaterThan(0));
      expect(bundling, greaterThan(capped));
    });
  });

  group('what the seller paid', () {
    final comparables = [found(3200, sold: true), found(2800, sold: true)];

    test('never changes the price', () {
      final without = suggest(comparables: comparables);

      for (final paid in [1, 500, 4000, 100000]) {
        final withPaid = suggest(comparables: comparables, paid: paid);

        expect(withPaid.listPriceCents, without.listPriceCents,
            reason: '$paid');
        expect(withPaid.netCents, without.netCents);
        expect(withPaid.basis, without.basis);
        expect(withPaid.belowWorthwhileNet, without.belowWorthwhileNet);
      }
    });

    test('is noted last', () {
      final result = suggest(comparables: comparables, paid: 4000);

      expect(result.reasons.last, 'You paid \$40.00.');
    });

    test('is not mentioned when it is not given', () {
      final result = suggest(comparables: comparables);

      expect(result.reasons.where((r) => r.startsWith('You paid')), isEmpty);
    });

    test('is not mentioned when it was nothing, as with a gift', () {
      final result = suggest(comparables: comparables, paid: 0);

      expect(result.reasons.where((r) => r.startsWith('You paid')), isEmpty);
    });
  });

  group('the condition', () {
    test('does not move a price built on comparables', () {
      final prices = {
        for (final condition in [null, ...DepopCondition.values])
          condition: suggest(
            comparables: [found(2800), found(3000)],
            condition: condition,
          ).listPriceCents,
      };

      expect(prices.values.toSet(), hasLength(1));
    });
  });

  group('the example from the Depop briefing', () {
    test('one sold at \$32 and one asking \$28 gives \$30 and \$28.56', () {
      final result = suggest(
        comparables: [found(3200, sold: true), found(2800, sold: false)],
      );

      expect(result.listPriceCents, 3000);
      expect(formatUsd(result.netCents!), r'$28.56');
    });

    test('works on the comparables in the contract\'s own example', () {
      // contracts/examples/listing/prices_ok.json: a sale at \$32, an asking
      // price of \$28, a similar listing at \$35, and a similar shop item at
      // \$60.
      final result = suggest(
        comparables: [
          found(3200, sold: true),
          found(2800, sold: false),
          found(3500, match: ComparableMatch.similar),
        ],
        retail: [shop(6000, match: ComparableMatch.similar)],
        condition: DepopCondition.usedExcellent,
      );

      // Two of the same product, so the \$35 similar listing stays out; and a
      // similar shop item does not cap.
      expect(result.listPriceCents, 3000);
      expect(result.netCents, 2856);
      expect(result.comparablesUsed, 2);
      expect(result.lowCents, 2800);
      expect(result.highCents, 3200);
    });
  });

  group('whatever it is given', () {
    test('it gives a price a seller could list, or none', () {
      final random = Random(20261017);
      final conditions = <DepopCondition?>[null, ...DepopCondition.values];

      List<SaleComparable> randomComparables() => [
            for (var i = 0; i < random.nextInt(7); i++)
              found(
                1 + random.nextInt(30000),
                sold: [true, false, null][random.nextInt(3)],
                match: ComparableMatch.values[random.nextInt(2)],
              ),
          ];
      List<RetailReference> randomShops() => [
            for (var i = 0; i < random.nextInt(4); i++)
              shop(
                1 + random.nextInt(40000),
                match: ComparableMatch.values[random.nextInt(2)],
              ),
          ];

      for (var round = 0; round < 2000; round++) {
        final comparables = randomComparables();
        final retail = randomShops();
        final condition = conditions[random.nextInt(conditions.length)];
        final typed = [
          for (var i = 0; i < random.nextInt(3); i++) random.nextInt(30000),
        ];
        final result = suggest(
          comparables: comparables,
          typed: typed,
          typedSold: random.nextBool(),
          retail: retail,
          condition: condition,
        );
        final why =
            'round $round: $comparables / $typed / $retail / $condition';

        expect(result.reasons, isNotEmpty, reason: why);
        expect(result.basis == PriceBasis.none, result.listPriceCents == null,
            reason: why);

        final list = result.listPriceCents;
        if (list == null) {
          expect(result.netCents, isNull, reason: why);
          continue;
        }

        // A price somebody would actually list.
        expect(list, greaterThanOrEqualTo(100), reason: why);
        expect(list % 100, 0, reason: why);
        if (list >= 1000) expect(list % 500, 0, reason: why);

        // Never above the price of the same thing new, unless it is new. The
        // one exception is a price new under \$1, which cannot be honoured:
        // no listing goes below a dollar.
        final sameNew = [
          for (final r in retail)
            if (r.match == ComparableMatch.same) r.priceCents,
        ];
        if (condition != DepopCondition.brandNew && sameNew.isNotEmpty) {
          expect(
            list,
            lessThanOrEqualTo(max(sameNew.reduce(min), 100)),
            reason: why,
          );
        }

        // The payout is the fee formula applied to that price.
        expect(result.netCents, DepopFees.us.netCents(list), reason: why);
        expect(result.belowWorthwhileNet, result.netCents! < 500, reason: why);

        // The range brackets the comparables behind it.
        if (result.lowCents != null) {
          expect(result.lowCents, lessThanOrEqualTo(result.highCents!),
              reason: why);
        }
      }
    });
  });
}
