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

  /// Where the garment says it was made, lower-cased for matching.
  ///
  /// Lifted out of the payload for the same reason the brand is: the wardrobe
  /// filters and sorts by it, and a scan of every row to read a JSON field is
  /// fine at 50 items and not at 500. The display spelling stays in the
  /// payload — this column exists for matching, not for showing somebody
  /// "portugal".
  TextColumn get originLower => text().nullable()();

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

/// Saved outfits.
///
/// The same JSON-plus-lifted-columns shape as [Items], for the same reason.
/// The item ids are lifted into a packed column so "which outfits contain this
/// garment" is a `LIKE` against an indexed string rather than a decode of
/// every row — and they are stored delimited on both ends (`|a|b|`) so that
/// matching `|a|` cannot also match an id ending in `a`.
///
/// Named explicitly because Drift would otherwise generate a row class called
/// `Outfit`, which is the core's domain type. Two different `Outfit`s in one
/// file is the kind of collision that gets resolved with an import prefix and
/// then quietly confuses everyone who reads it.
@DataClassName('OutfitRow')
class Outfits extends Table {
  TextColumn get id => text()();

  /// The full `Outfit`, as the core serialises it.
  TextColumn get payload => text()();

  // --- Lifted for querying. Derived from the payload by [outfitRowFor]. ---

  TextColumn get name => text()();
  TextColumn get occasion => text()();

  /// `|id|id|` — see the note above about the delimiters.
  TextColumn get itemIds => text()();

  BoolColumn get isFavorite => boolean()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The append-only event log.
class Events extends Table {
  TextColumn get id => text()();
  TextColumn get itemId => text()();
  DateTimeColumn get occurredAt => dateTime()();

  /// When this device wrote the event down, as against when the thing
  /// happened. Lifted because *sync* filters on it, and decoding every payload
  /// to find out what to send would defeat the point of lifting anything.
  DateTimeColumn get recordedAt => dateTime()();

  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Items, Events, Outfits])
class AppDatabase extends _$AppDatabase {
  /// Takes its executor rather than opening one.
  ///
  /// Keeps this file free of Flutter: opening a platform database is the app's
  /// job (see `connection.dart`), and a test supplies an in-memory sqlite3
  /// instead. The schema is then exercisable with plain `dart test`.
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 4;

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
        'CREATE INDEX IF NOT EXISTS idx_items_origin ON items (origin_lower)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_events_item ON events (item_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_events_recorded '
        'ON events (recorded_at)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_outfits_occasion '
        'ON outfits (occasion)',
      );
    },
    // Version 2 adds saved outfits. A new table only, so existing wardrobes
    // migrate without touching a single stored item — which is the whole
    // reason the payload is JSON and only filterable fields are lifted.
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(outfits);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_outfits_occasion '
          'ON outfits (occasion)',
        );
      }
      if (from < 3) {
        // Backfilled from `occurred_at`, which is the only defensible guess:
        // an event cannot have been recorded before the thing it describes.
        // The consequence is that existing events look freshly recorded once
        // and are sent again, which is harmless — merging is idempotent.
        await m.addColumn(events, events.recordedAt);
        await customStatement('UPDATE events SET recorded_at = occurred_at');
      }
      if (from < 4) {
        // Nothing to backfill: no build before this one ever read a country
        // off a label, so every existing row genuinely has none. The column
        // fills in as items are saved from here on.
        await m.addColumn(items, items.originLower);
      }
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_events_recorded '
        'ON events (recorded_at)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_items_origin ON items (origin_lower)',
      );
    },
  );
}

/// Builds the storage row for an outfit.
///
/// The single place the lifted columns are derived from the payload, so the
/// two cannot disagree — the same rule [rowFor] follows.
OutfitsCompanion outfitRowFor(Outfit outfit) => OutfitsCompanion.insert(
  id: outfit.id.value,
  payload: jsonEncode(outfit.toJson()),
  name: outfit.name,
  occasion: outfit.occasion.name,
  itemIds: packedItemIds(outfit.itemIds),
  isFavorite: outfit.isFavorite,
  updatedAt: outfit.updatedAt,
);

/// `|a|b|c|`, delimited at both ends so a `LIKE '%|a|%'` cannot match `|xa|`.
String packedItemIds(Iterable<ItemId> ids) =>
    ids.isEmpty ? '|' : '|${ids.map((i) => i.value).join('|')}|';

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
    originLower: Value(item.countryOfOrigin?.value.trim().toLowerCase()),
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
