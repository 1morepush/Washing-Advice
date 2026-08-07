/// The filter sheet.
///
/// What is under test is that the sheet edits the query and the list obeys it.
/// The meaning of each filter is the core's business and is already covered by
/// `runRepositoryContractTests`; duplicating that here would be asserting the
/// same behaviour twice and pinning it in the wrong place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/features/wardrobe/filter_sheet.dart';
import 'package:washing_advice/features/wardrobe/wardrobe_screen.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late ProviderContainer container;

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    await repository.saveAll([
      _item(
        id: 'tee',
        name: 'White tee',
        type: ItemType.tShirt,
        brand: 'Uniqlo',
      ),
      _item(
        id: 'jumper',
        name: 'Wool jumper',
        type: ItemType.sweater,
        composition: {Fiber.wool: 100},
        isFavorite: true,
      ),
      _item(id: 'jeans', name: 'Blue jeans', type: ItemType.jeans),
    ]);
    container = ProviderContainer(
      overrides: [wardrobeRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: FilterSheet())),
      ),
    );
    await tester.pumpAndSettle();
  }

  WardrobeQuery query() => container.read(wardrobeQueryProvider);

  testWidgets('selecting a category narrows the query', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Tops'));
    await tester.pumpAndSettle();

    expect(query().categories, {ItemCategory.top});
  });

  testWidgets('deselecting removes it again', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Tops'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Tops'));
    await tester.pumpAndSettle();

    expect(query().categories, isEmpty);
  });

  testWidgets('favourites is a filter, and the list obeys it', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Favourites'));
    await tester.pumpAndSettle();

    expect(query().favouritesOnly, isTrue);

    final shown = await container
        .read(wardrobeRepositoryProvider)
        .query(query());
    expect([for (final i in shown) i.id.value], ['jumper']);
  });

  testWidgets('brands come from the wardrobe, not a fixed list', (
    tester,
  ) async {
    await pumpSheet(tester);

    // Offering brands the user does not own is a filter that returns nothing.
    expect(find.widgetWithText(FilterChip, 'Uniqlo'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Nike'), findsNothing);
  });

  testWidgets('sorting is single-select', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Name'));
    await tester.pumpAndSettle();
    expect(query().sort, WardrobeSort.nameAscending);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Most worn'));
    await tester.pumpAndSettle();
    expect(query().sort, WardrobeSort.mostWorn);
  });

  testWidgets('clearing returns to the baseline, not to an empty query', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Favourites'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();

    // An empty query would surface donated and discarded items, which is not
    // what "clear filters" means on a wardrobe screen.
    expect(query(), WardrobeScreen.baseline);
    expect(query().lifecycleStates, isNotEmpty);
  });

  testWidgets('the button says how many items match', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Favourites'));
    await tester.pumpAndSettle();

    // Worth knowing before the sheet closes: a combination matching nothing
    // should be discovered while the controls are still on screen.
    expect(find.text('Show 1 item'), findsOneWidget);
  });
}

WardrobeItem _item({
  required String id,
  required String name,
  required ItemType type,
  String? brand,
  Map<Fiber, int> composition = const {Fiber.cotton: 100},
  bool isFavorite = false,
}) {
  final now = DateTime.utc(2026, 8, 5);
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
    isFavorite: isFavorite,
    addedAt: now,
    updatedAt: now,
  );
}
