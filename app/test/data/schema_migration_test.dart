/// Upgrading a wardrobe that already exists.
///
/// The one change in this codebase that can lose somebody's data. Everything
/// else is recoverable by scanning again; a migration that drops the items
/// table is a wardrobe somebody photographed one garment at a time and now has
/// to photograph again.
///
/// So this opens a database at the *old* version, with a real row in it, and
/// upgrades it the way a phone would on the next launch.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/drift/database.dart';
import 'package:washing_advice/data/drift/drift_listing_repository.dart';
import 'package:washing_advice/data/drift/drift_wardrobe_repository.dart';

import '../support/fixtures.dart';

void main() {
  late Database raw;

  setUp(() => raw = sqlite3.openInMemory());
  tearDown(() => raw.dispose());

  /// A wardrobe as version 4 left it: the current tables, minus the one
  /// version 5 adds, and stamped with the version a shipped build wrote.
  Future<void> asVersion4(WardrobeItem item) async {
    final current = AppDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await DriftWardrobeRepository(current).save(item);
    // Its index goes with it.
    await current.customStatement('DROP TABLE listings');
    await current.customStatement('PRAGMA user_version = 4');
    await current.close();
  }

  /// A wardrobe as version 3 left it: the current tables, minus the column
  /// version 4 adds and the table version 5 adds, and stamped with the version
  /// a shipped build wrote.
  Future<void> asVersion3(WardrobeItem item) async {
    final current = AppDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await current.customStatement('PRAGMA user_version = 4');
    await DriftWardrobeRepository(current).save(item);
    await current.customStatement('DROP TABLE listings');
    // The index goes first: version 3 had neither, and sqlite refuses to
    // drop a column an index still refers to.
    await current.customStatement('DROP INDEX IF EXISTS idx_items_origin');
    await current.customStatement('ALTER TABLE items DROP COLUMN origin_lower');
    await current.customStatement('PRAGMA user_version = 3');
    await current.close();
  }

  test('a wardrobe from the previous version survives the upgrade', () async {
    final saved = confidentItem(id: 'jumper', name: 'Charcoal merino jumper');
    await asVersion3(saved);

    // What a phone does on the next launch.
    final upgraded = AppDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    addTearDown(upgraded.close);
    final repository = DriftWardrobeRepository(upgraded);

    final read = await repository.byId(const ItemId('jumper'));
    expect(read, isNotNull);
    expect(read!.displayName, 'Charcoal merino jumper');
  });

  test(
    'the garments it already had have no country, not a blank one',
    () async {
      // Nothing to backfill: no build before this one read a country off a
      // label. A blank would filter and tally as a real place with no name.
      await asVersion3(confidentItem(id: 'jumper', name: 'Jumper'));

      final upgraded = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      addTearDown(upgraded.close);
      final repository = DriftWardrobeRepository(upgraded);

      expect(
        (await repository.byId(const ItemId('jumper')))!.countryOfOrigin,
        isNull,
      );
      expect(await repository.knownCountries(), isEmpty);
    },
  );

  test('and the new column works once something is saved into it', () async {
    await asVersion3(confidentItem(id: 'old', name: 'Old jumper'));

    final upgraded = AppDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    addTearDown(upgraded.close);
    final repository = DriftWardrobeRepository(upgraded);

    await repository.save(
      confidentItem(id: 'new', name: 'New shirt').copyWith(
        countryOfOrigin: Confident(
          'Portugal',
          confidence: 0.9,
          source: Provenance.tagScan,
        ),
      ),
    );

    // The lifted column is what the filter reads, so this failing would mean
    // the migration added a column nothing writes to.
    final found = await repository.query(
      const WardrobeQuery(countries: {'Portugal'}),
    );
    expect(found.map((i) => i.id.value), ['new']);
  });

  group('version 4 to 5, which adds listings', () {
    test('a wardrobe from version 4 keeps its garment', () async {
      final saved = confidentItem(id: 'jumper', name: 'Charcoal merino jumper');
      await asVersion4(saved);
      // The starting point is what a shipped build left: no listings table, so
      // that what follows can only have come from the upgrade.
      expect(_tables(raw), isNot(contains('listings')));

      final upgraded = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      addTearDown(upgraded.close);

      final read = await DriftWardrobeRepository(
        upgraded,
      ).byId(const ItemId('jumper'));
      expect(read, isNotNull);
      // Not touched at all, down to the last stored field.
      expect(read!.toJson(), saved.toJson());
    });

    test('and gains a listings table that is empty and works', () async {
      await asVersion4(confidentItem(id: 'jumper', name: 'Jumper'));

      final upgraded = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      addTearDown(upgraded.close);
      final listings = DriftListingRepository(upgraded);

      // Nothing has been listed yet, and asking is not an error.
      expect(await listings.all(), isEmpty);

      final draft = Listing.empty(
        id: const ListingId('first'),
        now: DateTime.utc(2026, 10, 17, 9),
      ).copyWith(title: 'Charcoal merino jumper');
      await listings.save(draft);

      expect(await listings.all(), [draft]);
      expect(_tables(raw), contains('listings'));
      expect(_indexes(raw), contains('idx_listings_status'));
      expect(_userVersion(raw), 5);
    });

    test('a listing is found by its garment once upgraded', () async {
      // The two tables meet at the garment's id, so the upgrade has to leave
      // both usable together and not merely each on its own.
      await asVersion4(confidentItem(id: 'jumper', name: 'Jumper'));
      final upgraded = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      addTearDown(upgraded.close);

      final listings = DriftListingRepository(upgraded);
      await listings.save(
        Listing(
          id: const ListingId('first'),
          itemId: const ItemId('jumper'),
          createdAt: DateTime.utc(2026, 10, 17, 9),
          updatedAt: DateTime.utc(2026, 10, 17, 9),
          title: 'Charcoal merino jumper',
        ),
      );

      expect(
        (await listings.unsoldFor(const ItemId('jumper')))!.id,
        const ListingId('first'),
      );
    });

    test('a wardrobe from version 3 comes all the way up', () async {
      // The steps run in order, so a phone that skipped a release still ends
      // with every table and column the current build reads.
      await asVersion3(confidentItem(id: 'jumper', name: 'Jumper'));

      final upgraded = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      addTearDown(upgraded.close);

      expect(
        await DriftWardrobeRepository(upgraded).byId(const ItemId('jumper')),
        isNotNull,
      );
      expect(await DriftListingRepository(upgraded).all(), isEmpty);
      expect(_tables(raw), contains('listings'));
      expect(_userVersion(raw), 5);
    });

    test('a new install has the same tables and indexes', () async {
      final fresh = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      addTearDown(fresh.close);
      await DriftListingRepository(fresh).all();

      expect(_tables(raw), contains('listings'));
      expect(_indexes(raw), contains('idx_listings_status'));
      expect(_userVersion(raw), 5);
    });
  });
}

/// The names of the tables in [database].
Set<String> _tables(Database database) => {
  for (final row in database.select(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  ))
    row['name'] as String,
};

/// The names of the indexes in [database].
Set<String> _indexes(Database database) => {
  for (final row in database.select(
    "SELECT name FROM sqlite_master WHERE type = 'index'",
  ))
    row['name'] as String,
};

int _userVersion(Database database) =>
    database.select('PRAGMA user_version').single.values.single! as int;
