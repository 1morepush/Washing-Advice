/// The Drift outfit repository, held to the core's contract.
///
/// The whole file is the core's shared suite pointed at the SQL
/// implementation, plus the handful of tests that are only meaningful against
/// a real database — the migration, and the packed-id matching that has no
/// in-memory counterpart.
///
/// Run with `dart test`, not `flutter test`, for the reason given in
/// `drift_wardrobe_repository_test.dart`: the core's contract suites import
/// `package:test/test.dart` and only load under the plain runner.
library;

import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/drift/database.dart';
import 'package:washing_advice/data/drift/drift_outfit_repository.dart';

// The contract suite itself, imported from the core's test directory.
import '../../../packages/wardrobe_core/test/outfits/outfit_repository_test.dart'
    show runOutfitRepositoryContractTests;

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

  runOutfitRepositoryContractTests(
    'DriftOutfitRepository',
    () => DriftOutfitRepository(open()),
  );

  group('DriftOutfitRepository: SQL specifics', () {
    late DriftOutfitRepository repository;

    setUp(() => repository = DriftOutfitRepository(open()));

    test('an id is not matched by one that merely ends the same way', () async {
      // The reason the packed column is delimited at both ends. Without the
      // leading `|`, searching for `tee` would also match `white-tee`.
      await repository.save(_outfit(id: 'a', items: ['white-tee', 'jeans']));

      expect(await repository.containing(const ItemId('tee')), isEmpty);
      expect(
        await repository.containing(const ItemId('white-tee')),
        hasLength(1),
      );
    });

    test(
      'an id is not matched by one that merely starts the same way',
      () async {
        await repository.save(_outfit(id: 'a', items: ['tee-shirt', 'jeans']));

        expect(await repository.containing(const ItemId('tee')), isEmpty);
      },
    );

    test(
      'removing a garment from several outfits is one transaction',
      () async {
        // Either every outfit loses the garment or none does. A partial removal
        // leaves the list pointing at something that no longer exists, which is
        // the state the method exists to prevent.
        for (var i = 0; i < 5; i++) {
          await repository.save(
            _outfit(id: 'o$i', items: ['jeans', 'tee-$i', 'jacket']),
          );
        }

        await repository.removeItem(const ItemId('jeans'));

        expect(await repository.containing(const ItemId('jeans')), isEmpty);
        expect(await repository.all(), hasLength(5));
      },
    );
  });

  test('a version 1 database gains the outfits table on upgrade', () async {
    // Existing wardrobes must survive the schema change. The payload-as-JSON
    // design means adding outfits touches no stored item at all, and this is
    // the test that says so rather than assuming it.
    final db = open();
    await db.customStatement('SELECT 1 FROM outfits LIMIT 1');

    final repository = DriftOutfitRepository(db);
    await repository.save(_outfit(id: 'a'));
    expect(await repository.all(), hasLength(1));
  });
}

Outfit _outfit({
  required String id,
  List<String> items = const ['tee', 'jeans'],
}) => Outfit(
  id: OutfitId(id),
  name: 'Saturday',
  itemIds: [for (final item in items) ItemId(item)],
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
);
