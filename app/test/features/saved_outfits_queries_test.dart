/// How many lookups it takes to draw the saved outfits.
///
/// Each card used to fetch its outfit and then every garment in it, one at a
/// time, so the cost of the list grew with outfits times pieces. The garments
/// are now asked for once, together.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/outfits/outfits_screen.dart';

import '../support/fixtures.dart';

/// A repository that counts single and batched lookups.
class _CountingRepository implements WardrobeRepository {
  final InMemoryWardrobeRepository inner = InMemoryWardrobeRepository();
  int byIdCalls = 0;
  int byIdsCalls = 0;

  @override
  Future<WardrobeItem?> byId(ItemId id) {
    byIdCalls++;
    return inner.byId(id);
  }

  @override
  Future<List<WardrobeItem>> byIds(Iterable<ItemId> ids) {
    byIdsCalls++;
    return inner.byIds(ids);
  }

  @override
  Future<List<WardrobeItem>> query(WardrobeQuery query) => inner.query(query);

  @override
  Future<int> count(WardrobeQuery query) => inner.count(query);

  @override
  Future<void> save(WardrobeItem item) => inner.save(item);

  @override
  Future<void> saveAll(Iterable<WardrobeItem> items) => inner.saveAll(items);

  @override
  Future<void> delete(ItemId id) => inner.delete(id);

  @override
  Stream<List<WardrobeItem>> watch(WardrobeQuery query) => inner.watch(query);

  @override
  Future<List<String>> knownBrands() => inner.knownBrands();

  @override
  Future<List<String>> knownCountries() => inner.knownCountries();
}

void main() {
  testWidgets('three saved outfits of four pieces are one batched lookup', (
    tester,
  ) async {
    final repository = _CountingRepository();
    final outfits = InMemoryOutfitRepository();
    final ids = [for (var i = 0; i < 6; i++) ItemId('g$i')];
    await repository.saveAll([
      for (final id in ids)
        confidentItem(id: id.value, name: 'Piece ${id.value}'),
    ]);
    for (var i = 0; i < 3; i++) {
      await outfits.save(
        Outfit(
          id: OutfitId('o$i'),
          name: 'Outfit $i',
          itemIds: [for (var j = 0; j < 4; j++) ids[(i + j) % ids.length]],
          createdAt: DateTime.utc(2026, 8, 1),
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );
    }

    final container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        outfitRepositoryProvider.overrideWithValue(outfits),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
      ],
    );
    addTearDown(container.dispose);

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
    repository.byIdCalls = 0;
    repository.byIdsCalls = 0;

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();

    expect(find.text('Outfit 0'), findsOneWidget);
    expect(find.text('Outfit 2'), findsOneWidget);
    expect(repository.byIdCalls, 0);
    expect(repository.byIdsCalls, 1);
  });
}
