/// What gets worn together.
///
/// The outfit builder accepts a [RelationshipGraph] and has had nothing to
/// feed it: the app proposes outfits and records wears, but nothing connected
/// the two. This is the connection, and it is a *projection* rather than a
/// store — no new table, no second source of truth to keep in step, and it
/// applies retroactively to history the app already has. Someone who has been
/// logging wears for a month gets a graph the moment this ships.
///
/// The inference is deliberately narrow. Wearing two things on the same day is
/// weak evidence; wearing them on the same day repeatedly is a pattern. So a
/// pair needs to recur before it becomes an edge at all, and the strength is a
/// *conditional* rate rather than a raw count — "when you wear the blazer, you
/// wear those trousers four times in five" — which does not reward a garment
/// merely for being worn often.
library;

import '../shared/ids.dart';
import '../wardrobe/model/relationship.dart';
import 'wardrobe_event.dart';

/// How long a run of wears counts as one occasion.
///
/// Wears are logged in batches — someone opens the app in the evening and taps
/// four things — so the window has to be generous enough to cover that. It is
/// measured from the *start* of a run rather than between consecutive events,
/// which stops a chain of eleven-hour gaps from merging a fortnight into one
/// enormous outfit.
const Duration defaultCoWearWindow = Duration(hours: 12);

/// How often a pair must recur before it is believed.
///
/// Two is the smallest number that can distinguish a pattern from a
/// coincidence, and the cost of getting this wrong is asymmetric: a missing
/// edge slightly weakens a suggestion, while a spurious one actively pushes a
/// bad pairing up the list.
const int defaultMinimumCoWears = 2;

/// Shrinks the rate toward zero when there is little evidence for it.
///
/// A bare hit rate cannot tell two observations from twenty: worn together
/// twice out of two is 100%, and so is twenty out of twenty, though only one
/// of them is a habit. Adding a constant to the denominator makes a small
/// sample sit below a large one at the same rate — two out of two becomes
/// 0.67, twenty out of twenty 0.95 — while leaving the rate itself the
/// dominant term. One phantom non-occurrence is the gentlest correction that
/// does the job.
const double _evidencePrior = 1;

/// Derives `wornWith` links from wear history.
abstract final class CoWearProjection {
  /// Folds [events] into a graph of what is worn with what.
  ///
  /// Only [ItemWorn] matters here; everything else is ignored, so a whole log
  /// can be passed in. Order is taken from [WardrobeEvent.occurredAt], not
  /// from the argument order, so a retrospectively logged wear still lands in
  /// the right occasion.
  static RelationshipGraph graphFrom(
    Iterable<WardrobeEvent> events, {
    Duration window = defaultCoWearWindow,
    int minimumCoWears = defaultMinimumCoWears,
  }) {
    final wears = <ItemWorn>[
      for (final event in events)
        if (event is ItemWorn) event,
    ]..sort((x, y) => x.occurredAt.compareTo(y.occurredAt));

    if (wears.isEmpty) return RelationshipGraph.empty();

    final wearCounts = <ItemId, int>{};
    final together = <_Pair, int>{};

    for (final occasion in _occasions(wears, window)) {
      for (final id in occasion) {
        wearCounts[id] = (wearCounts[id] ?? 0) + 1;
      }

      final ids = occasion.toList();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final pair = _Pair(ids[i], ids[j]);
          together[pair] = (together[pair] ?? 0) + 1;
        }
      }
    }

    final edges = <ItemRelationship>[];
    for (final entry in together.entries) {
      if (entry.value < minimumCoWears) continue;

      // Conditional on the rarer of the two. A garment worn every day would
      // otherwise look strongly linked to everything simply by being present,
      // which is the opposite of what the builder needs: the interesting edge
      // is the one that says *these two go together*, not *this one is worn a
      // lot*.
      final floor = wearCounts[entry.key.a]! < wearCounts[entry.key.b]!
          ? wearCounts[entry.key.a]!
          : wearCounts[entry.key.b]!;

      edges.add(
        ItemRelationship(
          from: entry.key.a,
          to: entry.key.b,
          kind: RelationKind.wornWith,
          strength: entry.value / (floor + _evidencePrior),
        ),
      );
    }

    // Sorted so the same history always produces the same graph. Map iteration
    // order is stable within a run but not across them, and a builder whose
    // suggestions reshuffle between launches on identical data looks broken.
    edges.sort((x, y) {
      final byStrength = y.strength.compareTo(x.strength);
      if (byStrength != 0) return byStrength;
      return '${x.from.value}|${x.to.value}'.compareTo(
        '${y.from.value}|${y.to.value}',
      );
    });

    return RelationshipGraph(edges);
  }

  /// Splits sorted wears into runs, each no longer than [window].
  ///
  /// An item worn twice in one run counts once: a duplicate tap should not
  /// make a pair look twice as strong.
  static List<Set<ItemId>> _occasions(List<ItemWorn> wears, Duration window) {
    final occasions = <Set<ItemId>>[];
    DateTime? openedAt;
    var current = <ItemId>{};

    for (final wear in wears) {
      if (openedAt == null || wear.occurredAt.difference(openedAt) > window) {
        if (current.isNotEmpty) occasions.add(current);
        current = <ItemId>{};
        openedAt = wear.occurredAt;
      }
      current.add(wear.itemId);
    }
    if (current.isNotEmpty) occasions.add(current);

    return occasions;
  }
}

/// An unordered pair of item ids, so `(a, b)` and `(b, a)` are one key.
final class _Pair {
  _Pair(ItemId x, ItemId y)
      : a = x.value.compareTo(y.value) <= 0 ? x : y,
        b = x.value.compareTo(y.value) <= 0 ? y : x;

  final ItemId a;
  final ItemId b;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _Pair && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}
