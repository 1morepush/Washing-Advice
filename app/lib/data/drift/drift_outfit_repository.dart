/// [OutfitRepository] over Drift.
///
/// Every operation here must mean exactly what `InMemoryOutfitRepository`
/// means. That is not left to care: `runOutfitRepositoryContractTests` from
/// the core runs against this class, so a divergence is a failing test rather
/// than something a user finds.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'database.dart';

class DriftOutfitRepository implements OutfitRepository {
  DriftOutfitRepository(this._db);

  final AppDatabase _db;

  @override
  Future<Outfit?> byId(OutfitId id) async {
    final row = await (_db.select(
      _db.outfits,
    )..where((t) => t.id.equals(id.value))).getSingleOrNull();
    return row == null ? null : _decode(row);
  }

  @override
  Future<List<Outfit>> all({Occasion? occasion}) async => [
    for (final row in await _query(occasion).get()) _decode(row),
  ];

  @override
  Future<List<Outfit>> containing(ItemId id) async {
    // Matched against the packed column with delimiters on both ends, so an id
    // cannot match another that merely ends with the same characters. The
    // delimiters are added by `packedItemIds`; the pattern has to mirror them.
    final rows = await (_query(
      null,
    )..where((t) => t.itemIds.like('%|${id.value}|%'))).get();
    return [for (final row in rows) _decode(row)];
  }

  @override
  Future<void> save(Outfit outfit) =>
      _db.into(_db.outfits).insertOnConflictUpdate(outfitRowFor(outfit));

  @override
  Future<void> delete(OutfitId id) =>
      (_db.delete(_db.outfits)..where((t) => t.id.equals(id.value))).go();

  @override
  Future<void> removeItem(ItemId id) async {
    final affected = await containing(id);
    if (affected.isEmpty) return;

    // One transaction: an interrupted removal that dropped a garment from
    // three outfits and not the fourth would leave the list referencing
    // something that no longer exists, which is the exact state this method
    // exists to prevent.
    await _db.transaction(() async {
      for (final outfit in affected) {
        final reduced = outfit.without(id);
        if (reduced.size < 2) {
          await delete(outfit.id);
        } else {
          await save(reduced);
        }
      }
    });
  }

  @override
  Stream<List<Outfit>> watch({Occasion? occasion}) => _query(
    occasion,
  ).watch().map((rows) => [for (final row in rows) _decode(row)]);

  /// The base query, ordered the way the contract requires.
  ///
  /// Most recently updated first, with the id as a tie-break — without which
  /// two outfits saved in the same millisecond come back in whatever order
  /// SQLite feels like, and a list that reshuffles between reads looks broken.
  SimpleSelectStatement<$OutfitsTable, OutfitRow> _query(Occasion? occasion) {
    final select = _db.select(_db.outfits)
      ..orderBy([
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id),
      ]);
    if (occasion != null) {
      select.where((t) => t.occasion.equals(occasion.name));
    }
    return select;
  }

  Outfit _decode(OutfitRow row) =>
      Outfit.fromJson(jsonDecode(row.payload) as Map<String, Object?>);
}
