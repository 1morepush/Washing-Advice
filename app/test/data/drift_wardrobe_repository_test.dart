/// The Drift repository, held to the core's contract.
///
/// The whole suite comes from `wardrobe_core` — the same tests that verify
/// `InMemoryWardrobeRepository`. That is the point: the in-memory version is
/// the executable definition of what every filter means, and a `WHERE` clause
/// that disagrees fails here rather than surfacing as a wrong wardrobe screen.
///
/// The extra tests at the bottom cover things only a database has: that the
/// lifted query columns stay in step with the JSON payload, and that a stored
/// item survives a round trip through SQLite unchanged.
///
/// Run with `dart test`, not `flutter test`. That is why `database.dart` takes
/// its executor instead of opening one (see `connection.dart`): storage has no
/// Flutter in it, so it is testable against real sqlite3 without a widget
/// binding — and the core's contract suite, which imports `package:test/test.dart`,
/// only loads under the plain runner.
library;

import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/drift/database.dart';
import 'package:washing_advice/data/drift/drift_wardrobe_repository.dart';

// The contract suite itself, imported from the core's test directory.
import '../../../packages/wardrobe_core/test/wardrobe/repository_test.dart'
    show runRepositoryContractTests;

void main() {
  final open = <AppDatabase>[];

  tearDown(() async {
    for (final db in open) {
      await db.close();
    }
    open.clear();
  });

  runRepositoryContractTests('DriftWardrobeRepository', () async {
    final db = AppDatabase(NativeDatabase.memory());
    open.add(db);
    return DriftWardrobeRepository(db);
  });

  group('storage details', () {
    late AppDatabase db;
    late DriftWardrobeRepository repository;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      open.add(db);
      repository = DriftWardrobeRepository(db);
    });

    test('an item survives a round trip through SQLite unchanged', () async {
      final original = _item(
        id: 'full',
        name: 'Grey Nike hoodie',
        brand: 'Nike',
        composition: {Fiber.cotton: 80, Fiber.polyester: 20},
      );

      await repository.save(original);
      final loaded = await repository.byId(const ItemId('full'));

      expect(loaded, isNotNull);
      // Compared as JSON: WardrobeItem's identity is its id alone, so `==`
      // would pass even if every other field had been mangled.
      expect(loaded!.toJson(), original.toJson());
    });

    test('the lifted columns are rebuilt when an item is replaced', () async {
      // The payload and the query columns are two representations of one thing.
      // If a save updated only the payload, the item would keep matching its
      // old filters — visible as a wardrobe screen that will not update.
      await repository.save(_item(id: 'a', name: 'Before', brand: 'Nike'));
      await repository.save(_item(id: 'a', name: 'After', brand: 'Adidas'));

      expect(
        await repository.query(const WardrobeQuery(text: 'after')),
        hasLength(1),
      );
      expect(await repository.query(const WardrobeQuery(text: 'before')), isEmpty);
      expect(
        await repository.query(const WardrobeQuery(brands: {'Adidas'})),
        hasLength(1),
      );
      expect(
        await repository.query(const WardrobeQuery(brands: {'Nike'})),
        isEmpty,
      );
    });

    test('packed columns do not match a fibre by prefix', () async {
      // `wool` must not match `lyocell` merely by appearing inside it. The
      // delimiters in the packed encoding are what prevents that, and a
      // substring LIKE without them would silently return wrong clothes.
      await repository.save(
        _item(id: 'lyocell-dress', composition: {Fiber.lyocell: 100}),
      );

      expect(
        await repository.query(const WardrobeQuery(fibers: {Fiber.wool})),
        isEmpty,
      );
      expect(
        await repository.query(const WardrobeQuery(fibers: {Fiber.lyocell})),
        hasLength(1),
      );
    });

    test('only fibres that describe the garment are indexed', () async {
      // The index has to apply the core's threshold, not a second opinion of
      // its own. This test is what caught the two disagreeing: the index was
      // built from the *care* threshold, so an 80/20 cotton-polyester tee was
      // not findable under polyester at all.
      await repository.saveAll([
        _item(
          id: 'trace',
          composition: {Fiber.cotton: 98, Fiber.elastane: 2},
        ),
        _item(
          id: 'real',
          composition: {Fiber.cotton: 80, Fiber.polyester: 20},
        ),
      ]);

      final elastane =
          await repository.query(const WardrobeQuery(fibers: {Fiber.elastane}));
      expect(elastane, isEmpty);

      final polyester = await repository
          .query(const WardrobeQuery(fibers: {Fiber.polyester}));
      expect([for (final i in polyester) i.id.value], ['real']);
    });

    test('a paged query with an offset and no limit still works', () async {
      // SQLite requires a LIMIT before an OFFSET; getting that wrong throws
      // rather than returning wrong data, so it is worth pinning.
      await repository.saveAll([
        for (var i = 0; i < 5; i++) _item(id: 'item-$i'),
      ]);

      final page = await repository.query(const WardrobeQuery(offset: 2));
      expect(page, hasLength(3));
    });

    test('brands come back in their display casing, not lower-cased',
        () async {
      await repository.save(_item(id: 'a', brand: 'Nike'));
      expect(await repository.knownBrands(), ['Nike']);
    });
  });
}

WardrobeItem _item({
  required String id,
  String name = 'Item',
  String? brand,
  ItemType type = ItemType.tShirt,
  Map<Fiber, int> composition = const {Fiber.cotton: 100},
}) {
  final now = DateTime.utc(2026, 3, 15);
  return WardrobeItem(
    id: ItemId(id),
    name: name,
    type: Confident(type, confidence: 0.9, source: Provenance.aiInference),
    composition: Confident(
      FabricComposition(composition),
      confidence: 0.9,
      source: Provenance.tagScan,
    ),
    colors: Confident(
      ColorPalette([ItemColor.fromHex('#8A8A8A', name: 'Grey')]),
      confidence: 0.9,
      source: Provenance.aiInference,
    ),
    brand: brand == null ? null : Confident.fromUser(brand),
    care: const CareProfile.unknown(),
    addedAt: now,
    updatedAt: now,
  );
}
