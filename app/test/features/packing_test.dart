/// The packing screen.
///
/// The quantities are the core's arithmetic and are tested there. Here: that
/// changing the trip changes the bag, that a shortfall is stated rather than
/// hidden, and that the laundry notes — the reason this screen exists rather
/// than a generic packing list — actually appear.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/packing/packing_screen.dart';

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
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PackingScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> stock() => repository.saveAll([
    for (var i = 0; i < 10; i++)
      confidentItem(id: 'top-$i', name: 'Tee $i', hex: '#1F2A44'),
    for (var i = 0; i < 4; i++)
      confidentItem(id: 'jeans-$i', name: 'Jeans $i', type: ItemType.jeans),
    for (var i = 0; i < 10; i++)
      confidentItem(id: 'pants-$i', name: 'Pants $i', type: ItemType.underwear),
    for (var i = 0; i < 10; i++)
      confidentItem(id: 'socks-$i', name: 'Socks $i', type: ItemType.socks),
    confidentItem(id: 'jacket', name: 'Jacket', type: ItemType.jacket),
    confidentItem(id: 'shoes', name: 'Trainers', type: ItemType.sneakers),
    confidentItem(id: 'pjs', name: 'Pyjamas', type: ItemType.pajamas),
  ]);

  int packedCount() =>
      container.read(packingListProvider).requireValue.items.length;

  testWidgets('a longer trip packs more', (tester) async {
    await stock();
    await pump(tester);

    final short = packedCount();

    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pumpAndSettle();

    expect(container.read(tripSpecProvider).days, greaterThan(5));
    expect(packedCount(), greaterThan(short));
  });

  testWidgets('laundry at the other end shrinks the bag', (tester) async {
    await stock();
    container.read(tripSpecProvider.notifier).state = const TripSpec(days: 14);
    await pump(tester);

    final withoutLaundry = packedCount();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(container.read(tripSpecProvider).laundryAvailable, isTrue);
    expect(packedCount(), lessThan(withoutLaundry));
  });

  testWidgets('a shortfall is stated, not hidden behind a short list', (
    tester,
  ) async {
    await repository.saveAll([
      confidentItem(id: 'tee', name: 'Only tee'),
      confidentItem(id: 'jeans', name: 'Only jeans', type: ItemType.jeans),
    ]);

    await pump(tester);

    expect(find.text('Short of a few things'), findsOneWidget);
    expect(find.textContaining('could supply'), findsOneWidget);
  });

  testWidgets('a long trip with no laundry says everything must last', (
    tester,
  ) async {
    await stock();
    container.read(tripSpecProvider.notifier).state = const TripSpec(days: 10);

    await pump(tester);

    expect(find.textContaining('No laundry planned'), findsOneWidget);
  });

  testWidgets('a bag spanning several piles warns about the washing', (
    tester,
  ) async {
    // The thing a wardrobe app knows and a packing app does not.
    await repository.saveAll([
      confidentItem(id: 'white', name: 'White tee', hex: '#F7F6F2'),
      confidentItem(id: 'black', name: 'Black tee', hex: '#111114'),
      confidentItem(id: 'red', name: 'Red tee', hex: '#C62828'),
      confidentItem(id: 'jeans', name: 'Jeans', type: ItemType.jeans),
    ]);
    container.read(tripSpecProvider.notifier).state = const TripSpec(
      days: 3,
      laundryAvailable: true,
    );

    await pump(tester);

    expect(find.textContaining('separate loads'), findsOneWidget);
  });
}
