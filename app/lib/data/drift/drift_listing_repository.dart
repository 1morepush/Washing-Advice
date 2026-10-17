/// [ListingRepository] over Drift.
///
/// Every operation here must mean exactly what `InMemoryListingRepository`
/// means. That is not left to care: `runListingRepositoryContractTests` from
/// the core runs against this class, so a divergence is a failing test rather
/// than something a person finds on the Sell tab.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'database.dart';

class DriftListingRepository implements ListingRepository {
  DriftListingRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Listing>> all() async => [
    for (final row in await _newestFirst().get()) _decode(row),
  ];

  @override
  Future<Listing?> byId(ListingId id) async {
    final row = await (_db.select(
      _db.listings,
    )..where((t) => t.id.equals(id.value))).getSingleOrNull();
    return row == null ? null : _decode(row);
  }

  @override
  Future<List<Listing>> forItem(ItemId id) async {
    // A listing with no garment has a null `item_id`, and `= 'x'` is never true
    // of a null, so those never match, which is what the contract asks for.
    final rows = await (_newestFirst()..where((t) => t.itemId.equals(id.value)))
        .get();
    return [for (final row in rows) _decode(row)];
  }

  @override
  Future<void> save(Listing listing) =>
      _db.into(_db.listings).insertOnConflictUpdate(listingRowFor(listing));

  @override
  Future<void> delete(ListingId id) =>
      (_db.delete(_db.listings)..where((t) => t.id.equals(id.value))).go();

  @override
  Stream<List<Listing>> watchAll() => _newestFirst().watch().map(
    (rows) => [for (final row in rows) _decode(row)],
  );

  /// The base query, ordered the way the contract requires.
  ///
  /// Most recently updated first, with the id as a tie-break — without which
  /// two listings saved at the same instant come back in whatever order SQLite
  /// feels like, and a list that reshuffles between reads looks broken.
  SimpleSelectStatement<$ListingsTable, ListingRow> _newestFirst() =>
      _db.select(_db.listings)..orderBy([
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id),
      ]);

  Listing _decode(ListingRow row) =>
      Listing.fromJson(jsonDecode(row.payload) as Map<String, Object?>);
}
