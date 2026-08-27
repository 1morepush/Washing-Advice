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
import 'package:washing_advice/data/drift/drift_wardrobe_repository.dart';

import '../support/fixtures.dart';

void main() {
  late Database raw;

  setUp(() => raw = sqlite3.openInMemory());
  tearDown(() => raw.dispose());

  /// A wardrobe as version 3 left it: the current tables, minus the column
  /// version 4 adds, and stamped with the version a shipped build wrote.
  Future<void> asVersion3(WardrobeItem item) async {
    final current = AppDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await current.customStatement('PRAGMA user_version = 4');
    await DriftWardrobeRepository(current).save(item);
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
}
