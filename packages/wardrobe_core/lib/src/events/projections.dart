/// Projections: pure folds from the event log into answers.
///
/// Each projection is a pure function from events to a value. That makes them
/// trivially testable, and it means the counters cached on a [WardrobeItem] can
/// always be verified — and repaired — by replaying. The test suite asserts
/// exactly that: replaying an item's events reproduces its stored [UsageStats].
library;

import '../laundry/model/laundry_record.dart';
import '../shared/ids.dart';
import '../wardrobe/model/condition.dart';
import '../wardrobe/model/lifecycle.dart';
import '../wardrobe/model/ownership.dart';
import 'wardrobe_event.dart';

/// Rebuilds usage counters from events.
abstract final class UsageProjection {
  /// Folds [events] into counters for one item.
  ///
  /// Events for other items are ignored, so a whole log can be passed in
  /// safely. Order is taken from [WardrobeEvent.occurredAt] rather than from
  /// the argument order, so a retrospectively logged wash lands correctly.
  static UsageStats forItem(ItemId itemId, Iterable<WardrobeEvent> events) {
    final relevant = [
      for (final event in events)
        if (event.itemId == itemId) event,
    ]..sort((x, y) => x.occurredAt.compareTo(y.occurredAt));

    var timesWorn = 0;
    var timesWashed = 0;
    var wearsSinceWash = 0;
    DateTime? lastWornAt;
    DateTime? lastWashedAt;
    DateTime? firstWornAt;

    for (final event in relevant) {
      switch (event) {
        case ItemWorn():
          timesWorn++;
          wearsSinceWash++;
          firstWornAt ??= event.occurredAt;
          lastWornAt = event.occurredAt;
        case ItemWashed():
          timesWashed++;
          wearsSinceWash = 0;
          lastWashedAt = event.occurredAt;
        case ItemPurchased():
        case ItemAdded():
        case ItemRepaired():
        case ConditionObserved():
        case LifecycleChanged():
          break;
      }
    }

    return UsageStats(
      timesWorn: timesWorn,
      timesWashed: timesWashed,
      wearsSinceWash: wearsSinceWash,
      lastWornAt: lastWornAt,
      lastWashedAt: lastWashedAt,
      firstWornAt: firstWornAt,
    );
  }

  /// Counters for every item mentioned in [events].
  static Map<ItemId, UsageStats> forAll(Iterable<WardrobeEvent> events) {
    final ids = {for (final event in events) event.itemId};
    return {for (final id in ids) id: forItem(id, events)};
  }
}

/// Rebuilds an item's current lifecycle state.
abstract final class LifecycleProjection {
  /// The state after applying every lifecycle event, or null if the item has
  /// no recorded history at all.
  static LifecycleState? forItem(
    ItemId itemId,
    Iterable<WardrobeEvent> events,
  ) {
    final relevant = [
      for (final event in events)
        if (event.itemId == itemId) event,
    ]..sort((x, y) => x.occurredAt.compareTo(y.occurredAt));

    LifecycleState? state;
    for (final event in relevant) {
      switch (event) {
        case ItemPurchased():
          state ??= LifecycleState.purchased;
        case ItemAdded():
          state = LifecycleState.active;
        case LifecycleChanged(:final to):
          state = to;
        case ItemWorn():
        case ItemWashed():
        case ItemRepaired():
        case ConditionObserved():
          break;
      }
    }
    return state;
  }
}

/// Rebuilds the wash history of an item.
abstract final class LaundryHistoryProjection {
  /// Every recorded wash for one item, oldest first.
  static List<LaundryRecord> forItem(
    ItemId itemId,
    Iterable<WardrobeEvent> events,
  ) =>
      [
        for (final event in events)
          if (event is ItemWashed && event.itemId == itemId) event.record,
      ]..sort((x, y) => x.washedAt.compareTo(y.washedAt));

  /// How often the item is washed on average, or null with fewer than two
  /// washes to measure between.
  static Duration? averageIntervalFor(
    ItemId itemId,
    Iterable<WardrobeEvent> events,
  ) {
    final washes = forItem(itemId, events);
    if (washes.length < 2) return null;
    final span = washes.last.washedAt.difference(washes.first.washedAt);
    return Duration(
      microseconds: span.inMicroseconds ~/ (washes.length - 1),
    );
  }

  /// How many washes were hotter than the item's care allows.
  ///
  /// A direct explanation for shrinkage or fading, and the raw material for
  /// telling a user their habits are costing them clothes.
  static int washesAbove(
    ItemId itemId,
    Iterable<WardrobeEvent> events, {
    required int maxTempC,
  }) =>
      forItem(itemId, events)
          .where((record) => (record.temperatureC ?? 0) > maxTempC)
          .length;
}

/// Rebuilds an item's condition from observations.
abstract final class ConditionProjection {
  static ConditionAssessment forItem(
    ItemId itemId,
    Iterable<WardrobeEvent> events,
  ) =>
      ConditionAssessment([
        for (final event in events)
          if (event is ConditionObserved && event.itemId == itemId)
            event.observation,
      ]);
}

/// Wardrobe-wide statistics.
abstract final class WardrobeAnalytics {
  /// Items ranked by how often they were worn, most first.
  static List<({ItemId itemId, int timesWorn})> mostWorn(
    Iterable<WardrobeEvent> events, {
    int limit = 10,
  }) {
    final counts = UsageProjection.forAll(events);
    final ranked = [
      for (final entry in counts.entries)
        (itemId: entry.key, timesWorn: entry.value.timesWorn),
    ]..sort((x, y) => y.timesWorn.compareTo(x.timesWorn));
    return ranked.take(limit).toList();
  }

  /// Items owned but never worn.
  ///
  /// Needs the set of owned ids passed in, because an item with no events at
  /// all does not appear in the log — and those are precisely the ones that
  /// have never been touched.
  static List<ItemId> neverWorn(
    Iterable<ItemId> ownedIds,
    Iterable<WardrobeEvent> events,
  ) {
    final worn = {
      for (final event in events)
        if (event is ItemWorn) event.itemId,
    };
    return [
      for (final id in ownedIds)
        if (!worn.contains(id)) id
    ];
  }

  /// Cost per wear for one item, or null without a price or any wears.
  static double? costPerWear(
    ItemId itemId,
    Iterable<WardrobeEvent> events,
  ) {
    PurchaseInfo? purchase;
    for (final event in events) {
      if (event is ItemPurchased && event.itemId == itemId) {
        purchase = event.purchase;
      }
    }
    if (purchase == null) return null;
    return UsageProjection.forItem(itemId, events).costPerWear(purchase);
  }

  /// Total spend recorded across the wardrobe, in minor units per currency.
  ///
  /// Keyed by currency rather than summed into one figure: converting between
  /// currencies needs a rate the domain has no business inventing.
  static Map<String, int> totalSpend(Iterable<WardrobeEvent> events) {
    final totals = <String, int>{};
    for (final event in events) {
      if (event is! ItemPurchased) continue;
      totals.update(
        event.purchase.currencyCode,
        (value) => value + event.purchase.priceMinorUnits,
        ifAbsent: () => event.purchase.priceMinorUnits,
      );
    }
    return totals;
  }

  /// How many washes were run in total, as a proxy for laundry frequency.
  static int washCount(Iterable<WardrobeEvent> events) =>
      events.whereType<ItemWashed>().length;
}
