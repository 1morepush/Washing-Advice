/// What happens to saved outfits when a garment leaves the wardrobe.
///
/// `OutfitRepository.removeItem` was written, tested against both
/// implementations, and never called. The gap was invisible: outfits kept
/// pointing at donated garments and the only symptom was a card with a missing
/// thumbnail, months later.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/core/router.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late InMemoryOutfitRepository outfits;
  late ProviderContainer container;

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    outfits = InMemoryOutfitRepository();
    await repository.saveAll([
      confidentItem(id: 'tee', name: 'White tee'),
      confidentItem(id: 'jeans', name: 'Blue jeans', type: ItemType.jeans),
      confidentItem(id: 'jacket', name: 'Jacket', type: ItemType.jacket),
    ]);

    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        outfitRepositoryProvider.overrideWithValue(outfits),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
      ],
    );
  });

  tearDown(() => container.dispose());

  Outfit outfit(String id, List<String> items) => Outfit(
    id: OutfitId(id),
    name: id,
    itemIds: [for (final item in items) ItemId(item)],
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 8, 1),
  );

  /// Drives the real edit screen to a new lifecycle and saves.
  Future<void> setLifecycle(WidgetTester tester, LifecycleState to) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          // The real router: saving navigates away, and a bare `home:` has no
          // GoRouter for it to navigate with.
          routerConfig: buildRouter(initialLocation: '/item/tee/edit'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<LifecycleState>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(to.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('donating a garment removes it from the outfits that held it', (
    tester,
  ) async {
    await outfits.save(outfit('o1', ['tee', 'jeans', 'jacket']));

    await setLifecycle(tester, LifecycleState.donated);

    final stored = (await outfits.byId(const OutfitId('o1')))!;
    expect([for (final i in stored.itemIds) i.value], ['jeans', 'jacket']);
  });

  testWidgets('an outfit left with one garment is deleted', (tester) async {
    await outfits.save(outfit('o1', ['tee', 'jeans']));

    await setLifecycle(tester, LifecycleState.discarded);

    expect(await outfits.byId(const OutfitId('o1')), isNull);
  });

  testWidgets('putting something in the laundry leaves outfits alone', (
    tester,
  ) async {
    // The predicate is `isOwned`, not `isWearable`, and the difference is the
    // whole point: a shirt in the basket is not wearable this minute and is
    // back on Tuesday. Stripping it from every saved outfit would be a worse
    // bug than the one this feature fixes.
    await outfits.save(outfit('o1', ['tee', 'jeans']));

    await setLifecycle(tester, LifecycleState.inLaundry);

    final stored = (await outfits.byId(const OutfitId('o1')))!;
    expect(stored.size, 2);
  });

  testWidgets('storing something away also leaves outfits alone', (
    tester,
  ) async {
    // Off-season storage is still ownership. The winter coat belongs in the
    // winter outfit in June.
    await outfits.save(outfit('o1', ['tee', 'jeans']));

    await setLifecycle(tester, LifecycleState.stored);

    expect((await outfits.byId(const OutfitId('o1')))!.size, 2);
  });

  testWidgets('outfits that never held it are untouched', (tester) async {
    await outfits.save(outfit('o1', ['tee', 'jeans']));
    await outfits.save(outfit('o2', ['jeans', 'jacket']));

    await setLifecycle(tester, LifecycleState.sold);

    expect((await outfits.byId(const OutfitId('o2')))!.size, 2);
  });
}
