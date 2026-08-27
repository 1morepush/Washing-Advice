/// What a screen shows when the thing behind it breaks.
///
/// Six screens used to render `Center(child: Text('$error'))`. When storage
/// genuinely failed — a browser out of quota, a database that would not open —
/// the app put a raw Dart exception in the middle of an otherwise finished
/// interface: no explanation, no next step, and a strong impression that the
/// whole thing had fallen over. The wardrobe screen had always handled this
/// properly, which is precisely why nobody noticed the others had not.
///
/// The exception itself is still shown, quietly and last. It is meaningless to
/// most people and the only useful thing in the world to whoever has to work
/// out what happened.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/insights/insights_screen.dart';
import 'package:washing_advice/features/outfits/outfits_screen.dart';
import 'package:washing_advice/features/packing/packing_screen.dart';
import 'package:washing_advice/features/wardrobe/edit_item_screen.dart';
import 'package:washing_advice/features/wardrobe/item_detail_screen.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(_BrokenRepository()),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        outfitRepositoryProvider.overrideWithValue(InMemoryOutfitRepository()),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        washerBrandProvider.overrideWith((ref) => null),
        dryerBrandProvider.overrideWith((ref) => null),
        customWasherProvider.overrideWith((ref) => null),
        customDryerProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Each screen, and the sentence it owes someone whose storage just failed.
  final screens = <String, (Widget, String)>{
    'insights': (const InsightsScreen(), 'Could not measure your wardrobe'),
    'packing': (const PackingScreen(), 'Could not work out what to pack'),
    'outfits': (const OutfitsScreen(), 'Could not suggest an outfit'),
    'item detail': (
      const ItemDetailScreen(id: ItemId('gone')),
      'Could not open this item',
    ),
    'edit': (
      const EditItemScreen(id: ItemId('gone')),
      'Could not open this item',
    ),
  };

  for (final entry in screens.entries) {
    final (screen, title) = entry.value;

    testWidgets('${entry.key} explains the failure rather than throwing it', (
      tester,
    ) async {
      await pump(tester, screen);

      expect(find.text(title), findsOneWidget);
      // And the raw exception is present, but not as the headline.
      expect(find.textContaining('storage is unavailable'), findsOneWidget);
    });
  }
}

/// Storage that fails the way a browser out of quota does: not by returning
/// nothing, but by refusing.
class _BrokenRepository implements WardrobeRepository {
  Never _fail() => throw const _StorageUnavailable();

  @override
  Future<WardrobeItem?> byId(ItemId id) async => _fail();

  @override
  Future<List<WardrobeItem>> query(WardrobeQuery query) async => _fail();

  @override
  Stream<List<WardrobeItem>> watch(WardrobeQuery query) =>
      Stream.error(const _StorageUnavailable());

  @override
  Future<void> save(WardrobeItem item) async => _fail();

  @override
  Future<void> saveAll(Iterable<WardrobeItem> items) async => _fail();

  @override
  Future<void> delete(ItemId id) async => _fail();

  @override
  Future<int> count(WardrobeQuery query) async => _fail();

  @override
  Future<List<String>> knownBrands() async => _fail();

  @override
  Future<List<String>> knownCountries() async => _fail();
}

class _StorageUnavailable implements Exception {
  const _StorageUnavailable();

  @override
  String toString() => 'storage is unavailable';
}
