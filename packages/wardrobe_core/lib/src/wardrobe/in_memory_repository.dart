/// An in-memory [WardrobeRepository].
///
/// Two jobs, and the second is the important one.
///
/// It is a test double, so the domain can be exercised without a database. But
/// it is also the **executable specification of every filter**: `_matches`
/// below is what a query is defined to mean, in one readable place. The Drift
/// implementation is checked against this by a shared test suite, so a `WHERE`
/// clause that disagrees is a bug in the SQL rather than an open question about
/// intent.
library;

import 'dart:async';

import '../shared/ids.dart';
import 'model/wardrobe_item.dart';
import 'query.dart';
import 'repository.dart';

/// Holds the wardrobe in a map.
final class InMemoryWardrobeRepository implements WardrobeRepository {
  InMemoryWardrobeRepository([Iterable<WardrobeItem> initial = const []]) {
    for (final item in initial) {
      _items[item.id] = item;
    }
  }

  final Map<ItemId, WardrobeItem> _items = {};
  final List<StreamController<List<WardrobeItem>>> _watchers = [];
  final Map<StreamController<List<WardrobeItem>>, WardrobeQuery> _queries = {};

  int get length => _items.length;

  @override
  Future<WardrobeItem?> byId(ItemId id) async => _items[id];

  @override
  Future<List<WardrobeItem>> query(WardrobeQuery query) async =>
      _apply(query, paged: true);

  @override
  Future<int> count(WardrobeQuery query) async =>
      _apply(query, paged: false).length;

  @override
  Future<void> save(WardrobeItem item) async {
    _items[item.id] = item;
    _notify();
  }

  @override
  Future<void> saveAll(Iterable<WardrobeItem> items) async {
    for (final item in items) {
      _items[item.id] = item;
    }
    _notify();
  }

  @override
  Future<void> delete(ItemId id) async {
    _items.remove(id);
    _notify();
  }

  @override
  Stream<List<WardrobeItem>> watch(WardrobeQuery query) {
    late final StreamController<List<WardrobeItem>> controller;

    // Single-subscription, not broadcast. Each call already returns its own
    // controller for one subscriber, and the difference matters: a broadcast
    // controller delivers only to listeners attached at the moment of the
    // `add`, so the initial snapshot pushed from `onListen` is dropped unless
    // the consumer subscribes in exactly the right way. A single-subscription
    // controller buffers it instead, and every consumer gets the current
    // contents whatever order it happens to listen in.
    //
    // This was not theoretical: it left the wardrobe screen showing a spinner
    // forever, because the stream it was watching never produced a first
    // value.
    controller = StreamController<List<WardrobeItem>>(
      onListen: () => controller.add(_apply(query, paged: true)),
      onCancel: () {
        _watchers.remove(controller);
        _queries.remove(controller);
      },
    );
    _watchers.add(controller);
    _queries[controller] = query;
    return controller.stream;
  }

  @override
  Future<List<String>> knownBrands() async {
    final brands = <String>{
      for (final item in _items.values)
        if (item.brand?.value case final String brand) brand,
    };
    return brands.toList()..sort();
  }

  /// Releases every watcher. Call when discarding the repository.
  Future<void> dispose() async {
    for (final controller in [..._watchers]) {
      await controller.close();
    }
    _watchers.clear();
    _queries.clear();
  }

  void _notify() {
    for (final controller in _watchers) {
      if (controller.isClosed) continue;
      controller.add(_apply(_queries[controller]!, paged: true));
    }
  }

  List<WardrobeItem> _apply(WardrobeQuery query, {required bool paged}) {
    final matched = [
      for (final item in _items.values)
        if (_matches(item, query)) item,
    ]..sort((a, b) => _compare(a, b, query.sort));

    if (!paged) return matched;

    final from = query.offset.clamp(0, matched.length);
    final to = query.limit == null
        ? matched.length
        : (from + query.limit!).clamp(from, matched.length);
    return matched.sublist(from, to);
  }

