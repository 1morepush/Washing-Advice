/// Saving an outfit, and what happens to it afterwards.
///
/// The repository's own behaviour is covered by the core's contract suite,
/// run against both implementations. What is under test here is the part only
/// the app decides: that saving asks for a name and never demands one, that a
/// saved outfit's wear count answers a question the per-item log cannot, and
/// that deleting is reachable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/outfits/outfit_controller.dart';
import 'package:washing_advice/features/outfits/outfits_screen.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late InMemoryOutfitRepository outfits;
  late InMemoryEventLog events;
  late ProviderContainer container;

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    outfits = InMemoryOutfitRepository();
    events = InMemoryEventLog();
    await repository.saveAll([
      confidentItem(id: 'tee', name: 'Cream tee', hex: '#F2E8D5'),
      confidentItem(id: 'jeans', name: 'Navy jeans', type: ItemType.jeans),
    ]);

    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        outfitRepositoryProvider.overrideWithValue(outfits),
        eventLogProvider.overrideWithValue(events),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'o'),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OutfitsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> saveFirstSuggestion(WidgetTester tester, {String? name}) async {
    await tester.tap(find.widgetWithText(TextButton, 'Save').first);
    await tester.pumpAndSettle();
    if (name != null) await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('saving asks for a name', (tester) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Save').first);
    await tester.pumpAndSettle();

    expect(find.text('Save this outfit'), findsOneWidget);
  });

  testWidgets('a name given is the name kept', (tester) async {
    await pump(tester);
    await saveFirstSuggestion(tester, name: 'Saturday');

    final stored = await outfits.all();
    expect(stored.single.name, 'Saturday');
    expect(stored.single.itemIds, hasLength(greaterThanOrEqualTo(2)));
  });

  testWidgets('an empty name falls back to the garments themselves', (
    tester,
  ) async {
    // Saving must never be blocked on typing. "Cream tee + Navy jeans" is what
    // someone would say out loud, and it beats both an error and a serial
    // number.
    await pump(tester);
    await saveFirstSuggestion(tester);

    final stored = await outfits.all();
    expect(stored.single.name, contains('+'));
    expect(stored.single.name, isNot(contains('o-')));
  });

  testWidgets('backing out of the dialog saves nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Save').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(await outfits.all(), isEmpty);
  });

  testWidgets('a saved outfit appears under Saved', (tester) async {
    await pump(tester);
    await saveFirstSuggestion(tester, name: 'Saturday');

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();

    expect(find.text('Saturday'), findsOneWidget);
    expect(find.textContaining('not worn yet'), findsOneWidget);
  });

  testWidgets('wearing a saved outfit counts the outfit, not just the items', (
    tester,
  ) async {
    // The number a per-item log cannot produce: it knows the tee and the jeans
    // were worn on the same day, not that they were worn together *as this
    // outfit*.
    await pump(tester);
    await saveFirstSuggestion(tester, name: 'Saturday');

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Wearing this'));
    await tester.pumpAndSettle();

    expect((await outfits.all()).single.usage.timesWorn, 1);
    // And the items were logged too, at one instant, so the co-wear projection
    // reads it as one occasion.
    final logged = await events.all();
    expect(logged, hasLength(2));
    expect(logged.map((e) => e.occurredAt).toSet(), hasLength(1));
  });

  testWidgets('saving is separate from wearing', (tester) async {
    // Keeping an outfit is not the same as putting it on, and collapsing the
    // two would make the wear count meaningless.
    await pump(tester);
    await saveFirstSuggestion(tester, name: 'Saturday');

    expect(await events.all(), isEmpty);
    expect((await outfits.all()).single.usage.timesWorn, 0);
  });

  testWidgets('an empty saved tab says what to do about it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing saved yet'), findsOneWidget);
  });

  test('deleting removes it from the list', () async {
    // Driven through the controller rather than the popup menu: what matters
    // is the effect, and menu mechanics are Flutter's business.
    final controller = container.read(outfitControllerProvider);
    await outfits.save(
      Outfit(
        id: const OutfitId('o1'),
        name: 'Saturday',
        itemIds: const [ItemId('tee'), ItemId('jeans')],
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
      ),
    );

    await controller.delete(const OutfitId('o1'));
    expect(await outfits.all(), isEmpty);
  });

  test('renaming keeps the same outfit rather than making a new one', () async {
    final controller = container.read(outfitControllerProvider);
    final outfit = Outfit(
      id: const OutfitId('o1'),
      name: 'Saturday',
      itemIds: const [ItemId('tee'), ItemId('jeans')],
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    );
    await outfits.save(outfit);

    await controller.rename(outfit, 'Sunday');

    final stored = await outfits.all();
    expect(stored, hasLength(1));
    expect(stored.single.name, 'Sunday');
    expect(stored.single.id, const OutfitId('o1'));
  });

  test('a blank rename is ignored rather than blanking the name', () async {
    final controller = container.read(outfitControllerProvider);
    final outfit = Outfit(
      id: const OutfitId('o1'),
      name: 'Saturday',
      itemIds: const [ItemId('tee'), ItemId('jeans')],
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    );
    await outfits.save(outfit);

    await controller.rename(outfit, '   ');

    expect((await outfits.all()).single.name, 'Saturday');
  });
}
