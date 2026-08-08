/// Deleting an item, as opposed to retiring it.
///
/// Retiring (`retiring_an_item_test.dart`) moves an item to a terminal
/// lifecycle state and keeps it — its history and photos stay, because the
/// point is statistics over garments that are gone. Deleting has no lifecycle
/// to move to: the record itself should never have existed, so it and
/// everything it produced — photos, cutouts, outfit membership — go too.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/router.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late InMemoryOutfitRepository outfits;
  late MemoryImageStore images;
  late ProviderContainer container;

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    outfits = InMemoryOutfitRepository();
    images = MemoryImageStore();

    final frontUri = await images.save(
      Uint8List.fromList([1, 2, 3]),
      name: 'tee-front',
    );
    final cutoutUri = await images.save(
      Uint8List.fromList([4, 5, 6]),
      name: 'tee-front-cutout',
    );
    final backUri = await images.save(
      Uint8List.fromList([7, 8, 9]),
      name: 'tee-back',
    );

    final tee = confidentItem(id: 'tee', name: 'White tee').copyWith(
      photos: PhotoSet([
        ItemPhoto(
          uri: frontUri,
          cutoutUri: cutoutUri,
          role: PhotoRole.front,
          capturedAt: DateTime.utc(2026, 8, 5),
        ),
        ItemPhoto(
          uri: backUri,
          role: PhotoRole.back,
          capturedAt: DateTime.utc(2026, 8, 5),
        ),
      ]),
    );

    await repository.saveAll([
      tee,
      confidentItem(id: 'jeans', name: 'Blue jeans', type: ItemType.jeans),
    ]);

    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        outfitRepositoryProvider.overrideWithValue(outfits),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(images),
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

  /// Drives the real detail screen: open its overflow menu, choose Delete,
  /// confirm the dialog.
  Future<void> deleteFromDetailScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: buildRouter(initialLocation: '/item/tee'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // The confirmation dialog's own button, distinct from the menu item of
    // the same word — matched by type so tapping the wrong "Delete" can't
    // pass this test by accident.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
  }

  testWidgets('deleting removes the item from the wardrobe', (tester) async {
    await deleteFromDetailScreen(tester);

    expect(await repository.byId(const ItemId('tee')), isNull);
    expect(await repository.byId(const ItemId('jeans')), isNotNull);
  });

  testWidgets('deleting frees every photo the item held, cutout included', (
    tester,
  ) async {
    expect(images.length, 3);

    await deleteFromDetailScreen(tester);

    expect(images.length, 0);
  });

  testWidgets('deleting drops the item from the outfits that held it', (
    tester,
  ) async {
    // Three members, so the outfit survives losing one — a fair test of
    // "dropped from" as distinct from the next test's "the outfit itself
    // goes too".
    await repository.save(
      confidentItem(id: 'jacket', name: 'Jacket', type: ItemType.jacket),
    );
    await outfits.save(outfit('o1', ['tee', 'jeans', 'jacket']));

    await deleteFromDetailScreen(tester);

    final stored = (await outfits.byId(const OutfitId('o1')))!;
    expect([for (final i in stored.itemIds) i.value], ['jeans', 'jacket']);
  });

  testWidgets('an outfit left with one garment is deleted too', (tester) async {
    // The same "fewer than two members" cleanup retiring already relies on
    // (`retiring_an_item_test.dart`), exercised here for delete's own call
    // site rather than assumed to carry over.
    await outfits.save(outfit('o1', ['tee', 'jeans']));

    await deleteFromDetailScreen(tester);

    expect(await outfits.byId(const OutfitId('o1')), isNull);
  });

  testWidgets('backing out of the confirmation keeps the item', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: buildRouter(initialLocation: '/item/tee'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(await repository.byId(const ItemId('tee')), isNotNull);
    expect(images.length, 3);
  });
}
