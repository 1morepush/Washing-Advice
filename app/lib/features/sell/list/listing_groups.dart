/// The Sell tab's listings sorted into the three sections it shows.
///
/// Order within a section is the order the listings arrive in, which is the
/// repository's: most recently changed first. A listing that was just edited is
/// the one somebody is working on, and it should not drop below older ones for
/// being a draft.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

import 'listing_money.dart';

final class ListingGroups {
  ListingGroups._({
    required List<Listing> drafts,
    required List<Listing> listed,
    required List<Listing> sold,
  }) : drafts = List.unmodifiable(drafts),
       listed = List.unmodifiable(listed),
       sold = List.unmodifiable(sold);

  /// [all] split by what has become of each.
  factory ListingGroups.of(Iterable<Listing> all) {
    final drafts = <Listing>[];
    final listed = <Listing>[];
    final sold = <Listing>[];

    for (final listing in all) {
      switch (listing.status) {
        case ListingStatus.draft:
          drafts.add(listing);
        case ListingStatus.listed:
          listed.add(listing);
        case ListingStatus.sold:
          sold.add(listing);
      }
    }
    return ListingGroups._(drafts: drafts, listed: listed, sold: sold);
  }

  final List<Listing> drafts;
  final List<Listing> listed;
  final List<Listing> sold;

  bool get isEmpty => drafts.isEmpty && listed.isEmpty && sold.isEmpty;

  /// What the sales add up to.
  SoldTotals get soldTotals => SoldTotals.of(sold);
}

/// What was sold, and what Depop's fees left of it.
final class SoldTotals {
  const SoldTotals({
    required this.count,
    required this.netCents,
    required this.withoutPrice,
  });

  /// Adds up [sold], taking each net from the core's fees.
  factory SoldTotals.of(Iterable<Listing> sold) {
    var count = 0;
    var net = 0;
    var withoutPrice = 0;

    for (final listing in sold) {
      count++;
      if (listing.soldPriceCents case final int paid) {
        net += netOf(paid);
      } else {
        withoutPrice++;
      }
    }
    return SoldTotals(count: count, netCents: net, withoutPrice: withoutPrice);
  }

  /// How many have sold.
  final int count;

  /// What the sales with a price left after fees, in US cents.
  final int netCents;

  /// How many sold without a price being recorded.
  ///
  /// Counted as sold and added to nothing, and said so in [summary]: a total
  /// that quietly left a sale out would read as less than the person took.
  final int withoutPrice;

  /// `3 sold · you got $84.20 after fees`.
  String get summary {
    final parts = [
      '$count sold',
      'you got ${formatUsd(netCents)} after fees',
      if (withoutPrice > 0)
        withoutPrice == 1
            ? '1 has no price recorded'
            : '$withoutPrice have no price recorded',
    ];
    return parts.join(' · ');
  }
}
