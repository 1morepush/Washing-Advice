/// The photo viewer and the wrapper that opens it.
///
/// What is held here is the viewer's own behaviour: how it opens and closes,
/// pages between photographs, zooms, and what it shows when there is nothing
/// to show. Which pictures in the app open it, and by which gesture, is held
/// beside each screen in `enlarge_photos_test.dart`.
///
/// None of this could fail against the old code in the usual sense: neither
/// `showPhotoViewer` nor `EnlargeOnTap` existed, so every test here is new
/// ground rather than a regression guard.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/widgets/garment_glyph.dart';
import 'package:washing_advice/widgets/item_thumbnail.dart';
import 'package:washing_advice/widgets/photo_viewer.dart';

import '../support/fixtures.dart';
import '../support/photos.dart';

/// What the address bar would say: the top route, imperative or not.
String _addressOf(GoRouter router) {
  final matches = router.routerDelegate.currentConfiguration;
  final last = matches.last;
  return (last is ImperativeRouteMatch ? last.matches.uri : matches.uri)
      .toString();
}

void main() {
  late MemoryImageStore store;

  late GoRouter router;

  setUp(() => store = MemoryImageStore());

  /// A screen of 40dp thumbnails, one per item, each wrapped to enlarge.
  Future<void> host(
    WidgetTester tester,
    List<WardrobeItem> items, {
    ThemeData? theme,
    Size size = const Size(400, 800),
    double textScale = 1,
    bool longPress = false,
    bool offerOpen = true,
    String location = '/',
    bool saveItems = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = InMemoryWardrobeRepository();
    if (saveItems) {
      for (final item in items) {
        await repository.save(item);
      }
    }
    router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/photo/:id',
          pageBuilder: (context, state) => photoViewerPage(
            context,
            state,
            PhotoViewerScreen(
              id: ItemId(state.pathParameters['id']!),
              page: int.tryParse(state.uri.queryParameters['page'] ?? '') ?? 0,
              offerOpen: state.uri.queryParameters['open'] != '0',
            ),
          ),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    for (final item in items)
                      EnlargeOnTap(
                        item: item,
                        onLongPress: longPress,
                        offerOpen: offerOpen,
                        child: ItemThumbnail(item: item, size: 40),
                      ),
                  ],
                ),
              ),
            ),
          ),
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
        overrides: [
          imageStoreProvider.overrideWithValue(store),
          wardrobeRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          theme: theme,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, WardrobeItem item) async {
    await tester.tap(find.byType(EnlargeOnTap).first);
    await settleImages(tester);
  }

  WardrobeItem base({String name = 'Charcoal jumper', String id = 'a'}) =>
      confidentItem(id: id, name: name, type: ItemType.sweater);

  double zoomOf(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  Offset photoCentre(WidgetTester tester) =>
      tester.getCenter(find.byType(RawImage));

  group('opening and closing', () {
    testWidgets('a tap opens the viewer on the garment; three ways close it', (
      tester,
    ) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item]);
      expect(find.byTooltip('Close'), findsNothing);

      await open(tester, item);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('Charcoal jumper'), findsOneWidget);
      // What it is, under the name, as the garment page words it.
      expect(find.text(garmentSubtitle(item)), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);

      // The close button.
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsNothing);

      // The system back gesture.
      await open(tester, item);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsNothing);

      // The empty black round the picture.
      await open(tester, item);
      await tester.tapAt(const Offset(3, 3));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsNothing);
    });

    testWidgets('a tap on the photograph itself does not close it', (
      tester,
    ) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item]);
      await open(tester, item);

      await tester.tapAt(photoCentre(tester));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('the letterbox beside a tall photograph closes it', (
      tester,
    ) async {
      final item = await photographed(tester, store, base(), shape: (100, 400));
      await host(tester, [item]);
      await open(tester, item);

      // Far left of centre, where a 1:4 picture on a 400dp screen is not.
      await tester.tapAt(Offset(8, photoCentre(tester).dy));
      // Past the window a double-tap would need, then the exit.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Close'), findsNothing);
    });

    testWidgets('the close button is at least 48dp and labelled', (
      tester,
    ) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item]);
      await open(tester, item);

      final size = tester.getSize(find.byTooltip('Close'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('Escape closes it', (tester) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item]);
      await open(tester, item);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Close'), findsNothing);
    });
  });

  group('Open garment', () {
    testWidgets('closes the viewer and lands on the garment page', (
      tester,
    ) async {
      final item = await photographed(tester, store, base(id: 'jumper'));
      await host(tester, [item]);
      await open(tester, item);

      await tester.tap(find.text('Open garment'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Close'), findsNothing);
      expect(find.text('Garment page jumper'), findsOneWidget);
    });

    testWidgets('replaces the viewer, so Back from the garment skips it', (
      tester,
    ) async {
      final item = await photographed(tester, store, base(id: 'jumper'));
      await host(tester, [item]);
      await open(tester, item);

      // A rapid double tap must not push the garment twice.
      final button = find.text('Open garment');
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Garment page jumper'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Garment page jumper'), findsNothing);
      expect(find.byTooltip('Close'), findsNothing);
      expect(find.byType(EnlargeOnTap), findsOneWidget);
    });

    testWidgets('is not offered when the picture is on the garment page', (
      tester,
    ) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item], offerOpen: false);
      await open(tester, item);

      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('Open garment'), findsNothing);
    });
  });

  group('as a route', () {
    testWidgets('the address names the garment and the photograph', (
      tester,
    ) async {
      final item = await photographed(
        tester,
        store,
        base(id: 'jumper'),
        roles: [PhotoRole.front, PhotoRole.back],
      );
      await host(tester, [item]);
      String here() => _addressOf(router);
      expect(here(), '/');

      await open(tester, item);
      expect(here(), '/photo/jumper');

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settleImages(tester);
      expect(here(), '/photo/jumper?page=1');
      expect(find.text('Back'), findsOneWidget);

      // One step back leaves the viewer, however many photographs were paged.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(here(), '/');
      expect(find.byTooltip('Close'), findsNothing);
    });

    testWidgets('a picture met on the garment page keeps that in the address', (
      tester,
    ) async {
      final item = await photographed(tester, store, base(id: 'jumper'));
      await host(tester, [item], offerOpen: false);
      await open(tester, item);

      expect(_addressOf(router), '/photo/jumper?open=0');
    });

    testWidgets('opening the address directly shows the photograph', (
      tester,
    ) async {
      final item = await photographed(
        tester,
        store,
        base(id: 'jumper'),
        roles: [PhotoRole.front, PhotoRole.back],
      );
      await host(tester, [item], location: '/photo/jumper?page=1');
      await settleImages(tester);

      expect(find.byType(RawImage), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Open garment'), findsOneWidget);
    });

    testWidgets('with nothing beneath it the X goes to the garment page', (
      tester,
    ) async {
      final item = await photographed(tester, store, base(id: 'jumper'));
      await host(tester, [item], location: '/photo/jumper');
      await settleImages(tester);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Garment page jumper'), findsOneWidget);
    });

    testWidgets('a garment that no longer exists says so, with a way out', (
      tester,
    ) async {
      await host(tester, [], location: '/photo/gone');
      await tester.pumpAndSettle();

      expect(find.text('This item no longer exists.'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Garment page gone'), findsOneWidget);
    });

    testWidgets('closing lets go of the decoded photograph', (tester) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item]);
      await settleImages(tester);
      final cache = PaintingBinding.instance.imageCache;
      final before = cache.currentSizeBytes;

      await open(tester, item);
      expect(cache.currentSizeBytes, greaterThan(before));

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(cache.currentSizeBytes, before);
    });
  });

  group('photographs', () {
    testWidgets('shows the original, not the cutout, when both exist', (
      tester,
    ) async {
      final item = await photographed(tester, store, base(), cutouts: true);
      await host(tester, [item]);
      await open(tester, item);

      // The fixture's original is 300px wide and its cutout 150.
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image!.width, 300);
    });

    testWidgets('falls back to the cutout when the original is gone', (
      tester,
    ) async {
      final item = await photographed(tester, store, base(), cutouts: true);
      await tester.runAsync(() => store.delete(item.photos.photos.single.uri));
      await host(tester, [item]);
      await open(tester, item);

      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image!.width, 150);
      expect(find.text('Could not load this photo'), findsNothing);
    });

    testWidgets('says so, with the garment, when nothing can be read', (
      tester,
    ) async {
      final item = await photographed(tester, store, base());
      await tester.runAsync(() => store.delete(item.photos.photos.single.uri));
      await host(tester, [item]);
      await open(tester, item);

      expect(find.text('Could not load this photo'), findsOneWidget);
      expect(find.byType(GarmentGlyph), findsWidgets);
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a huge photograph is decoded no larger than 2048px', (
      tester,
    ) async {
      final item = await photographed(
        tester,
        store,
        base(),
        shape: (4096, 2048),
      );
      await host(tester, [item]);
      await open(tester, item);

      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(image.width, 2048);
      // The shape is kept, not squared.
      expect(image.height, 1024);
    });

    testWidgets('a garment with no photograph shows its glyph and says so', (
      tester,
    ) async {
      final item = base();
      await host(tester, [item]);
      await open(tester, item);

      expect(find.text('No photo yet'), findsOneWidget);
      expect(find.byType(GarmentGlyph), findsWidgets);
      expect(find.byType(InteractiveViewer), findsNothing);
      // No action that does not exist in the app today.
      expect(find.textContaining('Take'), findsNothing);
      expect(find.byTooltip('Zoom in'), findsNothing);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('the picture says what it is to a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final item = await photographed(
        tester,
        store,
        base(),
        roles: [PhotoRole.back],
      );
      await host(tester, [item]);
      await open(tester, item);

      expect(
        find.bySemanticsLabel('Photo of Charcoal jumper, Back'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('several photographs', () {
    Future<WardrobeItem> two(WidgetTester tester) => photographed(
      tester,
      store,
      base(),
      roles: [PhotoRole.front, PhotoRole.back],
    );

    testWidgets('swiping changes the page indicator and the role', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final item = await two(tester);
      await host(tester, [item]);
      await open(tester, item);

      expect(find.text('Front'), findsOneWidget);
      expect(find.bySemanticsLabel('Photo 1 of 2'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settleImages(tester);

      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Front'), findsNothing);
      expect(find.bySemanticsLabel('Photo 2 of 2'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('one photograph has no indicator', (tester) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item]);
      await open(tester, item);

      expect(find.byKey(const ValueKey('photo-viewer-dots')), findsNothing);
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('zoom is back to whole on the next photograph', (tester) async {
      final item = await two(tester);
      await host(tester, [item]);
      await open(tester, item);

      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(zoomOf(tester), greaterThan(1.5));

      // Zoomed in, a drag pans; it must not slide to the next picture.
      await tester.drag(find.byType(InteractiveViewer), const Offset(-300, 0));
      await settleImages(tester);
      expect(find.text('Front'), findsOneWidget);

      await tester.tap(find.byTooltip('Zoom out'));
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settleImages(tester);

      expect(find.text('Back'), findsOneWidget);
      expect(zoomOf(tester), 1);
    });

    testWidgets('opens on the photograph the thumbnail showed', (tester) async {
      final item = await two(tester);
      final back = item.photos.photos.last;
      final primary = item.copyWith(
        photos: PhotoSet([
          item.photos.photos.first,
          back.copyWith(isPrimary: true),
        ]),
      );
      await host(tester, [primary]);
      await open(tester, primary);

      expect(find.text('Back'), findsOneWidget);
    });
  });

  group('zoom', () {
    testWidgets('pinch zoom is limited to 1x..5x', (tester) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item]);
      await open(tester, item);

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.minScale, 1);
      expect(viewer.maxScale, 5);
      expect(viewer.scaleEnabled, isTrue);
    });

    testWidgets('a double-tap zooms in and a second zooms out', (tester) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item]);
      await open(tester, item);
      expect(zoomOf(tester), 1);

      Future<void> doubleTap() async {
        final at = photoCentre(tester);
        await tester.tapAt(at);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(at);
        await tester.pump(const Duration(milliseconds: 400));
      }

      await doubleTap();
      expect(zoomOf(tester), closeTo(2.5, 0.01));
      expect(find.byTooltip('Close'), findsOneWidget);

      await doubleTap();
      expect(zoomOf(tester), 1);
    });

    testWidgets('the zoom buttons step to the limits and stop there', (
      tester,
    ) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item]);
      await open(tester, item);

      IconButton button(String tooltip) => tester.widget<IconButton>(
        find.widgetWithIcon(
          IconButton,
          tooltip == 'Zoom in' ? Icons.add : Icons.remove,
        ),
      );

      expect(button('Zoom out').onPressed, isNull, reason: 'already whole');
      for (var i = 0; i < 4; i++) {
        if (button('Zoom in').onPressed != null) {
          await tester.tap(find.byTooltip('Zoom in'));
          await tester.pump();
        }
      }
      expect(zoomOf(tester), 5);
      expect(button('Zoom in').onPressed, isNull, reason: 'at the limit');

      final size = tester.getSize(find.byTooltip('Zoom out'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('the mouse wheel zooms', (tester) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item]);
      await open(tester, item);

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(photoCentre(tester)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
      await tester.pump();

      expect(zoomOf(tester), greaterThan(1));
    });
  });

  group('the wrapper', () {
    testWidgets('keeps a 40dp thumbnail 40dp and gives it a 48dp target', (
      tester,
    ) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item]);

      final thumb = tester.getRect(find.byType(ItemThumbnail));
      expect(thumb.size, const Size(40, 40));

      final target = tester.getRect(find.byType(EnlargeOnTap));
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));
      expect(target.center, thumb.center);

      // A press in the margin, outside the 40dp picture, still opens it.
      await tester.tapAt(thumb.topLeft - const Offset(3, 3));
      await settleImages(tester);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('a long-press variant ignores a tap and answers a long-press', (
      tester,
    ) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item], longPress: true);

      await tester.tap(find.byType(EnlargeOnTap));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsNothing);

      await tester.longPress(find.byType(EnlargeOnTap));
      await settleImages(tester);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('speaks as a button, with a custom action for long-press', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final item = await photographed(tester, store, base());
      await host(tester, [item], longPress: true);

      final node = tester.getSemantics(
        find.bySemanticsLabel('Enlarge photo of Charcoal jumper'),
      );
      expect(node.flagsCollection.isButton, isTrue);
      final actions = node.getSemanticsData().customSemanticsActionIds;
      expect(actions, isNotEmpty);
      expect(
        CustomSemanticsAction.getAction(actions!.single)!.label,
        'Enlarge photo',
      );
      semantics.dispose();
    });
  });

  group('layout', () {
    final themes = <String, ThemeData Function()>{
      'light': AppTheme.light,
      'dark': AppTheme.dark,
      'amoled': AppTheme.amoled,
    };

    for (final MapEntry(key: mode, value: build) in themes.entries) {
      testWidgets('at 320dp and text scale 2 in $mode nothing overflows', (
        tester,
      ) async {
        final item = await photographed(
          tester,
          store,
          base(
            name:
                'Heathered dark grey merino wool activewear pants with a '
                'very long name indeed',
          ),
          roles: [PhotoRole.front, PhotoRole.careTag],
        );
        await host(
          tester,
          [item],
          theme: build(),
          size: const Size(320, 640),
          textScale: 2,
        );
        await open(tester, item);

        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Close'), findsOneWidget);
        expect(find.text('Open garment'), findsOneWidget);
        // One line, cut off with an ellipsis rather than wrapped.
        final name = tester.widget<Text>(find.textContaining('Heathered'));
        expect(name.maxLines, 1);
        expect(name.overflow, TextOverflow.ellipsis);
        // The controls stay on the screen.
        final screen = Offset.zero & const Size(320, 640);
        for (final finder in [
          find.byTooltip('Close'),
          find.text('Open garment'),
          find.byTooltip('Zoom in'),
          find.byTooltip('Zoom out'),
        ]) {
          expect(screen.contains(tester.getRect(finder).topLeft), isTrue);
          expect(screen.contains(tester.getRect(finder).bottomRight), isTrue);
        }
      });

      testWidgets('the no-photo state renders in $mode', (tester) async {
        final item = base();
        await host(
          tester,
          [item],
          theme: build(),
          size: const Size(320, 640),
          textScale: 2,
        );
        await open(tester, item);

        expect(tester.takeException(), isNull);
        expect(find.text('No photo yet'), findsOneWidget);
      });
    }

    testWidgets('the ground is black whatever the appearance', (tester) async {
      final item = await photographed(tester, store, base());
      await host(tester, [item], theme: AppTheme.light());
      await open(tester, item);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
      expect(scaffold.backgroundColor, Colors.black);
    });
  });
}
