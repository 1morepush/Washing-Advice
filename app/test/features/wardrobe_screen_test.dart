/// The wardrobe screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/features/wardrobe/wardrobe_screen.dart';

void main() {
  late InMemoryWardrobeRepository repository;

  setUp(() => repository = InMemoryWardrobeRepository());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [wardrobeRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: WardrobeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the items already in the wardrobe', (tester) async {
    await repository.saveAll([
      _item(id: 'a', name: 'Charcoal merino jumper'),
      _item(id: 'b', name: 'White cotton tee'),
    ]);

    await pump(tester);

    // The screen must show what is already stored on its very first frame.
    // A list that only fills in after the next write would look empty on
    // launch, which is what this catches.
    expect(find.text('Charcoal merino jumper'), findsOneWidget);
    expect(find.text('White cotton tee'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('an empty wardrobe says so rather than spinning', (tester) async {
    await pump(tester);

    expect(find.text('Your wardrobe is empty'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a filter that matches nothing offers to clear itself', (
    tester,
  ) async {
    await repository.save(_item(id: 'a', name: 'Charcoal merino jumper'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeRepositoryProvider.overrideWithValue(repository),
          wardrobeQueryProvider.overrideWith(
            (ref) => const WardrobeQuery(text: 'nothing matches this'),
          ),
        ],
        child: const MaterialApp(home: WardrobeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Distinct from an empty wardrobe: the user has items, and telling them
    // they own nothing would be both wrong and alarming.
    expect(find.text('Nothing matches'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
  });
}

WardrobeItem _item({required String id, required String name}) {
  final now = DateTime.utc(2026, 8, 5);
  return WardrobeItem(
    id: ItemId(id),
    name: name,
    type: Confident(
      ItemType.sweater,
      confidence: 0.9,
      source: Provenance.aiInference,
    ),
    composition: Confident(
      FabricComposition(const {Fiber.wool: 100}),
      confidence: 0.9,
      source: Provenance.tagScan,
    ),
    colors: Confident(
      ColorPalette([ItemColor.fromHex('#3C3F44', name: 'Charcoal')]),
      confidence: 0.9,
      source: Provenance.aiInference,
    ),
    care: const CareProfile.unknown(),
    addedAt: now,
    updatedAt: now,
  );
}
