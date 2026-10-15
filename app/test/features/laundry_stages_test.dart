/// Laundry in three stages, with the pile photo where laundry happens.
///
/// There were four tabs, the first of them the wardrobe again, and on a phone
/// the fourth was cut off the edge. These pin the three that remain, that they
/// fit the narrowest screen at large text, and that "Photograph a pile" moved
/// here from the wardrobe rather than being copied.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/laundry/laundry_screen.dart';
import 'package:washing_advice/features/pile/pile_screen.dart';
import 'package:washing_advice/main.dart';

import '../support/fixtures.dart';

void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final repository = InMemoryWardrobeRepository();
    await repository.save(confidentItem(id: 'a', name: 'Blue jumper'));
    await repository.save(
      confidentItem(
        id: 'b',
        name: 'Basket shirt',
      ).copyWith(lifecycle: LifecycleState.inLaundry),
    );
    container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(
          SettingsStore(await SharedPreferences.getInstance()),
        ),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        outfitRepositoryProvider.overrideWithValue(InMemoryOutfitRepository()),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WashingAdviceApp(initialLocation: '/laundry'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows exactly three stages: Basket, Washing, Drying', (
    tester,
  ) async {
    await open(tester);

    final tabs = tester.widgetList<Tab>(find.byType(Tab)).toList();
    expect(tabs.map((t) => t.text), [
      startsWith('Basket'),
      startsWith('Washing'),
      startsWith('Drying'),
    ]);
    expect(find.textContaining('Clean'), findsNothing);
    expect(find.textContaining('To wash'), findsNothing);
  });

  testWidgets('opens on the basket, with its count', (tester) async {
    await open(tester);

    expect(find.text('Basket (1)'), findsOneWidget);
    expect(find.text('Photograph a pile'), findsOneWidget);
    expect(find.text('What did you wear today?'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('all three fit 320 dp wide at ${scale}x text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, size: const Size(320, 640));

      expect(tester.takeException(), isNull);
      for (final tab in tester.widgetList<Tab>(find.byType(Tab))) {
        final box = tester.getRect(find.byWidget(tab));
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(320));
      }
    });
  }

  testWidgets('the pile photo opens from here and Back returns here', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Photograph a pile'));
    await tester.pumpAndSettle();
    expect(find.byType(PileScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(LaundryScreen), findsOneWidget);
  });

  testWidgets('and the wardrobe no longer offers it', (tester) async {
    await open(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Wardrobe'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sort laundry'), findsNothing);
    expect(find.text('Photograph a pile'), findsNothing);
  });
}
