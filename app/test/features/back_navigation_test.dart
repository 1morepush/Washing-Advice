/// Back goes back.
///
/// Every screen used to be reached with `go`, which replaces the stack, and
/// carried a hand-written Back arrow that jumped to a fixed place. So a garment
/// opened from Laundry went "back" to the wardrobe, and on Android the system
/// gesture left the app from anywhere. Detail screens are now pushed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/laundry/evening_nudge.dart';
import 'package:washing_advice/features/laundry/laundry_screen.dart';
import 'package:washing_advice/features/laundry/worn_today_screen.dart';
import 'package:washing_advice/features/stains/stain_screen.dart';
import 'package:washing_advice/features/wardrobe/item_detail_screen.dart';
import 'package:washing_advice/features/wardrobe/wardrobe_screen.dart';
import 'package:washing_advice/main.dart';

import '../support/fixtures.dart';
import '../support/recording_nudges.dart';

void main() {
  late RecordingNudges nudges;
  late ProviderContainer container;
  late InMemoryWardrobeRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    nudges = RecordingNudges();
    repository = InMemoryWardrobeRepository();
    await repository.save(confidentItem(id: 'a', name: 'Blue jumper'));
    container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(
          SettingsStore(await SharedPreferences.getInstance()),
        ),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        outfitRepositoryProvider.overrideWithValue(InMemoryOutfitRepository()),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        nudgesProvider.overrideWithValue(nudges),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> open(WidgetTester tester, {String location = '/'}) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: WashingAdviceApp(initialLocation: location),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> backArrow(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  testWidgets('wardrobe, garment, stain, and back twice', (tester) async {
    await open(tester);
    expect(find.byType(WardrobeScreen), findsOneWidget);

    await tester.tap(find.text('Blue jumper'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailScreen), findsOneWidget);

    await tester.tap(find.text('Spilled something?'));
    await tester.pumpAndSettle();
    expect(find.byType(StainScreen), findsOneWidget);

    await backArrow(tester);
    expect(find.byType(StainScreen), findsNothing);
    expect(find.byType(ItemDetailScreen), findsOneWidget);

    await backArrow(tester);
    expect(find.byType(ItemDetailScreen), findsNothing);
    expect(find.byType(WardrobeScreen), findsOneWidget);
  });

  testWidgets('a garment opened from laundry goes back to laundry', (
    tester,
  ) async {
    await repository.save(
      confidentItem(
        id: 'b',
        name: 'Basket shirt',
        lifecycle: LifecycleState.inLaundry,
      ),
    );
    await open(tester, location: '/laundry');

    await tester.tap(find.widgetWithText(ListTile, 'Basket shirt').first);
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailScreen), findsOneWidget);

    await backArrow(tester);
    expect(find.byType(LaundryScreen), findsOneWidget);
  });

  testWidgets('the system back gesture pops a pushed screen', (tester) async {
    await open(tester);
    await tester.tap(find.text('Blue jumper'));
    await tester.pumpAndSettle();

    // What Android's back button does: ask the platform to pop the route.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(ItemDetailScreen), findsNothing);
    expect(find.byType(WardrobeScreen), findsOneWidget);
  });

  testWidgets('a garment opened directly still has a way back', (tester) async {
    await open(tester, location: '/item/a');
    expect(find.byType(ItemDetailScreen), findsOneWidget);

    await backArrow(tester);
    expect(find.byType(WardrobeScreen), findsOneWidget);
  });

  testWidgets('worn today has a back button', (tester) async {
    await open(tester, location: '/laundry');
    await tester.tap(find.text('What did you wear today?'));
    await tester.pumpAndSettle();
    expect(find.byType(WornTodayScreen), findsOneWidget);

    await backArrow(tester);
    expect(find.byType(LaundryScreen), findsOneWidget);
  });

  testWidgets('the reminder still opens worn today, with laundry behind it', (
    tester,
  ) async {
    await open(tester);

    nudges.tapped.add(eveningNudge.route);
    await tester.pumpAndSettle();
    expect(find.byType(WornTodayScreen), findsOneWidget);

    await backArrow(tester);
    expect(find.byType(LaundryScreen), findsOneWidget);
  });
}
