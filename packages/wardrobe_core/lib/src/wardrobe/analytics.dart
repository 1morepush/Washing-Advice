/// What a wardrobe adds up to.
///
/// In the core rather than in the app because these are *domain* questions, not
/// display ones: what counts as neglected, whether a garment has earned its
/// price, which fibres a wardrobe is actually made of. A screen that computed
/// them would be deciding them, and two screens would eventually decide
/// differently.
///
/// Everything here is derived from data the app already holds. Nothing is
/// stored, so there is no cache to invalidate and no figure that can drift out
/// of step with the items it describes.
library;

import 'model/fabric.dart';
import 'model/item_attributes.dart';
import 'model/item_color.dart';
import 'model/wardrobe_item.dart';

/// One garment and a number attached to it.
final class RankedItem {
  const RankedItem({required this.item, required this.value});

  final WardrobeItem item;

  /// The figure this ranking is by — wears, cost per wear, days idle.
  final double value;

  @override
  String toString() => '${item.displayName}: $value';
}

/// A count of items sharing some attribute.
final class Tally<T> {
  const Tally({required this.key, required this.count, required this.share});

  final T key;
  final int count;

  /// Fraction of the wardrobe, `0..1`.
  final double share;

  @override
  String toString() => '$key: $count (${(share * 100).round()}%)';
}

/// A read-only view over a wardrobe's *contents*.
///
/// Distinct from [WardrobeAnalytics] in the events context, which answers
/// usage questions by replaying the log. This reads items — their attributes,
/// and the counters cached on them — and so can answer things the log cannot:
/// what the wardrobe is made of, which piles it would sort into, how much of
/// it the app can actually advise on.
///
/// Where both can answer (most worn, never worn), they agree as long as the
/// counters are in step with the log, which `WardrobeRecorder` maintains on
/// every write and `SyncEngine` rebuilds after a merge. The log remains the
/// authority; this is the fast path over its projection.
final class WardrobeSummary {
  WardrobeSummary(List<WardrobeItem> items, {DateTime? asOf})
      : _items = List.unmodifiable(items),
        _asOf = asOf ?? DateTime.now();

  final List<WardrobeItem> _items;
  final DateTime _asOf;

  int get itemCount => _items.length;

  bool get isEmpty => _items.isEmpty;

  int get totalWears =>
      _items.fold(0, (sum, item) => sum + item.usage.timesWorn);

  int get totalWashes =>
      _items.fold(0, (sum, item) => sum + item.usage.timesWashed);

  /// Items never worn once.
  ///
  /// The "why do I own this?" figure, and the one most likely to change
  /// behaviour. Deliberately *not* filtered by how recently they were added:
  /// something bought yesterday belongs here too, and hiding it until an
  /// arbitrary grace period elapses would just delay the observation.
  List<WardrobeItem> get neverWorn => [
        for (final item in _items)
          if (item.usage.timesWorn == 0) item,
      ];

