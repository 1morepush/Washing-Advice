/// Which pictures open the viewer, and by which gesture.
///
/// The rule: where a picture did nothing before, a tap enlarges it; where a
/// tap already meant something (open the garment, pick it for today), a
/// long-press enlarges and the tap keeps its meaning. The viewer itself is
/// held in `widgets/photo_viewer_test.dart`.
///
/// Against the old code every test here fails, because no picture opened
/// anything: the Laundry and load-card tests find no `EnlargeOnTap`, and the
/// long-press tests would have found no viewer. The "tap keeps its meaning"
/// halves of the outfit and Worn Today tests are the ones that would have
/// passed, and are there to stop the new gesture taking the old one's place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/outfits/outfit_pieces.dart';
import 'package:washing_advice/features/pile/widgets/load_card.dart';
import 'package:washing_advice/features/wardrobe/item_detail_screen.dart';
import 'package:washing_advice/main.dart';
import 'package:washing_advice/widgets/item_thumbnail.dart';
import 'package:washing_advice/widgets/photo_viewer.dart';
import 'package:washing_advice/widgets/rinse_kit.dart';

import '../support/fixtures.dart';
import '../support/photos.dart';

void main() {
  late MemoryImageStore store;
  late InMemoryWardrobeRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = MemoryImageStore();
    repository = InMemoryWardrobeRepository();
  });

  ProviderContainer containerFor(SharedPreferences prefs) {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        outfitRepositoryProvider.overrideWithValue(InMemoryOutfitRepository()),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> openApp(
    WidgetTester tester,
    String location, {
    Size size = const Size(400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = containerFor(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: WashingAdviceApp(initialLocation: location),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<WardrobeItem> saved(
    WidgetTester tester,
    String id,
    String name, {
    LifecycleState lifecycle = LifecycleState.active,
    bool photo = true,
    List<PhotoRole> roles = const [PhotoRole.front],
  }) async {
    var item = confidentItem(id: id, name: name, lifecycle: lifecycle);
    if (photo) {
      item = await photographed(tester, store, item, roles: roles);
    }
    await repository.save(item);
    return item;
  }

  Finder viewerClose() => find.byTooltip('Close');

  /// The enlargeable picture of the garment called [name].
  Finder thumbOf(String name) => find.byWidgetPredicate(
    (w) => w is EnlargeOnTap && w.item.displayName == name,
    description: 'enlargeable picture of $name',
  );

  group('a load card', () {
    testWidgets('a tap on a garment picture opens the viewer on that garment', (
      tester,
    ) async {
      await saved(
        tester,
        'b',
        'Basket shirt',
        lifecycle: LifecycleState.inLaundry,
      );
      await openApp(tester, '/laundry');

      final inCard = find.descendant(
        of: find.byType(LoadCard),
        matching: thumbOf('Basket shirt'),
      );
      expect(inCard, findsOneWidget);
      // Still the 40dp picture it was, in a 48dp target.
      expect(
        tester.getSize(
          find.descendant(of: inCard, matching: find.byType(ItemThumbnail)),
        ),
        const Size(40, 40),
      );
      expect(tester.getSize(inCard).height, greaterThanOrEqualTo(48));

      await tester.tap(inCard);
      await settleImages(tester);

      expect(viewerClose(), findsOneWidget);
      expect(find.text('Open garment'), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);
    });

    testWidgets('close button, back and a tap on the black all return', (
      tester,
    ) async {
      await saved(
        tester,
        'b',
        'Basket shirt',
        lifecycle: LifecycleState.inLaundry,
      );
      await openApp(tester, '/laundry');
      final inCard = find.descendant(
        of: find.byType(LoadCard),
        matching: thumbOf('Basket shirt'),
      );

      Future<void> openViewer() async {
        await tester.tap(inCard);
        await settleImages(tester);
        expect(viewerClose(), findsOneWidget);
      }

      Future<void> expectBackOnTheCard() async {
        await tester.pumpAndSettle();
        expect(viewerClose(), findsNothing);
        expect(find.byType(LoadCard), findsOneWidget);
      }

      await openViewer();
      await tester.tap(viewerClose());
      await expectBackOnTheCard();

      await openViewer();
      await tester.binding.handlePopRoute();
      await expectBackOnTheCard();

      await openViewer();
      await tester.tapAt(const Offset(3, 3));
      await tester.pump(const Duration(milliseconds: 400));
      await expectBackOnTheCard();
    });

    testWidgets('Open garment lands on the garment page', (tester) async {
      await saved(
        tester,
        'b',
        'Basket shirt',
        lifecycle: LifecycleState.inLaundry,
      );
      await openApp(tester, '/laundry');
      await tester.tap(
        find.descendant(
          of: find.byType(LoadCard),
          matching: thumbOf('Basket shirt'),
        ),
      );
      await settleImages(tester);

      await tester.tap(find.text('Open garment'));
      await tester.pumpAndSettle();

      expect(viewerClose(), findsNothing);
      expect(find.byType(ItemDetailScreen), findsOneWidget);
    });
  });

  group('the Laundry stage lists', () {
    Future<void> openWashing(WidgetTester tester) async {
      await openApp(tester, '/laundry');
      await tester.tap(find.byType(StagePill).at(1));
      await tester.pumpAndSettle();
    }

    testWidgets('the picture enlarges and does not open the garment', (
      tester,
    ) async {
      await saved(
        tester,
        'w',
        'Washing shirt',
        lifecycle: LifecycleState.beingWashed,
      );
      await openWashing(tester);

      await tester.tap(thumbOf('Washing shirt'));
      await settleImages(tester);

      expect(viewerClose(), findsOneWidget);
      expect(find.byType(ItemDetailScreen), findsNothing);

      await tester.tap(viewerClose());
      await tester.pumpAndSettle();
      expect(find.byType(ItemDetailScreen), findsNothing);
    });

    testWidgets('the rest of the row still opens the garment', (tester) async {
      await saved(
        tester,
        'w',
        'Washing shirt',
        lifecycle: LifecycleState.beingWashed,
      );
      await openWashing(tester);

      await tester.tap(find.text('Washing shirt'));
      await tester.pumpAndSettle();

      expect(viewerClose(), findsNothing);
      expect(find.byType(ItemDetailScreen), findsOneWidget);
    });
  });

  group('the garment page', () {
    testWidgets('its picture enlarges, without an Open garment button', (
      tester,
    ) async {
      await saved(tester, 'a', 'Blue jumper');
      await openApp(tester, '/item/a');

      await tester.tap(thumbOf('Blue jumper'));
      await settleImages(tester);

      expect(viewerClose(), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.text('Open garment'), findsNothing);
    });

    testWidgets('a garment without a photo still opens, saying so', (
      tester,
    ) async {
      await saved(tester, 'a', 'Blue jumper', photo: false);
      await openApp(tester, '/item/a');

      await tester.tap(thumbOf('Blue jumper'));
      await settleImages(tester);

      expect(find.text('No photo yet'), findsOneWidget);
    });
  });

  group('where a tap already means something', () {
    testWidgets('Worn Today: a long-press enlarges, a tap still picks', (
      tester,
    ) async {
      await saved(tester, 'a', 'Navy hoodie');
      await saved(tester, 'b', 'Stone chinos');
      await openApp(tester, '/laundry/worn');
      expect(find.text('Pick what you wore'), findsOneWidget);

      await tester.tap(thumbOf('Navy hoodie'));
      await tester.pumpAndSettle();
      expect(viewerClose(), findsNothing);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('Log 1 and put it in the basket'), findsOneWidget);

      await tester.longPress(thumbOf('Stone chinos'));
      await settleImages(tester);
      expect(viewerClose(), findsOneWidget);
      await tester.tap(viewerClose());
      await tester.pumpAndSettle();
      // The long-press did not also pick it.
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('an outfit piece: a long-press enlarges, a tap opens it', (
      tester,
    ) async {
      final jumper = await photographed(
        tester,
        store,
        confidentItem(id: 'a', name: 'Blue jumper'),
      );
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(body: OutfitPieces(items: [jumper])),
          ),
          GoRoute(
            path: '/item/:id',
            builder: (_, state) => Scaffold(
              body: Text('Garment page ${state.pathParameters['id']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [imageStoreProvider.overrideWithValue(store)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      await tester.longPress(thumbOf('Blue jumper'));
      await settleImages(tester);
      expect(viewerClose(), findsOneWidget);
      expect(find.text('Garment page a'), findsNothing);

      await tester.tap(viewerClose());
      await tester.pumpAndSettle();
      await tester.tap(thumbOf('Blue jumper'));
      await tester.pumpAndSettle();
      expect(viewerClose(), findsNothing);
      expect(find.text('Garment page a'), findsOneWidget);
    });
  });
}
