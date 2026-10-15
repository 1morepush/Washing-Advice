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
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/router.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/features/laundry/evening_nudge.dart';
import 'package:washing_advice/features/more/more_screen.dart';
import 'package:washing_advice/features/pile/pile_screen.dart';
import 'package:washing_advice/features/scan/crop_screen.dart';
import 'package:washing_advice/features/scan/scan_controller.dart';
import 'package:washing_advice/features/scan/scan_screen.dart';
import 'package:washing_advice/features/settings/settings_screen.dart';
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
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource([
            const ScanImage(bytes: [1, 2, 3]),
          ]),
        ),
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

  testWidgets('settings pushed from the pile has a back arrow', (tester) async {
    await open(tester, location: '/pile');
    await tester.tap(find.text('Set your machine to get exact programs'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byTooltip('Open navigation menu'), findsNothing);

    await backArrow(tester);
    expect(find.byType(PileScreen), findsOneWidget);
  });

  testWidgets('settings opened by address has a way out to More', (
    tester,
  ) async {
    await open(tester, location: '/settings');

    expect(find.byTooltip('Open navigation menu'), findsNothing);
    await backArrow(tester);
    expect(find.byType(MoreScreen), findsOneWidget);
  });

  group('the scan screen forgets its photos when left', () {
    Future<void> collectOnePhoto(WidgetTester tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Add garments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('One garment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      expect(container.read(scanControllerProvider), isA<ScanCollecting>());
    }

    testWidgets('by the Back arrow', (tester) async {
      await collectOnePhoto(tester);

      await backArrow(tester);

      expect(find.byType(ScanScreen), findsNothing);
      expect(container.read(scanControllerProvider), isA<ScanIdle>());
    });

    testWidgets('by the system gesture', (tester) async {
      await collectOnePhoto(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(ScanScreen), findsNothing);
      expect(container.read(scanControllerProvider), isA<ScanIdle>());
    });

    testWidgets('but not when a screen on top of it is closed', (tester) async {
      await collectOnePhoto(tester);

      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(find.byType(CropScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(CropScreen), findsNothing);
      expect(find.byType(ScanScreen), findsOneWidget);
      expect(container.read(scanControllerProvider), isA<ScanCollecting>());
    });
  });

  test('the address bar follows pushed screens', () {
    // Off by default in go_router, which left the browser on `/` after a push
    // and made a reload or a shared link of a pushed screen open the wrong one.
    GoRouter.optionURLReflectsImperativeAPIs = false;
    buildRouter().dispose();
    expect(GoRouter.optionURLReflectsImperativeAPIs, isTrue);
  });
}