  /// Items not worn in [days], excluding those never worn at all.
  ///
  /// Kept separate from [neverWorn] because they prompt different actions: a
  /// garment worn twice last winter is seasonal, while one never worn in two
  /// years of ownership is a mistake.
  List<RankedItem> idleFor(int days) {
    final cutoff = _asOf.subtract(Duration(days: days));
    final idle = <RankedItem>[
      for (final item in _items)
        if (item.usage.lastWornAt case final DateTime worn)
          if (worn.isBefore(cutoff))
            RankedItem(
              item: item,
              value: _asOf.difference(worn).inDays.toDouble(),
            ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return idle;
  }

  /// Most-worn first.
  List<RankedItem> get mostWorn {
    final ranked = <RankedItem>[
      for (final item in _items)
        if (item.usage.timesWorn > 0)
          RankedItem(item: item, value: item.usage.timesWorn.toDouble()),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return ranked;
  }

  /// Best value first — the lowest cost per wear.
  ///
  /// Only items with both a price and a wear, because the statistic is
  /// undefined otherwise. Showing "unknown" rows in a value ranking would bury
  /// the comparison the ranking exists to make.
  List<RankedItem> get bestValue {
    final ranked = <RankedItem>[
      for (final item in _items)
        if (item.costPerWear case final double cost)
          RankedItem(item: item, value: cost),
    ]..sort((a, b) => a.value.compareTo(b.value));
    return ranked;
  }

  /// Worst value first, which is the same list reversed.
  List<RankedItem> get worstValue => bestValue.reversed.toList();

  /// Total spend per currency, in minor units.
  ///
  /// Keyed by currency rather than summed, because converting between them
  /// needs a rate the domain has no business inventing — the same choice
  /// `WardrobeAnalytics.totalSpend` makes over the event log, kept identical
  /// here so the two cannot present different answers.
  Map<String, int> get totalSpend {
    final totals = <String, int>{};
    for (final item in _items) {
      if (item.purchase case final purchase?) {
        totals.update(
          purchase.currencyCode,
          (value) => value + purchase.priceMinorUnits,
          ifAbsent: () => purchase.priceMinorUnits,
        );
      }
    }
    return totals;
  }

  /// How the wardrobe divides by category.
  List<Tally<ItemCategory>> get byCategory =>
      _tally([for (final item in _items) item.category]);

  /// How it divides by laundry colour class — the piles it would sort into.
  List<Tally<ColorClass>> get byColorClass =>
      _tally([for (final item in _items) item.colorClass]);

  /// Which fibres the wardrobe is actually made of.
  ///
  /// Counted per *item*, not per percentage point: an 80/20 cotton-polyester
  /// tee is one cotton item and one polyester item, because the question being
  /// asked is "how much of my wardrobe involves this fibre", not "how many
  /// grams of it do I own".
  ///
  /// Uses the same notability threshold as search, so the answer here matches
  /// what filtering by that fibre returns. Two different definitions of "is
  /// made of" would be worse than either alone.
  List<Tally<Fiber>> get byFiber {
    final keys = <Fiber>[];
    for (final item in _items) {
      final composition = item.composition.value;
      for (final fiber in composition.fibers) {
        if (composition.isDescribedBy(fiber)) keys.add(fiber);
      }
    }
    return _tally(keys);
  }

  /// Where the wardrobe was made.
  ///
  /// Counted only over garments whose label actually said, and
  /// [withoutCountry] reports the rest. A chart that folded the unknowns into
  /// the total would make a wardrobe with three read labels look like it came
  /// overwhelmingly from one country.
  ///
  /// Grouped on the printed words, case-insensitively, so "Portugal" and
  /// "PORTUGAL" are one entry — but nothing tries to map "PRC" onto "China".
  /// That needs a table nobody has written, and a wrong mapping states a fact
  /// about a garment that its label does not.
  List<Tally<String>> get byCountryOfOrigin {
    final display = <String, String>{};
    final keys = <String>[];

    for (final item in _items) {
      if (item.countryOfOrigin?.value.trim() case final String country
          when country.isNotEmpty) {
        final key = country.toLowerCase();
        // The first spelling seen wins, so the chart shows a real label rather
        // than a lower-cased one.
        display.putIfAbsent(key, () => country);
        keys.add(key);
      }
    }

    // Re-keyed to the printed spelling. The share is left as `_tally` worked
    // it out: against the whole wardrobe, so the unknowns account for the
    // remainder rather than being normalised away.
    return [
      for (final tally in _tally(keys))
        Tally(
          key: display[tally.key] ?? tally.key,
          count: tally.count,
          share: tally.share,
        ),
    ];
  }

  /// Garments whose label never said where they were made.
  ///
  /// Reported beside [byCountryOfOrigin] rather than hidden, because on a
  /// young wardrobe it is most of them and the chart means little without it.
  int get withoutCountry => [
        for (final item in _items)
          if (item.countryOfOrigin == null) item,
      ].length;

  /// Items whose care is still a guess.
  ///
  /// The actionable backlog: each one is a label away from being sortable, and
  /// until then the sorter refuses to place it in a load.
  List<WardrobeItem> get needingCareTagScan => [
        for (final item in _items)
          if (item.needsCareTagScan) item,
      ];

  /// Share of the wardrobe the app can sort with confidence, `0..1`.
  ///
  /// The single number that says how useful a pile scan will be. A wardrobe
  /// where most items still need a label reading will produce mostly
  /// "identify this first" rather than loads, and saying so beforehand is
  /// better than letting someone discover it at the machine.
  double get readiness {
    final launderable = [
      for (final item in _items)
        if (item.isLaunderable) item,
    ];
    if (launderable.isEmpty) return 1;

    final ready = launderable.where((item) => !item.needsCareTagScan).length;
    return ready / launderable.length;
  }

  List<Tally<T>> _tally<T>(List<T> keys) {
    if (keys.isEmpty) return const [];

    final counts = <T, int>{};
    for (final key in keys) {
      counts[key] = (counts[key] ?? 0) + 1;
    }

    // Shares are of the *item count*, not of the key count, so a wardrobe
    // where every item is one category reads as 100% rather than being
    // normalised against a total that includes items counted twice.
    final total = _items.length;
    final tallies = [
      for (final entry in counts.entries)
        Tally(
          key: entry.key,
          count: entry.value,
          share: total == 0 ? 0 : entry.value / total,
        ),
    ]..sort((a, b) => b.count.compareTo(a.count));
    return tallies;
  }
}
