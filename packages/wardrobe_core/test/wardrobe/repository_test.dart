/// The contract every `WardrobeRepository` must satisfy.
///
/// Written against the interface, not against the in-memory class, so the app's
/// Drift implementation can be dropped into `runRepositoryContractTests` and
/// held to exactly the same behaviour. A `WHERE` clause that disagrees with
/// `InMemoryWardrobeRepository._matches` is then a failing test rather than an
/// open question about what a filter was supposed to mean.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

/// Builds a fresh, empty repository.
typedef RepositoryFactory = Future<WardrobeRepository> Function();

void main() {
  runRepositoryContractTests(
    'InMemoryWardrobeRepository',
    () async => InMemoryWardrobeRepository(),
  );

  group('WardrobeQuery', () {
    test('an empty query is unfiltered', () {
      expect(const WardrobeQuery().isUnfiltered, isTrue);
      expect(const WardrobeQuery().activeFilterCount, 0);
    });

    test('counts only the filters actually set', () {
      const query = WardrobeQuery(
        favouritesOnly: true,
        brands: {'Nike'},
        text: 'hoodie',
      );
      expect(query.activeFilterCount, 3);
      expect(query.isUnfiltered, isFalse);
    });

    test('blank text is not a filter', () {
      // Otherwise clearing a search box would leave the UI claiming a filter.
      const query = WardrobeQuery(text: '   ');
      expect(query.isUnfiltered, isTrue);
      expect(query.activeFilterCount, 0);
    });

    test('sorting and paging are not filters', () {
      const query = WardrobeQuery(sort: WardrobeSort.mostWorn, limit: 10);
      expect(query.isUnfiltered, isTrue);
    });

    test('clearing keeps sort and paging', () {
      const query = WardrobeQuery(
        favouritesOnly: true,
        sort: WardrobeSort.mostWorn,
        limit: 20,
      );
      final cleared = query.cleared();

      expect(cleared.isUnfiltered, isTrue);
      expect(cleared.sort, WardrobeSort.mostWorn);
      expect(cleared.limit, 20);
    });

    test('equal queries compare equal regardless of set order', () {
      const a = WardrobeQuery(brands: {'Nike', 'Adidas'});
      const b = WardrobeQuery(brands: {'Adidas', 'Nike'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('the owned preset excludes items the user no longer has', () {
      const owned = WardrobeQuery.owned();
      expect(owned.lifecycleStates, contains(LifecycleState.active));
      expect(owned.lifecycleStates, isNot(contains(LifecycleState.donated)));
      expect(owned.lifecycleStates, isNot(contains(LifecycleState.discarded)));
    });
  });
}

/// The behavioural contract, runnable against any implementation.
void runRepositoryContractTests(String name, RepositoryFactory create) {
  group('$name: storage', () {
    late WardrobeRepository repository;

    setUp(() async => repository = await create());

    test('an unknown id is null rather than an error', () async {
      expect(await repository.byId(const ItemId('nope')), isNull);
    });

    test('saves and reads back', () async {
      final item = buildItem(id: 'a', name: 'Grey hoodie');
      await repository.save(item);

      final loaded = await repository.byId(const ItemId('a'));
      expect(loaded?.name, 'Grey hoodie');
    });

    test('saving the same id replaces rather than duplicates', () async {
      await repository.save(buildItem(id: 'a', name: 'First'));
      await repository.save(buildItem(id: 'a', name: 'Second'));

      expect(await repository.count(const WardrobeQuery()), 1);
      expect((await repository.byId(const ItemId('a')))?.name, 'Second');
    });

    test('saveAll stores every item', () async {
      await repository.saveAll([
        buildItem(id: 'a'),
        buildItem(id: 'b'),
        buildItem(id: 'c'),
      ]);
      expect(await repository.count(const WardrobeQuery()), 3);
    });

    test('delete removes an item', () async {
      await repository.save(buildItem(id: 'a'));
      await repository.delete(const ItemId('a'));

      expect(await repository.byId(const ItemId('a')), isNull);
    });

    test('deleting something absent is not an error', () async {
      await repository.delete(const ItemId('never-existed'));
    });

    test('lists the brands present, sorted and deduplicated', () async {
      await repository.saveAll([
        buildItem(id: 'a', brand: 'Nike'),
        buildItem(id: 'b', brand: 'Adidas'),
        buildItem(id: 'c', brand: 'Nike'),
        buildItem(id: 'd'),
      ]);

      expect(await repository.knownBrands(), ['Adidas', 'Nike']);
    });
  });

  group('$name: filtering', () {
    late WardrobeRepository repository;

    setUp(() async {
      repository = await create();
      await repository.saveAll([
        buildItem(
          id: 'white-tee',
          name: 'White tee',
          type: ItemType.tShirt,
          colors: [Colors.white],
          brand: 'Uniqlo',
          composition: {Fiber.cotton: 100},
        ),
        buildItem(
          id: 'navy-hoodie',
          name: 'Navy hoodie',
          type: ItemType.hoodie,
          colors: [Colors.navy],
          brand: 'Nike',
          // Carries both sides of the fibre-search threshold: 20% polyester
          // describes the garment, 2% elastane does not. The 2% is still below
          // elastane's care threshold of 3, so this stays a plain warm wash and
          // the fixture is not quietly testing two things at once.
          composition: {Fiber.cotton: 78, Fiber.polyester: 20, Fiber.elastane: 2},
          isFavorite: true,
        ),
        buildItem(
          id: 'wool-jumper',
          name: 'Wool jumper',
          type: ItemType.sweater,
          colors: [Colors.charcoal],
          composition: {Fiber.wool: 100},
          usage: const UsageStats(),
        ),
        buildItem(
          id: 'old-jeans',
          name: 'Old jeans',
          type: ItemType.jeans,
          colors: [Colors.navy],
          brand: 'Levi\'s',
          lifecycle: LifecycleState.donated,
        ),
      ]);
    });

    Future<List<String>> ids(WardrobeQuery query) async =>
        [for (final item in await repository.query(query)) item.id.value];

    test('no filters returns everything', () async {
      expect(await ids(const WardrobeQuery()), hasLength(4));
    });

    test('filters by type', () async {
      expect(
        await ids(const WardrobeQuery(types: {ItemType.hoodie})),
        ['navy-hoodie'],
      );
    });

    test('filters by category', () async {
      final tops =
          await ids(const WardrobeQuery(categories: {ItemCategory.top}));
      expect(tops, containsAll(['white-tee', 'navy-hoodie', 'wool-jumper']));
      expect(tops, isNot(contains('old-jeans')));
    });

    test('filters by colour class', () async {
      expect(
        await ids(const WardrobeQuery(colorClasses: {ColorClass.whites})),
        ['white-tee'],
      );
    });

    test('filters by brand, case-insensitively', () async {
      // Users type "nike"; the stored value is "Nike".
      expect(await ids(const WardrobeQuery(brands: {'nike'})), ['navy-hoodie']);
    });

    test('an item with no brand never matches a brand filter', () async {
      expect(
        await ids(const WardrobeQuery(brands: {'Nike'})),
        isNot(contains('wool-jumper')),
      );
    });

    test('filters by fibre when the garment is described by it', () async {
      expect(
        await ids(const WardrobeQuery(fibers: {Fiber.wool})),
        ['wool-jumper'],
      );
      expect(
        await ids(const WardrobeQuery(fibers: {Fiber.cotton})),
        containsAll(['white-tee', 'navy-hoodie']),
      );
    });

    test('a blended fibre still describes the garment', () async {
      // The hoodie is 20% polyester, which is a polyester blend by any ordinary
      // reading. It is *not* enough to change how the thing is washed, and an
      // earlier version filtered on the care threshold and so found nothing
      // here — the bug this test exists to prevent coming back.
      expect(
        await ids(const WardrobeQuery(fibers: {Fiber.polyester})),
        ['navy-hoodie'],
      );
    });

    test('a trace fibre does not describe the garment', () async {
      // The same hoodie has 2% elastane. Someone asking to see their elastane
      // clothes does not mean a waistband, even though the care rules care.
      expect(await ids(const WardrobeQuery(fibers: {Fiber.elastane})), isEmpty);
    });

    test('filters favourites', () async {
      expect(
        await ids(const WardrobeQuery(favouritesOnly: true)),
        ['navy-hoodie'],
      );
    });

    test('filters never-worn items', () async {
      expect(await ids(const WardrobeQuery(neverWorn: true)), ['wool-jumper']);
    });

    test('filters by lifecycle, so the owned preset hides donations', () async {
      final owned = await ids(const WardrobeQuery.owned());
      expect(owned, hasLength(3));
      expect(owned, isNot(contains('old-jeans')));
    });

    test('free text searches name, brand and type', () async {
      expect(await ids(const WardrobeQuery(text: 'hoodie')), ['navy-hoodie']);
      expect(await ids(const WardrobeQuery(text: 'levi')), ['old-jeans']);
      expect(await ids(const WardrobeQuery(text: 'jumper')), ['wool-jumper']);
    });

    test('free text is case-insensitive', () async {
      expect(await ids(const WardrobeQuery(text: 'NAVY')), ['navy-hoodie']);
    });

    test('filters combine with AND', () async {
      expect(
        await ids(
          const WardrobeQuery(
            colorClasses: {ColorClass.darks},
            favouritesOnly: true,
          ),
        ),
        ['navy-hoodie'],
      );
    });

    test('a filter matching nothing returns empty rather than everything',
        () async {
      expect(await ids(const WardrobeQuery(brands: {'Nonexistent'})), isEmpty);
    });

    test('count ignores paging', () async {
      const query = WardrobeQuery(limit: 1);
      expect(await repository.count(query), 4);
      expect(await ids(query), hasLength(1));
    });
  });

  group('$name: seasons', () {
    late WardrobeRepository repository;

    setUp(() async {
      repository = await create();
      await repository.saveAll([
        buildItem(id: 'summer', seasons: {Season.summer}),
        buildItem(id: 'all', seasons: {Season.allSeason}),
        buildItem(id: 'winter', seasons: {Season.winter}),
      ]);
    });

    test('matches on overlap, so all-season items appear in summer', () async {
      // An all-season item genuinely is wearable in summer; excluding it would
      // make the filter actively misleading.
      final results = await repository.query(
        const WardrobeQuery(seasons: {Season.summer, Season.allSeason}),
      );
      expect(
        [for (final item in results) item.id.value],
        containsAll(['summer', 'all']),
      );
    });
  });

  group('$name: wear dates', () {
    late WardrobeRepository repository;
    final cutoff = DateTime.utc(2026, 2, 1);

    setUp(() async {
      repository = await create();
      await repository.saveAll([
        buildItem(
          id: 'recent',
          usage: UsageStats(timesWorn: 3, lastWornAt: DateTime.utc(2026, 3, 1)),
        ),
        buildItem(
          id: 'stale',
          usage: UsageStats(timesWorn: 3, lastWornAt: DateTime.utc(2026, 1, 1)),
        ),
        buildItem(id: 'never', usage: const UsageStats()),
      ]);
    });

    test('wornSince finds only recently worn items', () async {
      final results = await repository.query(WardrobeQuery(wornSince: cutoff));
      expect([for (final i in results) i.id.value], ['recent']);
    });

    test('notWornSince includes items never worn at all', () async {
      // Never worn is the extreme case of "not worn since", not an exception
      // to it — the whole point of the filter is finding neglected clothes.
      final results =
          await repository.query(WardrobeQuery(notWornSince: cutoff));
      expect(
        [for (final i in results) i.id.value],
        containsAll(['stale', 'never']),
      );
      expect([for (final i in results) i.id.value], isNot(contains('recent')));
    });
  });

  group('$name: sorting', () {
    late WardrobeRepository repository;

    setUp(() async {
      repository = await create();
      await repository.saveAll([
        buildItem(
          id: 'worn-often',
          name: 'B',
          usage:
              UsageStats(timesWorn: 40, lastWornAt: DateTime.utc(2026, 1, 5)),
          purchase: const PurchaseInfo(
            priceMinorUnits: 8000,
            currencyCode: 'USD',
          ),
        ),
        buildItem(
          id: 'worn-once',
          name: 'A',
          usage: UsageStats(timesWorn: 1, lastWornAt: DateTime.utc(2026, 3, 5)),
          purchase: const PurchaseInfo(
            priceMinorUnits: 8000,
            currencyCode: 'USD',
          ),
        ),
        buildItem(id: 'never-worn', name: 'C', usage: const UsageStats()),
      ]);
    });

    Future<List<String>> sorted(WardrobeSort sort) async => [
          for (final item in await repository.query(WardrobeQuery(sort: sort)))
            item.id.value,
        ];

    test('by name', () async {
      expect(
        await sorted(WardrobeSort.nameAscending),
        ['worn-once', 'worn-often', 'never-worn'],
      );
    });

    test('by most worn', () async {
      expect((await sorted(WardrobeSort.mostWorn)).first, 'worn-often');
    });

    test('by cost per wear, cheapest first', () async {
      // Same price, very different value: 40 wears beats 1.
      final order = await sorted(WardrobeSort.costPerWear);
      expect(order.first, 'worn-often');
      // An unpriced, unworn item has no cost per wear, so it sorts last rather
      // than pretending to be free.
      expect(order.last, 'never-worn');
    });

    test('never-worn items sort last by wear date, not first', () async {
      // Sorting a null date as "very old" would bury the most-worn items under
      // everything untouched, in a view meant to surface what gets used.
      expect((await sorted(WardrobeSort.recentlyWorn)).last, 'never-worn');
      expect((await sorted(WardrobeSort.leastRecentlyWorn)).last, 'never-worn');
    });
  });

  group('$name: watching', () {
    late WardrobeRepository repository;

    setUp(() async => repository = await create());

    test('emits current results immediately on listen', () async {
      await repository.save(buildItem(id: 'a'));

      final first = await repository.watch(const WardrobeQuery()).first;
      expect(first, hasLength(1));
    });

    test('re-emits when an item is saved', () async {
      final stream = repository.watch(const WardrobeQuery());
      final results = <int>[];
      final subscription = stream.listen((items) => results.add(items.length));

      await Future<void>.delayed(Duration.zero);
      await repository.save(buildItem(id: 'a'));
      await Future<void>.delayed(Duration.zero);
      await repository.save(buildItem(id: 'b'));
      await Future<void>.delayed(Duration.zero);

      await subscription.cancel();
      // The wardrobe screen watches rather than polls, so an item saved after
      // a scan appears without anyone remembering to refresh.
      expect(results, containsAllInOrder([0, 1, 2]));
    });

    test('a watched query keeps its filter across updates', () async {
      final stream =
          repository.watch(const WardrobeQuery(favouritesOnly: true));
      final results = <int>[];
      final subscription = stream.listen((items) => results.add(items.length));

      await Future<void>.delayed(Duration.zero);
      await repository.save(buildItem(id: 'plain'));
      await Future<void>.delayed(Duration.zero);
      await repository.save(buildItem(id: 'fave', isFavorite: true));
      await Future<void>.delayed(Duration.zero);

      await subscription.cancel();
      expect(results.last, 1, reason: 'the filter was dropped on re-emit');
    });
  });
}
