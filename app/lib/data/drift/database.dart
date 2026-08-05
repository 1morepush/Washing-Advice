/// Local storage.
///
/// ## Why the schema looks like this
///
/// A `WardrobeItem` is a rich object graph — confidences, provenance, a colour
/// palette, a photo set, a whole care profile. Normalising all of that into
/// columns would mean a dozen tables and a join for every read, and the core
/// already knows how to serialise itself losslessly to JSON.
///
/// So the item is stored as **JSON in one column**, with the fields the app
/// actually *filters and sorts on* lifted out into real, indexed columns
/// alongside it. Reads decode the JSON; queries never touch it.
///
/// The cost is that a filterable field lives in two places and they must agree,
/// which [rowFor] handles in exactly one spot. The benefit is that adding a
/// field to the domain does not require a migration unless it becomes
/// filterable — and during a milestone-a-week build, that is the difference
/// between shipping and writing migrations.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

part 'database.g.dart';

/// Wardrobe items: JSON payload plus the columns worth indexing.
class Items extends Table {
  TextColumn get id => text()();

  /// The full `WardrobeItem`, as the core serialises it.
  TextColumn get payload => text()();

  // --- Lifted for querying. Derived from the payload by [rowFor]. ---

  TextColumn get name => text()();
  TextColumn get itemType => text()();
  TextColumn get category => text()();
  TextColumn get kind => text()();
  TextColumn get colorClass => text()();
  TextColumn get lifecycle => text()();

  /// Lower-cased, so brand filtering is case-insensitive without a scan.
  TextColumn get brandLower => text().nullable()();

  TextColumn get seasons => text()();
  TextColumn get fibers => text()();
  TextColumn get tags => text()();

  /// Name, brand, type label, notes and any printed text, lower-cased, for
  /// free-text search without decoding every payload.
  TextColumn get searchText => text()();

  BoolColumn get isFavorite => boolean()();
  BoolColumn get needsCareTagScan => boolean()();

  IntColumn get timesWorn => integer()();
  DateTimeColumn get lastWornAt => dateTime().nullable()();
  DateTimeColumn get addedAt => dateTime()();

  /// Cost per wear in minor units, precomputed so sorting does not need to
  /// decode. Null when unpriced or unworn, which sorts last.
  IntColumn get costPerWearMinor => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The append-only event log.
class Events extends Table {
  TextColumn get id => text()();
  TextColumn get itemId => text()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Items, Events])
class AppDatabase extends _$AppDatabase {
  /// Takes its executor rather than opening one.
  ///
  /// Keeps this file free of Flutter: opening a platform database is the app's
  /// job (see `connection.dart`), and a test supplies an in-memory sqlite3
  /// instead. The schema is then exercisable with plain `dart test`.
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Indexes on the columns the wardrobe screen actually filters by.
          // Without these every filter is a table scan, which is fine at 50
          // items and not at 500.
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_items_lifecycle '
            'ON items (lifecycle)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_items_category ON items (category)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_items_brand ON items (brand_lower)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_events_item ON events (item_id)',
          );
        },
      );
}

/// Builds the storage row for an item.
///
/// The single place where the lifted columns are derived from the payload, so
/// the two cannot disagree. Anything filterable must be computed here.
ItemsCompanion rowFor(WardrobeItem item) {
  final searchable = [
    item.name,
    item.brand?.value ?? '',
    item.type.value.label,
    item.distinguishingText ?? '',
    item.notes ?? '',
    ...item.tags,
  ].join(' ').toLowerCase();

  // Only fibres the garment is genuinely described by are indexed, matching
  // `InMemoryWardrobeRepository`. The threshold comes from the core rather
  // than being restated here: the whole point of one shared constant is that
  // the index and the in-memory filter cannot answer differently.
  final composition = item.composition.value;
  final notableFibers = [
    for (final fiber in composition.percentages.keys)
      if (composition.isDescribedBy(fiber)) fiber.name,
  ];

  final costPerWear = item.costPerWear;

  return ItemsCompanion.insert(
    id: item.id.value,
    payload: jsonEncode(item.toJson()),
    name: item.name,
    itemType: item.type.value.name,
    category: item.category.name,
    kind: item.kind.name,
    colorClass: item.colorClass.name,
    lifecycle: item.lifecycle.name,
    brandLower: Value(item.brand?.value.toLowerCase()),
    seasons: _packed(item.seasons.map((s) => s.name)),
    fibers: _packed(notableFibers),
    tags: _packed(item.tags),
    searchText: searchable,
    isFavorite: item.isFavorite,
    needsCareTagScan: item.needsCareTagScan,
    timesWorn: item.usage.timesWorn,
    lastWornAt: Value(item.usage.lastWornAt),
    addedAt: item.addedAt,
    costPerWearMinor: Value(
      costPerWear == null ? null : (costPerWear * 100).round(),
    ),
  );
}

/// Decodes a stored row back into a domain object.
WardrobeItem itemFrom(Item row) =>
    WardrobeItem.fromJson(jsonDecode(row.payload) as Map<String, Object?>);

/// Packs a set of enum names for `LIKE`-based matching.
///
/// Delimited on both ends so `%|wool|%` cannot match `lyocell`. A join table
/// would be the textbook answer; at wardrobe scale this is one column and no
/// joins, and the delimiters make it correct rather than merely convenient.
String _packed(Iterable<String> values) {
  final sorted = values.toList()..sort();
  return sorted.isEmpty ? '' : '|${sorted.join('|')}|';
}

/// The pattern that matches [value] inside a packed column.
String packedPattern(String value) => '%|$value|%';
