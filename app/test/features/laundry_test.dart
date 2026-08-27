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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/widgets/item_thumbnail.dart';
import 'package:washing_advice/features/laundry/laundry_screen.dart';
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

  group('taking a garment back out', () {
    /// Pumps the laundry screen on the tab for [pile].
    Future<void> openOn(WidgetTester tester, String tab) async {
      // Wide enough for all four tabs at once. The tab bar scrolls on a real
      // phone, and a test that had to drag it before every assertion would be
      // testing the tab bar rather than the thing under it.
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LaundryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }

    testWidgets('the load to run shows each garment, not just its name', (
      tester,
    ) async {
      // This card is read with a basket in front of you. Matching "heathered
      // dark grey activewear pants" to the right pair by reading meant
      // scrolling past the card to the list below and back up again, once per
      // garment.
      final item = await save('tee');
      await controller().move([item.id], LifecycleState.inLaundry);

      await openOn(tester, 'To wash (1)');

      // Two: one in the load card, one in the list of what is in the basket.
      expect(find.byType(ItemThumbnail), findsNWidgets(2));
      expect(find.text('Start this load'), findsOneWidget);
    });

    testWidgets('the basket lets go of something put there by mistake', (
      tester,
    ) async {
      // The gap this fills. A garment in the basket had no way back out at
      // all — the only control on the row was the one that did not exist.
      final item = await save('tee');
      await controller().move([item.id], LifecycleState.inLaundry);

      await openOn(tester, 'To wash (1)');
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take out of the laundry'));
      await tester.pumpAndSettle();

      expect(
        (await repository.byId(item.id))!.lifecycle,
        LifecycleState.active,
      );
    });

    testWidgets('and so does the machine', (tester) async {
      final item = await save('tee');
      await controller().move([item.id], LifecycleState.beingWashed);

      await openOn(tester, 'Washing (1)');
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take out of the laundry'));
      await tester.pumpAndSettle();

      expect(
        (await repository.byId(item.id))!.lifecycle,
        LifecycleState.active,
      );
    });

    testWidgets('a jumper still damp can go back to the basket', (
      tester,
    ) async {
      final item = await save('jumper');
      await controller().move([item.id], LifecycleState.beingDried);

      await openOn(tester, 'Drying (1)');
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to the basket'));
      await tester.pumpAndSettle();

      expect(
        (await repository.byId(item.id))!.lifecycle,
        LifecycleState.inLaundry,
      );
    });

    testWidgets('the clean pile has nothing extra to offer', (tester) async {
      // It is the wardrobe. "Take out of the laundry" on a garment that is
      // not in the laundry would be a control that does nothing.
      await save('tee');

      await openOn(tester, 'Clean (1)');

      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('the basket cannot be moved into the drum by hand', (
      tester,
    ) async {
      // Starting a wash records it, and "times washed" and every later fading
      // judgement rest on that record. A hand move would put the garment in
      // the drum with no record at all, so it is deliberately not offered.
      final item = await save('tee');
      await controller().move([item.id], LifecycleState.inLaundry);

      await openOn(tester, 'To wash (1)');
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Move to washing'), findsNothing);
      expect(find.textContaining('drum'), findsNothing);
    });
  });
}