  /// What a query *means*. The Drift implementation must agree with this.
  bool _matches(WardrobeItem item, WardrobeQuery query) {
    if (query.kinds.isNotEmpty && !query.kinds.contains(item.kind))
      return false;
    if (query.categories.isNotEmpty &&
        !query.categories.contains(item.category)) {
      return false;
    }
    if (query.types.isNotEmpty && !query.types.contains(item.type.value)) {
      return false;
    }
    if (query.colorClasses.isNotEmpty &&
        !query.colorClasses.contains(item.colorClass)) {
      return false;
    }
    if (query.lifecycleStates.isNotEmpty &&
        !query.lifecycleStates.contains(item.lifecycle)) {
      return false;
    }

    if (query.brands.isNotEmpty) {
      final brand = item.brand?.value.toLowerCase();
      if (brand == null) return false;
      final wanted = {for (final b in query.brands) b.toLowerCase()};
      if (!wanted.contains(brand)) return false;
    }

    // Seasons match on overlap: a query for summer should find an all-season
    // item, because that item is genuinely wearable in summer.
    if (query.seasons.isNotEmpty &&
        item.seasons.intersection(query.seasons).isEmpty) {
      return false;
    }

    // Fibre matches when the garment is genuinely described by it. A trace of
    // 2% elastane is not what someone means by "show me my elastane clothes";
    // 20% polyester in a cotton tee is. Note this is *not* the care threshold —
    // see `FabricComposition.isDescribedBy`.
    if (query.fibers.isNotEmpty) {
      final composition = item.composition.value;
      if (!query.fibers.any(composition.isDescribedBy)) return false;
    }

    if (query.tags.isNotEmpty && item.tags.intersection(query.tags).isEmpty) {
      return false;
    }

    if (query.favouritesOnly && !item.isFavorite) return false;
    if (query.neverWorn && !item.usage.hasNeverBeenWorn) return false;
    if (query.needsCareTagScan && !item.needsCareTagScan) return false;

    if (query.wornSince case final DateTime since) {
      final lastWorn = item.usage.lastWornAt;
      if (lastWorn == null || lastWorn.isBefore(since)) return false;
    }

    if (query.notWornSince case final DateTime since) {
      // Never worn counts as not worn since — it is the extreme case of the
      // thing the filter is looking for, not an exception to it.
      final lastWorn = item.usage.lastWornAt;
      if (lastWorn != null && !lastWorn.isBefore(since)) return false;
    }

    if (query.text?.trim() case final String text when text.isNotEmpty) {
      final needle = text.toLowerCase();
      final haystack = [
        item.name,
        item.brand?.value ?? '',
        item.distinguishingText ?? '',
        item.type.value.label,
        item.notes ?? '',
        ...item.tags,
      ].join(' ').toLowerCase();
      if (!haystack.contains(needle)) return false;
    }

    return true;
  }

  int _compare(WardrobeItem a, WardrobeItem b, WardrobeSort sort) =>
      switch (sort) {
        WardrobeSort.recentlyAdded => b.addedAt.compareTo(a.addedAt),
        WardrobeSort.nameAscending =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
        WardrobeSort.mostWorn => b.usage.timesWorn.compareTo(a.usage.timesWorn),
        WardrobeSort.recentlyWorn => _byDate(
            a.usage.lastWornAt,
            b.usage.lastWornAt,
            newestFirst: true,
          ),
        WardrobeSort.leastRecentlyWorn => _byDate(
            a.usage.lastWornAt,
            b.usage.lastWornAt,
            newestFirst: false,
          ),
        WardrobeSort.costPerWear => _byCost(a, b),
      };

  /// Orders by date, with nulls last in both directions.
  ///
  /// "Never worn" is not a very old date — sorting it as one would bury the
  /// most-worn items under everything untouched, in a view meant to surface
  /// what gets used.
  int _byDate(DateTime? a, DateTime? b, {required bool newestFirst}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return newestFirst ? b.compareTo(a) : a.compareTo(b);
  }

  /// Cheapest per wear first, with unpriced or unworn items last.
  int _byCost(WardrobeItem a, WardrobeItem b) {
    final costA = a.costPerWear;
    final costB = b.costPerWear;
    if (costA == null && costB == null) return 0;
    if (costA == null) return 1;
    if (costB == null) return -1;
    return costA.compareTo(costB);
  }
}
