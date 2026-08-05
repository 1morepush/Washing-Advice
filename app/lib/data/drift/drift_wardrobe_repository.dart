/// [WardrobeRepository] over Drift.
///
/// Every filter here must mean exactly what `InMemoryWardrobeRepository._matches`
/// means. That is not a matter of care — `runRepositoryContractTests` from the
/// core runs against this class, so a `WHERE` clause that disagrees is a failing
/// test rather than a bug someone finds in six months.
///
/// Where a translation is subtle, the comment says which core behaviour it is
/// reproducing.
library;

import 'package:drift/drift.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'database.dart';

class DriftWardrobeRepository implements WardrobeRepository {
  DriftWardrobeRepository(this._db);

  final AppDatabase _db;

  @override
  Future<WardrobeItem?> byId(ItemId id) async {
    final row = await (_db.select(_db.items)
          ..where((t) => t.id.equals(id.value)))
        .getSingleOrNull();
    return row == null ? null : itemFrom(row);
  }

  @override
  Future<List<WardrobeItem>> query(WardrobeQuery query) async {
    final rows = await _build(query, paged: true).get();
    return [for (final row in rows) itemFrom(row)];
  }

  @override
  Future<int> count(WardrobeQuery query) async {
    final rows = await _build(query, paged: false).get();
    return rows.length;
  }

  @override
  Future<void> save(WardrobeItem item) =>
      _db.into(_db.items).insertOnConflictUpdate(rowFor(item));

  @override
  Future<void> saveAll(Iterable<WardrobeItem> items) => _db.batch((batch) {
        batch.insertAllOnConflictUpdate(
          _db.items,
          [for (final item in items) rowFor(item)],
        );
      });

  @override
  Future<void> delete(ItemId id) async {
    await (_db.delete(_db.items)..where((t) => t.id.equals(id.value))).go();
  }

  @override
  Stream<List<WardrobeItem>> watch(WardrobeQuery query) =>
      _build(query, paged: true)
          .watch()
          .map((rows) => [for (final row in rows) itemFrom(row)]);

  @override
  Future<List<String>> knownBrands() async {
    final rows = await (_db.select(_db.items)
          ..where((t) => t.brandLower.isNotNull()))
        .get();

    // Read the display-cased brand back from the payload: `brandLower` exists
    // for matching, not for showing a user "nike".
    final brands = <String>{
      for (final row in rows)
        if (itemFrom(row).brand?.value case final String brand) brand,
    };
    return brands.toList()..sort();
  }

  /// Builds the select for a query.
  SimpleSelectStatement<$ItemsTable, Item> _build(
    WardrobeQuery query, {
    required bool paged,
  }) {
    final select = _db.select(_db.items);

    if (query.kinds.isNotEmpty) {
      select.where((t) => t.kind.isIn([for (final k in query.kinds) k.name]));
    }
    if (query.categories.isNotEmpty) {
      select.where(
        (t) => t.category.isIn([for (final c in query.categories) c.name]),
      );
    }
    if (query.types.isNotEmpty) {
      select.where(
        (t) => t.itemType.isIn([for (final t2 in query.types) t2.name]),
      );
    }
    if (query.colorClasses.isNotEmpty) {
      select.where(
        (t) => t.colorClass.isIn([for (final c in query.colorClasses) c.name]),
      );
    }
    if (query.lifecycleStates.isNotEmpty) {
      select.where(
        (t) => t.lifecycle.isIn([for (final s in query.lifecycleStates) s.name]),
      );
    }

    if (query.brands.isNotEmpty) {
      // Lower-cased on both sides, matching the core's case-insensitive brand
      // comparison. An item with no brand never matches, because NULL fails
      // isIn — which is the behaviour the contract asks for.
      select.where(
        (t) => t.brandLower.isIn([for (final b in query.brands) b.toLowerCase()]),
      );
    }

    // Seasons and fibres match on *overlap*: an all-season item must appear
    // under a summer filter, because it genuinely is wearable in summer.
    if (query.seasons.isNotEmpty) {
      select.where(
        (t) => _anyPacked(t.seasons, [for (final s in query.seasons) s.name]),
      );
    }
    if (query.fibers.isNotEmpty) {
      select.where(
        (t) => _anyPacked(t.fibers, [for (final f in query.fibers) f.name]),
      );
    }
    if (query.tags.isNotEmpty) {
      select.where((t) => _anyPacked(t.tags, query.tags.toList()));
    }

    if (query.favouritesOnly) {
      select.where((t) => t.isFavorite.equals(true));
    }
    if (query.neverWorn) {
      select.where((t) => t.timesWorn.equals(0));
    }
    if (query.needsCareTagScan) {
      select.where((t) => t.needsCareTagScan.equals(true));
    }

    if (query.wornSince case final DateTime since) {
      select.where((t) => t.lastWornAt.isBiggerOrEqualValue(since));
    }
    if (query.notWornSince case final DateTime since) {
      // Never worn counts as not worn since — it is the extreme case of what
      // the filter looks for, not an exception to it. A bare `<` comparison
      // would drop NULLs and silently hide exactly the items being sought.
      select.where(
        (t) => t.lastWornAt.isNull() | t.lastWornAt.isSmallerThanValue(since),
      );
    }

    if (query.text?.trim() case final String text when text.isNotEmpty) {
      select.where((t) => t.searchText.like('%${text.toLowerCase()}%'));
    }

    select.orderBy(_ordering(query.sort));

    if (paged && query.limit != null) {
      select.limit(query.limit!, offset: query.offset);
    } else if (paged && query.offset > 0) {
      // SQLite requires a LIMIT before an OFFSET; -1 means "no limit".
      select.limit(-1, offset: query.offset);
    }

    return select;
  }

  /// Whether a packed column contains any of [values].
  Expression<bool> _anyPacked(GeneratedColumn<String> column, List<String> values) {
    final expression = column as Expression<String>;
    return values
        .map((value) => expression.like(packedPattern(value)))
        .reduce((a, b) => a | b);
  }

  List<OrderClauseGenerator<$ItemsTable>> _ordering(WardrobeSort sort) =>
      switch (sort) {
        WardrobeSort.recentlyAdded => [
            (t) => OrderingTerm(expression: t.addedAt, mode: OrderingMode.desc),
          ],
        WardrobeSort.nameAscending => [
            (t) => OrderingTerm(expression: t.name.lower()),
          ],
        WardrobeSort.mostWorn => [
            (t) =>
                OrderingTerm(expression: t.timesWorn, mode: OrderingMode.desc),
          ],
        // `nulls: last` on every date and cost ordering. Never-worn and
        // unpriced items must sort last in BOTH directions, or a view meant to
        // surface what gets used would bury it under everything untouched.
        WardrobeSort.recentlyWorn => [
            (t) => OrderingTerm(
                  expression: t.lastWornAt,
                  mode: OrderingMode.desc,
                  nulls: NullsOrder.last,
                ),
          ],
        WardrobeSort.leastRecentlyWorn => [
            (t) => OrderingTerm(
                  expression: t.lastWornAt,
                  nulls: NullsOrder.last,
                ),
          ],
        WardrobeSort.costPerWear => [
            (t) => OrderingTerm(
                  expression: t.costPerWearMinor,
                  nulls: NullsOrder.last,
                ),
          ],
      };
}
