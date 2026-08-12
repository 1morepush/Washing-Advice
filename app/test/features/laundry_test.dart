/// Moving garments between the wardrobe, the basket and the machine.
///
/// The grouping engine is tested in the core and is not re-tested here. What
/// this covers is the wiring either side of it: that putting something in the
/// basket actually reaches the plan, that starting a load leaves the clothes in
/// the machine *and* the wash in the history, and that the two never happen
/// separately — a load recorded but not moved leaves the app thinking it
/// washed clothes that are still in the basket, and a load moved but not
/// recorded loses the only evidence the wash happened at all.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/features/laundry/laundry_controller.dart';

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
        // No machine configured, which is a supported state throughout: the
        // sorter still groups and states requirements, it just cannot name a
        // programme. Left unoverridden these reach SharedPreferences.
        washerBrandProvider.overrideWith((ref) => null),
        dryerBrandProvider.overrideWith((ref) => null),
        customWasherProvider.overrideWith((ref) => null),
        customDryerProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(container.dispose);
  });

  LaundryController controller() => container.read(laundryControllerProvider);

  /// Reads a pile, waiting for the underlying stream to deliver.
  Future<List<WardrobeItem>> pile(LifecycleState stage) async {
    await container.read(ownedItemsProvider.future);
    return container.read(pileProvider(stage)).valueOrNull ?? [];
  }

  Future<WardrobeItem> save(String id, {String? name}) async {
    final item = confidentItem(id: id, name: name ?? 'Cotton tee');
    await repository.save(item);
    return item;
  }

  test('a garment put in the basket leaves the clean pile for it', () async {
    final item = await save('tee');
    expect(await pile(LifecycleState.active), hasLength(1));

    await controller().move([item.id], LifecycleState.inLaundry);

    expect(await pile(LifecycleState.active), isEmpty);
    expect(await pile(LifecycleState.inLaundry), hasLength(1));
  });

  test('it is still owned, so the wardrobe does not appear to lose it', () async {
    // The whole wardrobe reads through `WardrobeQuery.owned()`. A laundry state
    // missing from it would make clothes vanish the moment they got dirty.
    final item = await save('tee');
    await controller().move([item.id], LifecycleState.beingWashed);

    final owned = await container.read(ownedItemsProvider.future);
    expect(owned.map((i) => i.id), contains(item.id));
  });

  test('the move is in the history, not only in the row', () async {
    final item = await save('tee');

    await controller().move([item.id], LifecycleState.inLaundry);

    final events = await log.all();
    expect(
      events.whereType<LifecycleChanged>().map((e) => e.to),
      contains(LifecycleState.inLaundry),
    );
  });

  test('a garment that no longer exists is skipped, not fatal', () async {
    // A bulk move of a dozen things must not fail wholesale because one of
    // them was retired on another device.
    final item = await save('tee');

    await controller().move([
      item.id,
      const ItemId('gone'),
    ], LifecycleState.inLaundry);

    expect(await pile(LifecycleState.inLaundry), hasLength(1));
  });

  test('a move that makes no sense is refused', () async {
    final item = await save('tee');
    await repository.save(
      item.copyWith(
        lifecycle: LifecycleState.discarded,
        updatedAt: item.addedAt,
      ),
    );

    await controller().move([item.id], LifecycleState.inLaundry);

    expect(
      (await repository.byId(item.id))!.lifecycle,
      LifecycleState.discarded,
    );
  });

  group('the plan', () {
    test('covers what is in the basket', () async {
      final tee = await save('tee');
      await save('jeans', name: 'Blue jeans');
      await controller().move([tee.id], LifecycleState.inLaundry);
      await container.read(ownedItemsProvider.future);

      final plan = container.read(laundryPlanProvider).valueOrNull!;

      expect(
        [for (final load in plan.loads) ...load.items.map((i) => i.id)],
        [tee.id],
      );
    });

    test('does not re-plan what is already in the machine', () async {
      // Something turning in the drum is being washed, not waiting to be.
      // Planning it into a second load would tell the user to wash it twice.
      final tee = await save('tee');
      await controller().move([tee.id], LifecycleState.beingWashed);
      await container.read(ownedItemsProvider.future);

      final plan = container.read(laundryPlanProvider).valueOrNull!;

      expect(plan.loads, isEmpty);
    });
  });

  group('starting a load', () {
    Future<LaundryLoad> plannedLoad() async {
      final tee = await save('tee');
      await controller().move([tee.id], LifecycleState.inLaundry);
      await container.read(ownedItemsProvider.future);
      return container.read(laundryPlanProvider).valueOrNull!.loads.single;
    }

    test('puts the clothes in the machine', () async {
      final load = await plannedLoad();

      await controller().start(load);

      expect(await pile(LifecycleState.inLaundry), isEmpty);
      expect(await pile(LifecycleState.beingWashed), hasLength(1));
    });

    test('records the wash at the same time', () async {
      // Recorded at the start because this is the last moment the settings are
      // known — once it is running, the machine is just a set of items and
      // nothing says which load they were.
      final load = await plannedLoad();

      await controller().start(load);

      expect((await log.all()).whereType<ItemWashed>(), hasLength(1));
    });

    test(
      'the garment comes back out of the machine into the wardrobe',
      () async {
        final load = await plannedLoad();
        await controller().start(load);
        final id = load.items.single.id;

        await controller().move([id], LifecycleState.beingDried);
        expect(await pile(LifecycleState.beingDried), hasLength(1));

        await controller().move([id], LifecycleState.active);
        expect(await pile(LifecycleState.active), hasLength(1));
        expect(await pile(LifecycleState.beingDried), isEmpty);
      },
    );
  });
}
