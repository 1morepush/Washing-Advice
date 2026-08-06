/// The `OutfitRepository` contract.
///
/// Exported rather than kept private so the app's Drift implementation runs
/// the same tests. Two implementations of one interface that are only ever
/// tested separately drift apart — that has happened twice in this project
/// already, with the wardrobe repository and the event log — and the failure
/// is silent until a user hits it.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

typedef OutfitRepositoryFactory = FutureOr<OutfitRepository> Function();

void main() {
  runOutfitRepositoryContractTests(
    'InMemoryOutfitRepository',
    InMemoryOutfitRepository.new,
  );
}

Outfit buildOutfit({
  required String id,
  String name = 'Saturday',
  List<String> items = const ['tee', 'jeans'],
  Occasion occasion = Occasion.everyday,
  Set<Season> seasons = const {},
  DateTime? updatedAt,
}) =>
    Outfit(
      id: OutfitId(id),
      name: name,
      itemIds: [for (final item in items) ItemId(item)],
      occasion: occasion,
      seasons: seasons,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: updatedAt ?? DateTime.utc(2026, 8, 1),
    );

void runOutfitRepositoryContractTests(
  String name,
  OutfitRepositoryFactory create,
) {
  group('$name: storage', () {
    late OutfitRepository repository;

    setUp(() async => repository = await create());

    test('an unknown id is null rather than an error', () async {
      expect(await repository.byId(const OutfitId('nope')), isNull);
    });

    test('saves and reads back', () async {
      await repository.save(buildOutfit(id: 'a', name: 'Friday'));

      final stored = await repository.byId(const OutfitId('a'));
      expect(stored!.name, 'Friday');
      expect(stored.itemIds, [const ItemId('tee'), const ItemId('jeans')]);
    });

    test('item order is preserved, because it is the order shown', () async {
      await repository.save(
        buildOutfit(id: 'a', items: ['jacket', 'tee', 'jeans']),
      );

      expect(
        (await repository.byId(
          const OutfitId('a'),
        ))!
            .itemIds
            .map((i) => i.value),
        ['jacket', 'tee', 'jeans'],
      );
    });

    test('saving the same id twice replaces rather than duplicates', () async {
      await repository.save(buildOutfit(id: 'a', name: 'First'));
      await repository.save(buildOutfit(id: 'a', name: 'Second'));

      expect((await repository.byId(const OutfitId('a')))!.name, 'Second');
      expect(await repository.all(), hasLength(1));
    });

    test('every field survives a round trip', () async {
      final outfit = buildOutfit(
        id: 'a',
        occasion: Occasion.formal,
        seasons: {Season.winter, Season.autumn},
      ).copyWith(
        isFavorite: true,
        notes: 'the good jeans',
        usage: const UsageStats(timesWorn: 4),
      );

      await repository.save(outfit);

      final stored = (await repository.byId(const OutfitId('a')))!;
      expect(stored.toJson(), outfit.toJson());
    });

    test('deleting removes it', () async {
      await repository.save(buildOutfit(id: 'a'));
      await repository.delete(const OutfitId('a'));

      expect(await repository.byId(const OutfitId('a')), isNull);
      expect(await repository.all(), isEmpty);
    });

    test('deleting something absent is not an error', () async {
      await repository.delete(const OutfitId('nope'));
      expect(await repository.all(), isEmpty);
    });
  });

  group('$name: listing', () {
    late OutfitRepository repository;

    setUp(() async => repository = await create());

    test('is empty before anything is saved', () async {
      expect(await repository.all(), isEmpty);
    });

    test('most recently updated first', () async {
      await repository.save(
        buildOutfit(id: 'old', updatedAt: DateTime.utc(2026, 1, 5)),
      );
      await repository.save(
        buildOutfit(id: 'new', updatedAt: DateTime.utc(2026, 8, 5)),
      );

      expect([
        for (final o in await repository.all()) o.id.value,
      ], [
        'new',
        'old'
      ]);
    });

    test('a tie is broken stably rather than arbitrarily', () async {
      // Two outfits saved in the same millisecond must not reorder themselves
      // between reads.
      final at = DateTime.utc(2026, 8, 5);
      await repository.save(buildOutfit(id: 'b', updatedAt: at));
      await repository.save(buildOutfit(id: 'a', updatedAt: at));

      expect(
        [for (final o in await repository.all()) o.id.value],
        [for (final o in await repository.all()) o.id.value],
      );
    });

    test('filters by occasion', () async {
      await repository.save(buildOutfit(id: 'work', occasion: Occasion.work));
      await repository.save(
        buildOutfit(id: 'casual', occasion: Occasion.everyday),
      );

      final work = await repository.all(occasion: Occasion.work);
      expect([for (final o in work) o.id.value], ['work']);
    });

    test('finds the outfits a garment is part of', () async {
      await repository.save(buildOutfit(id: 'a', items: ['tee', 'jeans']));
      await repository.save(buildOutfit(id: 'b', items: ['shirt', 'jeans']));
      await repository.save(buildOutfit(id: 'c', items: ['shirt', 'chinos']));

      final withJeans = await repository.containing(const ItemId('jeans'));
      expect([for (final o in withJeans) o.id.value]..sort(), ['a', 'b']);
    });

    test('a garment in nothing yields an empty list', () async {
      await repository.save(buildOutfit(id: 'a'));
      expect(await repository.containing(const ItemId('scarf')), isEmpty);
    });
  });

  group('$name: when a garment leaves the wardrobe', () {
    late OutfitRepository repository;

    setUp(() async => repository = await create());

    test('it is dropped from the outfits that held it', () async {
      await repository.save(
        buildOutfit(id: 'a', items: ['tee', 'jeans', 'jacket']),
      );

      await repository.removeItem(const ItemId('jeans'));

      final stored = (await repository.byId(const OutfitId('a')))!;
      expect([for (final i in stored.itemIds) i.value], ['tee', 'jacket']);
    });

    test('an outfit left with one item is deleted, not kept', () async {
      // An "outfit" of one garment is not an outfit, and leaving it in a list
      // the user maintains by hand is worse than removing it.
      await repository.save(buildOutfit(id: 'a', items: ['tee', 'jeans']));

      await repository.removeItem(const ItemId('jeans'));

      expect(await repository.byId(const OutfitId('a')), isNull);
    });

    test('outfits that never held it are untouched', () async {
      await repository.save(buildOutfit(id: 'a', items: ['tee', 'jeans']));
      await repository.save(buildOutfit(id: 'b', items: ['shirt', 'chinos']));

      await repository.removeItem(const ItemId('jeans'));

      expect((await repository.byId(const OutfitId('b')))!.size, 2);
    });

    test('removing something no outfit holds is not an error', () async {
      await repository.save(buildOutfit(id: 'a'));
      await repository.removeItem(const ItemId('scarf'));

      expect(await repository.all(), hasLength(1));
    });
  });

  group('$name: watching', () {
    late OutfitRepository repository;

    setUp(() async => repository = await create());

    test('emits the current contents on subscribe', () async {
      // Not only on the next change. A screen that subscribes to an existing
      // list and is told nothing shows a spinner forever.
      await repository.save(buildOutfit(id: 'a'));

      expect(await repository.watch().first, hasLength(1));
    });

    test('re-emits when something is saved', () async {
      final seen = <int>[];
      final subscription = repository.watch().listen(
            (list) => seen.add(list.length),
          );

      await pumpEventQueue();
      await repository.save(buildOutfit(id: 'a'));
      await pumpEventQueue();

      expect(seen.last, 1);
      await subscription.cancel();
    });

    test('re-emits when something is deleted', () async {
      await repository.save(buildOutfit(id: 'a'));

      final seen = <int>[];
      final subscription = repository.watch().listen(
            (list) => seen.add(list.length),
          );

      await pumpEventQueue();
      await repository.delete(const OutfitId('a'));
      await pumpEventQueue();

      expect(seen.last, 0);
      await subscription.cancel();
    });

    test('honours the occasion filter', () async {
      final seen = <List<String>>[];
      final subscription = repository
          .watch(occasion: Occasion.work)
          .listen((list) => seen.add([for (final o in list) o.id.value]));

      await pumpEventQueue();
      await repository.save(
        buildOutfit(id: 'casual', occasion: Occasion.everyday),
      );
      await repository.save(buildOutfit(id: 'work', occasion: Occasion.work));
      await pumpEventQueue();

      expect(seen.last, ['work']);
      await subscription.cancel();
    });
  });
}
