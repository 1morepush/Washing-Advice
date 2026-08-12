/// Packing for a trip.
///
/// Every packing app answers "what should I bring". This one can answer the
/// question that actually goes wrong: **what happens to it while you are
/// away**. A suitcase of hand-wash silk on a two-week trip is a bad suitcase
/// however good each garment is, and nothing in a wardrobe list will tell you
/// so. Because the care model is already in the core, packing can.
///
/// The quantities are ordinary packing arithmetic, stated as a table rather
/// than buried in conditionals so they can be read, argued with and changed:
/// a top a day, a bottom every few days, underwear plus a spare. When laundry
/// is available mid-trip, every quota is capped by the wash interval instead —
/// which is the whole reason to do laundry on a trip, and the difference
/// between a carry-on and a hold bag.
library;

import 'dart:math' as math;

import '../care/model/care_symbols.dart';
import '../wardrobe/model/item_attributes.dart';
import '../wardrobe/model/item_color.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'model/occasion.dart';

/// What the trip demands.
final class TripSpec {
  const TripSpec({
    required this.days,
    this.season = Season.allSeason,
    this.occasions = const {Occasion.everyday},
    this.laundryAvailable = false,
    this.washEveryDays = 4,
  })  : assert(days > 0, 'a trip is at least one day'),
        assert(washEveryDays > 0, 'a wash interval is at least one day');

  final int days;
  final Season season;

  /// Everything the trip has to cover. A work trip with a dinner is
  /// `{work, formal}`, and both need clothes.
  final Set<Occasion> occasions;

  /// Whether there is a machine at the other end.
  final bool laundryAvailable;

  /// How often the user is willing to run one.
  final int washEveryDays;

  /// The number of days one set of clothes has to stretch over.
  ///
  /// Without laundry that is the whole trip. With it, one wash interval plus a
  /// day of slack, because clothes are not wearable while they are in the
  /// machine.
  int get cycleDays =>
      laundryAvailable ? math.min(days, washEveryDays + 1) : days;
}

/// One packed thing, and why it is in the bag.
final class PackedItem {
  const PackedItem({
    required this.item,
    required this.category,
    required this.reason,
  });

  final WardrobeItem item;
  final ItemCategory category;

  /// Plain English: what this is covering.
  final String reason;

  @override
  String toString() => '${item.displayName} — $reason';
}

/// Something the trip needs that the wardrobe cannot supply.
final class PackingGap {
  const PackingGap({
    required this.category,
    required this.wanted,
    required this.found,
  });

  final ItemCategory category;
  final int wanted;
  final int found;

  int get missing => wanted - found;

  String get message => found == 0
      ? 'Nothing in the wardrobe fits ${category.label.toLowerCase()} '
          'for this trip'
      : 'Only $found of $wanted ${category.label.toLowerCase()} available';

  @override
  String toString() => message;
}

/// The packed bag.
final class PackingList {
  const PackingList({
    required this.trip,
    required this.items,
    required this.gaps,
    required this.notes,
  });

  final TripSpec trip;
  final List<PackedItem> items;

  /// Where the wardrobe fell short. Reported rather than silently padded,
  /// because a short packing list that looks complete is how people arrive
  /// somewhere without socks.
  final List<PackingGap> gaps;

  /// Warnings about what happens to these clothes on the trip.
  final List<String> notes;

  int get count => items.length;

  bool get isComplete => gaps.isEmpty;

  /// Rough packed weight in grams, using typical dry weights.
  ///
  /// Approximate by construction — the wardrobe stores what a garment of this
  /// type usually weighs, not what this one does — so it is for comparing two
  /// packing lists, not for an airline's scales.
  double get estimatedWeightGrams => items.fold(
      0, (sum, packed) => sum + packed.item.type.value.typicalWeightGrams);

  @override
  String toString() =>
      'PackingList(${items.length} items, ${gaps.length} gaps)';
}

/// Builds a packing list from a wardrobe.
final class PackingPlanner {
  const PackingPlanner();

  PackingList plan(List<WardrobeItem> wardrobe, TripSpec trip) {
    final available = [
      for (final item in wardrobe)
        if (item.lifecycle.isWearable && _suitsSeason(item, trip.season))
          if (_suitsAnyOccasion(item, trip.occasions)) item,
    ];

    final packed = <PackedItem>[];
    final gaps = <PackingGap>[];
    final used = <String>{};

    for (final entry in _quotas(trip).entries) {
      final category = entry.key;
      final wanted = entry.value;
      if (wanted == 0) continue;

      final candidates = [
        for (final item in available)
          if (item.category == category && !used.contains(item.id.value)) item,
      ]..sort(
          (a, b) => _versatility(b, trip).compareTo(_versatility(a, trip)),
        );

      final chosen = candidates.take(wanted).toList();
      for (final item in chosen) {
        used.add(item.id.value);
        packed.add(
          PackedItem(
            item: item,
            category: category,
            reason: _reasonFor(category, wanted, trip),
          ),
        );
      }

      if (chosen.length < wanted) {
        gaps.add(
          PackingGap(
            category: category,
            wanted: wanted,
            found: chosen.length,
          ),
        );
      }
    }

    return PackingList(
      trip: trip,
      items: packed,
      gaps: gaps,
      notes: _notes(packed, trip),
    );
  }

  bool _suitsSeason(WardrobeItem item, Season season) =>
      season == Season.allSeason ||
      item.seasons.isEmpty ||
      item.seasons.contains(season) ||
      item.seasons.contains(Season.allSeason);

