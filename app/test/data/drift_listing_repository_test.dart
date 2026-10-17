/// The Drift listing repository, held to the core's contract.
///
/// The whole suite comes from `wardrobe_core` — the same tests that define what
/// `InMemoryListingRepository` means. A listing that comes back in a different
/// order from SQLite than from the map, or a garment's listings that the `WHERE`
/// clause misses, fails here rather than on the Sell tab.
///
/// The tests after it cover what only a database has: that the columns lifted
/// out of the payload stay in step with it, and that they are indexed.
///
/// Loaded by `flutter test` as well as `dart test`, for the reason given in
/// `drift_outfit_repository_test.dart`: the contract suite imports
/// `package:test/test.dart`.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/drift/database.dart';
import 'package:washing_advice/data/drift/drift_listing_repository.dart';

// The contract suite itself, imported from the core's test directory.
import '../../../packages/wardrobe_core/test/selling/listing_repository_test.dart'
    show runListingRepositoryContractTests;

void main() {
  final databases = <AppDatabase>[];

  AppDatabase open() {
    final db = AppDatabase(NativeDatabase.memory());
    databases.add(db);
    return db;
  }

  tearDown(() async {
    for (final db in databases) {
      await db.close();
    }
    databases.clear();
  });

  runListingRepositoryContractTests(
    'DriftListingRepository',
    () => DriftListingRepository(open()),
  );

  group('DriftListingRepository: SQL specifics', () {
    late AppDatabase db;
    late DriftListingRepository repository;

    setUp(() {
      db = open();
      repository = DriftListingRepository(db);
    });

    test('the lifted columns are what the payload says', () async {
      final listing = _listing(
        id: 'a',
        itemId: 'hoodie',
      ).markListed(DateTime.utc(2026, 10, 2, 10));

      await repository.save(listing);

      // Read raw, not through the repository: the repository only ever reads
      // the payload, so it could not notice a column that had drifted.
      final row = await db.select(db.listings).getSingle();
      final payload = jsonDecode(row.payload) as Map<String, Object?>;
      expect(row.id, 'a');
      expect(row.status, payload['status']);
      expect(row.status, 'listed');
      expect(row.itemId, payload['itemId']);
      expect(row.itemId, 'hoodie');
      expect(row.updatedAt.toUtc(), DateTime.utc(2026, 10, 2, 10));
    });

    test('saving again moves the lifted columns with the payload', () async {
      final draft = _listing(id: 'a', itemId: 'hoodie');
      await repository.save(draft);

      await repository.save(
        draft.markSold(DateTime.utc(2026, 10, 9, 12), priceCents: 2800),
      );

      final row = await db.select(db.listings).getSingle();
      expect(row.status, 'sold');
      expect(row.updatedAt.toUtc(), DateTime.utc(2026, 10, 9, 12));
      expect((await repository.byId(draft.id))!.soldPriceCents, 2800);
    });

    test('a listing with no garment has no garment in its row', () async {
      await repository.save(_listing(id: 'a'));

      final row = await db.select(db.listings).getSingle();
      expect(row.itemId, isNull);
    });

    test(
      'a garment is not matched by one that merely contains its id',
      () async {
        // Exact, not `LIKE`: `hood` must not find the listings of `hoodie`.
        await repository.save(_listing(id: 'a', itemId: 'hoodie'));
        await repository.save(_listing(id: 'b', itemId: 'hood'));

        final found = await repository.forItem(const ItemId('hood'));

        expect(found.map((l) => l.id.value), ['b']);
      },
    );

    test('the stored payload is the core\'s own JSON, unchanged', () async {
      // The repository adds nothing to what the core writes: the listing comes
      // back from the payload, and the columns beside it are only for queries.
      final listing = _listing(id: 'a', itemId: 'hoodie');

      await repository.save(listing);

      final row = await db.select(db.listings).getSingle();
      expect(jsonDecode(row.payload), listing.toJson());
    });

    test('listings are indexed by status', () async {
      final indexes = await db
          .customSelect("PRAGMA index_list('listings')")
          .get();

      // Beside the key's own, which SQLite makes without being asked.
      expect(
        indexes.map((row) => row.read<String>('name')),
        contains('idx_listings_status'),
      );
    });
  });
}

Listing _listing({required String id, String? itemId}) => Listing(
  id: ListingId(id),
  itemId: itemId == null ? null : ItemId(itemId),
  createdAt: DateTime.utc(2026, 10, 1, 9),
  updatedAt: DateTime.utc(2026, 10, 1, 9),
  title: 'Nike vintage crewneck sweatshirt grey',
  itemType: ItemType.sweatshirt,
  brand: 'Nike',
  photos: const [ListingPhoto(uri: 'wa-memory:front', shot: ListingShot.cover)],
);
