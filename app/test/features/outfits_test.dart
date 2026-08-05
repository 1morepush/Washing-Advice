/// The outfits screen.
///
/// The ranking is the core's business and is tested there. What matters here
/// is that the reasoning reaches the screen — a suggestion the user cannot
/// argue with is one they will either obey blindly or ignore.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/outfits/outfits_screen.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
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

  testWidgets('a wardrobe of only tops explains what is missing', (
    tester,
  ) async {
    // "No results" would leave someone guessing. The requirement is nameable,
    // so it gets named.
    await repository.saveAll([confidentItem(id: 'tee', name: 'White tee')]);

    await pump(tester);

    expect(find.textContaining('top and a bottom'), findsOneWidget);
  });

  testWidgets('a suggestion shows both halves and its reasoning', (
    tester,
  ) async {
    await repository.saveAll([
      confidentItem(
        id: 'tee',
        name: 'Cream tee',
        hex: '#F2E8D5',
        usage: const UsageStats.none(),
      ),
      confidentItem(
        id: 'jeans',
        name: 'Navy jeans',
        type: ItemType.jeans,
        hex: '#1F2A44',
      ),
    ]);

    await pump(tester);

    expect(find.text('Cream tee'), findsOneWidget);
    expect(find.text('Navy jeans'), findsOneWidget);
    expect(find.textContaining('never been worn'), findsOneWidget);
  });

  testWidgets('switching occasion re-asks the question', (tester) async {
    await repository.saveAll([
      confidentItem(id: 'hoodie', name: 'Grey hoodie', type: ItemType.hoodie),
      confidentItem(id: 'jeans', name: 'Navy jeans', type: ItemType.jeans),
    ]);

    await pump(tester);
    expect(find.text('Grey hoodie'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Formal'));
    await tester.pumpAndSettle();

    // A hoodie is not a formal option, and the screen says so rather than
    // showing it anyway.
    expect(find.text('Grey hoodie'), findsNothing);
    expect(find.textContaining('Nothing for formal'), findsOneWidget);
  });

  testWidgets('a tagged item overrides the occasion default', (tester) async {
    await repository.saveAll([
      confidentItem(
        id: 'hoodie',
        name: 'Grey hoodie',
        type: ItemType.hoodie,
        tags: {'formal'},
      ),
      // Trousers rather than jeans: the tag lifts the hoodie into the
      // occasion, but an outfit still needs a bottom that belongs there, and
      // jeans do not.
      confidentItem(
        id: 'trousers',
        name: 'Grey trousers',
        type: ItemType.trousers,
      ),
    ]);

    await pump(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Formal'));
    await tester.pumpAndSettle();

    expect(find.text('Grey hoodie'), findsOneWidget);
  });
}