  bool _suitsAnyOccasion(WardrobeItem item, Set<Occasion> occasions) {
    // Underwear, socks and sleepwear serve no occasion and are needed on every
    // trip regardless, so they bypass the filter rather than being tagged for
    // every occasion in the list.
    if (_alwaysNeeded.contains(item.category)) return true;
    return occasions.any(
      (o) => item.tags.contains(o.tag) || o.suits(item.type.value),
    );
  }

  /// How many of each category the trip needs.
  Map<ItemCategory, int> _quotas(TripSpec trip) {
    final cycle = trip.cycleDays;
    final winter = trip.season == Season.winter;

    return {
      // A clean top every day is the one quantity nobody economises on.
      ItemCategory.top: cycle,
      // Bottoms are worn several times between washes, which is why a week
      // away does not need seven pairs of trousers.
      ItemCategory.bottom: math.max(1, (cycle / 3).ceil()),
      ItemCategory.underwear: cycle + 1,
      ItemCategory.legwear: cycle + 1,
      ItemCategory.sleepwear: trip.days >= 3 ? 1 : 0,
      // One layer, two if it is winter and the trip is long enough that one
      // getting soaked would matter.
      ItemCategory.outerwear: winter && trip.days > 7 ? 2 : 1,
      // A second pair only earns its space when the trip has a second kind of
      // day in it — shoes are the heaviest thing in any bag.
      ItemCategory.footwear:
          trip.occasions.length > 1 || trip.occasions.contains(Occasion.active)
              ? 2
              : 1,
      ItemCategory.activewear: trip.occasions.contains(Occasion.active)
          ? math.max(1, (cycle / 2).ceil())
          : 0,
    };
  }

  /// How useful an item is *in a suitcase*, which is not the same as how good
  /// it is at home.
  ///
  /// A neutral goes with more of what else is packed, so it earns its space
  /// several times over. Weight is a real cost here and nowhere else. And
  /// something that cannot go in a machine is a liability on a trip with
  /// laundry in the plan — the one place the care model changes the answer.
  double _versatility(WardrobeItem item, TripSpec trip) {
    var score = 0.5;

    if (item.colors.value.dominant case final ItemColor color) {
      if (color.isNeutral) score += 0.2;
    }

    // Suits more of the trip than the minimum.
    final covered = trip.occasions
        .where((o) => item.tags.contains(o.tag) || o.suits(item.type.value))
        .length;
    if (covered > 1) score += 0.1;

    if (item.isFavorite) score += 0.1;

    final care = item.effectiveCare;
    if (!care.isMachineWashable) score -= trip.laundryAvailable ? 0.25 : 0.1;
    if (care.requiresIsolation) score -= 0.1;

    // Lighter is better, scaled against a kilo so the adjustment stays small:
    // a coat should still be packed when the trip needs a coat.
    score -= (item.type.value.typicalWeightGrams / 1000) * 0.05;

    return score;
  }

  String _reasonFor(ItemCategory category, int quantity, TripSpec trip) =>
      switch (category) {
        ItemCategory.top => 'One per day',
        ItemCategory.bottom =>
          'Covers ${(trip.cycleDays / quantity).ceil()} days',
        ItemCategory.underwear ||
        ItemCategory.legwear =>
          'One per day, plus a spare',
        ItemCategory.sleepwear => 'For the nights',
        ItemCategory.outerwear => 'The layer',
        ItemCategory.footwear => 'For ${_occasionList(trip.occasions)}',
        _ => 'For ${_occasionList(trip.occasions)}',
      };

  String _occasionList(Set<Occasion> occasions) =>
      occasions.map((o) => o.label.toLowerCase()).join(' and ');

  /// What the trip will do to these clothes.
  List<String> _notes(List<PackedItem> packed, TripSpec trip) {
    final notes = <String>[];
    final launderable = [
      for (final packedItem in packed)
        if (packedItem.item.isLaunderable) packedItem.item,
    ];

    if (trip.laundryAvailable) {
      final awkward = [
        for (final item in launderable)
          if (item.effectiveCare.wash.method != WashMethod.machine) item,
      ];
      if (awkward.isNotEmpty) {
        notes.add(
          '${awkward.length} packed ${awkward.length == 1 ? 'item needs' : 'items need'} '
          'hand washing or professional care, which is awkward away from home: '
          '${awkward.map((i) => i.displayName).join(', ')}',
        );
      }

      final classes = {for (final item in launderable) item.colorClass};
      if (classes.length > 2) {
        notes.add(
          'Washing this lot properly means ${classes.length} separate loads '
          '(${classes.map((c) => c.label.toLowerCase()).join(', ')}). '
          'Dropping one color would make it fewer.',
        );
      }
    } else if (trip.days > trip.washEveryDays) {
      notes.add(
        'No laundry planned for a ${trip.days}-day trip, so everything packed '
        'has to last the whole time.',
      );
    }

    final needsScan = [
      for (final item in launderable)
        if (item.needsCareTagScan) item,
    ];
    if (needsScan.isNotEmpty) {
      notes.add(
        '${needsScan.length} packed '
        '${needsScan.length == 1 ? 'item has' : 'items have'} no confirmed care '
        'label, so the advice above is a guess for '
        '${needsScan.length == 1 ? 'it' : 'them'}.',
      );
    }

    return notes;
  }
}

/// Categories needed on every trip whatever it is for.
const Set<ItemCategory> _alwaysNeeded = {
  ItemCategory.underwear,
  ItemCategory.legwear,
  ItemCategory.sleepwear,
};
