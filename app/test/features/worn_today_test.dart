/// Saying what you wore, at the front door, tired.
///
/// The feature is not the recording — the app could already do that, twice
/// over, on two different screens. The feature is the *ordering*, because the
/// whole thing fails the same way: somebody scrolls for a shirt, gives up, and
/// throws the clothes in the pile unrecorded. So what is worth protecting is
/// that the likely answers are at the top before any scrolling happens, and
/// that one tap does both halves of the job.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/features/history/wear_recorder.dart';
import 'package:washing_advice/features/laundry/worn_today_controller.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late InMemoryEventLog log;
  late ProviderContainer container;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    log = InMemoryEventLog();
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(log),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'worn'),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  WornTodayController controller() =>
      container.read(wornTodayControllerProvider.notifier);
  WornTodayState state() => container.read(wornTodayControllerProvider);

  /// Waits for the controller's initial load.
  Future<void> settle() => controller().ready;

  Future<WardrobeItem> save(
    String id, {
    String name = 'Garment',
    UsageStats usage = const UsageStats(),
    LifecycleState lifecycle = LifecycleState.active,
  }) async {
    final item = confidentItem(
      id: id,
      name: name,
      usage: usage,
      lifecycle: lifecycle,
    );
    await repository.save(item);
    return item;
  }

  List<String> namesInOrder() => [
    for (final candidate in state().candidates) candidate.item.displayName,
  ];

  group('what gets offered', () {
    test('only what is in the wardrobe', () async {
      // A garment already in the basket cannot have been worn today and put
      // in the basket, and offering it would spend the top of the list on an
      // answer that is already recorded.
      await save('clean', name: 'Clean tee');
      await save(
        'dirty',
        name: 'Dirty tee',
        lifecycle: LifecycleState.inLaundry,
      );
      await settle();

      expect(namesInOrder(), ['Clean tee']);
    });

    test('a wardrobe with no history still lists everything', () async {
      // The first week. No wears, no co-wear graph, nothing to rank on — the
      // screen must still be usable rather than empty.
      await save('a', name: 'Alpha');
      await save('b', name: 'Beta');
      await settle();

      expect(state().candidates, hasLength(2));
    });
  });

  group('the ordering', () {
    test('something due a wash outranks something fresh', () async {
      // `wearsSinceWash` is the domain's own answer to "does this need
      // washing", so it is evidence about what is being taken off right now.
      await save('fresh', name: 'Fresh');
      await save(
        'third-wear',
        name: 'Third wear',
        usage: const UsageStats(timesWorn: 3, wearsSinceWash: 3),
      );
      await settle();

      expect(namesInOrder().first, 'Third wear');
    });

    test(
      'something worn yesterday outranks something worn last month',
      () async {
        await save(
          'recent',
          name: 'Recent',
          usage: UsageStats(
            timesWorn: 2,
            lastWornAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
        );
        await save(
          'stale',
          name: 'Stale',
          usage: UsageStats(
            timesWorn: 2,
            lastWornAt: DateTime.now().subtract(const Duration(days: 40)),
          ),
        );
        await settle();

        expect(namesInOrder().first, 'Recent');
      },
    );

    test('ties break by name rather than by database order', () async {
      // So an unscored wardrobe is at least stable. A list that reshuffles
      // between openings is one nobody learns the shape of.
      await save('z', name: 'Zebra print');
      await save('a', name: 'Aran jumper');
      await settle();

      expect(namesInOrder(), ['Aran jumper', 'Zebra print']);
    });
  });

  group('picking one changes what is offered', () {
    /// A wardrobe where 'trousers' and 'shirt' have been worn together.
    Future<void> wornTogether() async {
      await save('trousers', name: 'Work trousers');
      await save('shirt', name: 'Blue shirt');
      // Ranked last on its own merits, so a co-wear lift is unmistakable.
      await save(
        'unrelated',
        name: 'Aaa unrelated',
        usage: const UsageStats(timesWorn: 30, wearsSinceWash: 2),
      );

      // Twice, on two occasions. The co-wear projection deliberately refuses
      // to believe a pair worn together once — two is the smallest number
      // that separates a habit from a coincidence, and a spurious edge here
      // would push a wrong garment to the top of a list somebody is tapping
      // without reading.
      final recorder = container.read(wearRecorderProvider);
      for (final daysAgo in [2, 5]) {
        await recorder.recordOutfit([
          const ItemId('trousers'),
          const ItemId('shirt'),
        ], at: DateTime.now().subtract(Duration(days: daysAgo)));
      }
      container.invalidate(coWearGraphProvider);
    }

    test('what you wear with it comes to the top', () async {
      await wornTogether();
      await settle();

      controller().toggle(const ItemId('trousers'));

      // First is the one just picked or the one it goes with; what matters is
      // that the shirt is above the garment with better raw statistics.
      final order = namesInOrder();
      expect(
        order.indexOf('Blue shirt'),
        lessThan(order.indexOf('Aaa unrelated')),
      );
    });

    test('and says why it moved', () async {
      // A list that reorders itself for no visible reason is unsettling. The
      // claim is one the user can check against their own memory.
      await wornTogether();
      await settle();

      controller().toggle(const ItemId('trousers'));

      final shirt = state().candidates.firstWhere(
        (c) => c.item.displayName == 'Blue shirt',
      );
      expect(shirt.wornWithPicked, isTrue);
    });

    test(
      'the garment you picked is not labelled as its own neighbour',
      () async {
        await wornTogether();
        await settle();

        controller().toggle(const ItemId('trousers'));

        final picked = state().candidates.firstWhere(
          (c) => c.item.id == const ItemId('trousers'),
        );
        expect(picked.wornWithPicked, isFalse);
      },
    );

    test('unpicking takes the lift away again', () async {
      await wornTogether();
      await settle();
      controller().toggle(const ItemId('trousers'));
      controller().toggle(const ItemId('trousers'));

      expect(state().selected, isEmpty);
      expect(state().candidates.every((c) => !c.wornWithPicked), isTrue);
    });
  });

  group('logging it', () {
    test('records the wear and moves it, in one action', () async {
      // Both, because they are one event to the person doing it. Either half
      // alone leaves the app lying: a shirt marked worn but still "available",
      // or a shirt in the basket with no evidence it was ever worn.
      final item = await save('tee', name: 'Grey tee');
      await settle();
      controller().toggle(item.id);

      await controller().commit();

      final saved = await repository.byId(item.id);
      expect(saved!.lifecycle, LifecycleState.inLaundry);
      expect(saved.usage.timesWorn, 1);
    });

    test('several become one occasion, not several', () async {
      // What makes the co-wear graph work at all — and therefore what puts
      // the right garments on screen tomorrow.
      final a = await save('a', name: 'Shirt');
      final b = await save('b', name: 'Trousers');
      await settle();
      controller().toggle(a.id);
      controller().toggle(b.id);

      await controller().commit();

      final worn = (await log.all()).whereType<ItemWorn>().toList();
      expect(worn, hasLength(2));
      expect(worn.first.occurredAt, worn.last.occurredAt);
    });

    test('it reports what it did', () async {
      final item = await save('tee');
      await settle();
      controller().toggle(item.id);

      await controller().commit();

      expect(state().saved, 1);
      expect(state().isDone, isTrue);
    });

    test('nothing picked does nothing', () async {
      await save('tee');
      await settle();

      await controller().commit();

      expect(state().isDone, isFalse);
      expect((await log.all()).whereType<ItemWorn>(), isEmpty);
    });
  });
}
