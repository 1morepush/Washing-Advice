/// The loop between recording a wear and suggesting an outfit.
///
/// The two halves have existed separately for a while: the app records wears,
/// and the builder accepts a relationship graph. Nothing connected them, so
/// the builder never learned anything from use. What is under test here is
/// specifically the wiring — the projection's own behaviour is covered in the
/// core, and the point of this file is that the app actually asks for it and
/// notices when it changes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/features/history/wear_recorder.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late InMemoryEventLog events;
  late ProviderContainer container;

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    events = InMemoryEventLog();
    await repository.saveAll([
      confidentItem(id: 'tee-a', name: 'Tee A'),
      confidentItem(id: 'tee-b', name: 'Tee B'),
      confidentItem(id: 'jeans', name: 'Jeans', type: ItemType.jeans),
    ]);

    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(events),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'ev'),
        ),
        washerBrandProvider.overrideWith((ref) => 'Bosch'),
        dryerBrandProvider.overrideWith((ref) => null),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<RelationshipGraph> graph() =>
      container.read(coWearGraphProvider.future);

  /// One occasion: several items tapped in one sitting, on a given day.
  ///
  /// Days apart, because wearing the same combination twice in an evening is
  /// one outfit — which is what the projection says, and is right.
  Future<void> wearTogether(List<String> ids, {required int daysAgo}) async {
    final recorder = container.read(wearRecorderProvider);
    final at = DateTime.now().subtract(Duration(days: daysAgo));
    for (final id in ids) {
      await recorder.recordWear(ItemId(id), at: at);
    }
  }

  test('a fresh wardrobe has nothing to learn from', () async {
    // And the builder still works: suggestions come from colour and usage
    // until there is history, rather than waiting for it.
    expect((await graph()).isEmpty, isTrue);

    await container.read(ownedItemsProvider.future);
    expect(container.read(outfitSuggestionsProvider).requireValue, isNotEmpty);
  });

  test('recorded wears become links the builder can use', () async {
    // Twice, because one co-wear is a coincidence and the projection says so.
    await wearTogether(['tee-b', 'jeans'], daysAgo: 14);
    await wearTogether(['tee-b', 'jeans'], daysAgo: 7);

    final learned = await graph();
    expect(learned.neighbours(const ItemId('tee-b')), {const ItemId('jeans')});
  });

  test('the graph is dropped when a wear is appended', () async {
    // A fold over the whole log is stale the moment anything lands in it. If
    // this regresses, the app learns exactly once and then never again.
    expect((await graph()).isEmpty, isTrue);

    await wearTogether(['tee-b', 'jeans'], daysAgo: 14);
    await wearTogether(['tee-b', 'jeans'], daysAgo: 7);

    expect((await graph()).isEmpty, isFalse);
  });

  test('what was recorded changes what is suggested', () async {
    // The whole point. Two interchangeable tees; the one actually worn with
    // the jeans should lead.
    container.read(outfitRequestProvider.notifier).state = const OutfitRequest(
      includeFootwear: false,
    );

    await wearTogether(['tee-b', 'jeans'], daysAgo: 14);
    await wearTogether(['tee-b', 'jeans'], daysAgo: 7);
    await graph();
    await container.read(ownedItemsProvider.future);

    final suggestions = container.read(outfitSuggestionsProvider).requireValue;
    expect(suggestions.first.itemIds.map((i) => i.value), contains('tee-b'));
    expect(
      suggestions.first.reasons,
      contains(contains('worn these together')),
    );
  });

  test('a wash does not create a co-wear link', () async {
    // Only ItemWorn counts. Everything in a load was washed together, which
    // says nothing whatever about what is worn together — and a load is
    // exactly the kind of large simultaneous batch that would otherwise
    // manufacture edges between every pair in it.
    final recorder = container.read(wearRecorderProvider);
    // Built by the real sorter rather than by hand, so the load under test is
    // the shape the app actually produces.
    final plan = container
        .read(laundrySorterProvider)
        .sort(await repository.query(const WardrobeQuery.launderable()));

    expect(plan.loads, isNotEmpty);
    for (var i = 0; i < 3; i++) {
      for (final load in plan.loads) {
        await recorder.recordWash(load);
      }
    }

    expect((await graph()).isEmpty, isTrue);
  });
}
