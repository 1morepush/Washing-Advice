/// The cutout editor, driven through its real widget.
///
/// `mask_edit_test.dart` proves the compositing against pixels. What matters
/// here is the other half: that a drag on the actual canvas becomes a stroke,
/// that saving writes a cutout the item then points at, and that cancelling
/// writes nothing — an editor that silently commits on the way out is worse
/// than one that does not exist.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/wardrobe/mask_edit.dart';
import 'package:washing_advice/features/wardrobe/mask_editor_screen.dart';

import '../support/fixtures.dart';

Future<Uint8List> _png(Color colour, {int size = 40}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = colour,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  picture.dispose();
  image.dispose();
  return data.buffer.asUint8List();
}

void main() {
  const id = ItemId('tee');

  late InMemoryWardrobeRepository repository;
  late MemoryImageStore images;
  late ProviderContainer container;

  /// An item with a photograph, and a cutout only when [withCutout].
  ///
  /// Encoding a PNG is real engine work, so this has to be handed to
  /// [WidgetTester.runAsync] — under the test binding's fake clock
  /// `Picture.toImage` never completes and the test hangs rather than failing.
  Future<void> seed({required bool withCutout}) async {
    final photoUri = await images.save(
      await _png(const Color(0xFF204080)),
      name: 'tee-front',
    );
    final cutoutUri = withCutout
        ? await images.save(await _png(const Color(0xFF204080)), name: 'cut')
        : null;

    await repository.save(
      confidentItem(id: id.value, name: 'White cotton tee').copyWith(
        photos: PhotoSet([
          ItemPhoto(
            uri: photoUri,
            cutoutUri: cutoutUri,
            role: PhotoRole.front,
            capturedAt: DateTime.utc(2026, 1, 1),
          ),
        ]),
      ),
    );
  }

  setUp(() {
    repository = InMemoryWardrobeRepository();
    images = MemoryImageStore();
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(images),
      ],
    );
    addTearDown(container.dispose);
  });

  /// Lets whatever real engine work is outstanding finish, then shows it.
  ///
  /// `pumpAndSettle` is unusable here for two reasons that compound: the
  /// loading spinner animates forever, so nothing ever "settles"; and image
  /// decoding is genuine engine work that the binding's fake clock never runs,
  /// so it would hang rather than fail. `runAsync` steps outside the fake clock
  /// long enough for the engine to answer; the `pump` afterwards flushes the
  /// continuation, which was queued back in the fake zone.
  ///
  /// It alternates rather than doing one of each because the work is a *chain*
  /// — read, decode, read, decode — and each link is only started by the pump
  /// that delivers the one before it.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await tester.pump();
  }

  /// Opens the editor on the seeded item, loaded and ready to paint.
  ///
  /// Through a real router rather than `MaterialApp(home:)`, because both ways
  /// out of this screen navigate — a bare `home` would turn Cancel and Save
  /// into assertion failures instead of exercising them.
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/item/${id.value}/mask',
            routes: [
              GoRoute(
                path: '/item/:id',
                builder: (_, _) => const Scaffold(body: Text('the item')),
                routes: [
                  GoRoute(
                    path: 'mask',
                    builder: (_, state) => MaskEditorScreen(
                      id: ItemId(state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await drain(tester);
  }

  /// A drag across the middle of the canvas.
  Future<void> paintAcross(WidgetTester tester) async {
    final centre = tester.getCenter(find.byKey(maskCanvasKey));
    final gesture = await tester.startGesture(centre - const Offset(40, 0));
    await gesture.moveTo(centre);
    await gesture.moveTo(centre + const Offset(40, 0));
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a drag becomes a stroke that can be undone', (tester) async {
    await tester.runAsync(() => seed(withCutout: true));
    await open(tester);

    final undo = find.widgetWithIcon(IconButton, Icons.undo);
    expect(tester.widget<IconButton>(undo).onPressed, isNull);

    await paintAcross(tester);

    expect(tester.widget<IconButton>(undo).onPressed, isNotNull);
  });

  testWidgets('saving writes a cutout the item points at', (tester) async {
    await tester.runAsync(() => seed(withCutout: true));
    // The item starts *with* a cutout, so `hasCutout` afterwards would be true
    // whether or not saving did anything. What has to change is which file it
    // points at and what is in it.
    final before = (await repository.byId(id))!.photos.displayPhoto!.cutoutUri;

    await open(tester);
    await paintAcross(tester);

    await tester.tap(find.text('Save cutout'));
    // Rendering and encoding the PNG is real engine work, same as the load.
    await drain(tester);

    final photo = (await repository.byId(id))!.photos.displayPhoto!;
    expect(photo.cutoutUri, isNot(before));
    // Real bytes, not a pointer to something that was never written.
    expect(await images.read(photo.cutoutUri!), isNotNull);
    // And back on the item, rather than stranded on the editor.
    expect(find.text('the item'), findsOneWidget);
  });

  testWidgets('cancelling writes nothing', (tester) async {
    await tester.runAsync(() => seed(withCutout: true));
    final before = (await repository.byId(id))!.updatedAt;
    await open(tester);
    await paintAcross(tester);

    await tester.tap(find.text('Cancel'));
    await drain(tester);

    expect(find.text('the item'), findsOneWidget);
    expect((await repository.byId(id))!.updatedAt, before);
  });

  testWidgets('an item whose cutout failed opens ready to paint in', (
    tester,
  ) async {
    // The case most in need of a hand-drawn mask is the one where the remover
    // gave up entirely, so it must not be the one that refuses to open — and
    // there is nothing to rub out of an empty mask, so it opens on Restore.
    await tester.runAsync(() => seed(withCutout: false));
    await open(tester);

    expect(find.text('Save cutout'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<MaskMode>>(
            find.byType(SegmentedButton<MaskMode>),
          )
          .selected,
      {MaskMode.add},
    );
  });

  testWidgets('a photograph that has gone missing says so', (tester) async {
    await repository.save(
      confidentItem(id: id.value, name: 'Tee').copyWith(
        photos: PhotoSet([
          ItemPhoto(
            uri: 'file:///gone.png',
            role: PhotoRole.front,
            capturedAt: DateTime.utc(2026, 1, 1),
          ),
        ]),
      ),
    );

    await open(tester);

    expect(find.textContaining('photograph'), findsWidgets);
    expect(find.text('Save cutout'), findsNothing);
  });

  group('letting the app finish the edges', () {
    /// A gateway whose remover answers with [answer], or refuses when null.
    ///
    /// It records what it was sent, because the thing worth pinning is that
    /// the *edited* canvas goes up rather than the untouched photograph — the
    /// whole reason a second pass can succeed where the first failed is that
    /// it is being asked about a different picture.
    _Remover install({Uint8List? answer}) {
      final remover = _Remover(answer: answer);
      container.dispose();
      container = ProviderContainer(
        overrides: [
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          imageStoreProvider.overrideWithValue(images),
          aiGatewayProvider.overrideWithValue(remover),
        ],
      );
      addTearDown(container.dispose);
      return remover;
    }

    testWidgets('the edited canvas is what gets sent, not the original', (
      tester,
    ) async {
      final refined = await tester.runAsync(
        () => _png(const Color(0xFF00FF00)),
      );
      final remover = install(answer: refined);
      await tester.runAsync(() => seed(withCutout: true));
      await open(tester);
      await paintAcross(tester);

      await tester.tap(find.text('Let the app finish the edges'));
      await drain(tester);

      expect(remover.received, isNotNull);
      // PNG, because what is sent is already transparent where the user
      // painted and JPEG would flatten that to black.
      expect(remover.received!.mimeType, 'image/png');
    });

    testWidgets('its answer becomes the canvas and can be undone', (
      tester,
    ) async {
      final refined = await tester.runAsync(
        () => _png(const Color(0xFF00FF00)),
      );
      install(answer: refined);
      await tester.runAsync(() => seed(withCutout: true));
      await open(tester);

      final undo = find.widgetWithIcon(IconButton, Icons.undo);
      expect(tester.widget<IconButton>(undo).onPressed, isNull);

      await tester.tap(find.text('Let the app finish the edges'));
      await drain(tester);

      // A pass is undoable in its own right, not only the strokes before it.
      expect(tester.widget<IconButton>(undo).onPressed, isNotNull);
    });

    testWidgets('a refusal keeps the work on the canvas', (tester) async {
      // The important one. Setting the fatal-failure field here would replace
      // the whole editor with a message and throw away a hand-drawn mask
      // because one request came back empty.
      install();
      await tester.runAsync(() => seed(withCutout: true));
      await open(tester);
      await paintAcross(tester);

      await tester.tap(find.text('Let the app finish the edges'));
      await drain(tester);

      expect(find.textContaining('could not separate'), findsOneWidget);
      // Still an editor, still holding the stroke.
      expect(find.text('Save cutout'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('a pass that would eat the garment is refused', (tester) async {
      // Reported from a real phone: a hand-tidied black t-shirt came back as
      // a scrap of bedding in one corner. Accepting that replaces careful
      // hand work with an empty frame, and Undo is small comfort when the
      // screen has just thrown away what you spent a minute drawing.
      final nearlyEmpty = await tester.runAsync(() => _mostlyTransparent());
      install(answer: nearlyEmpty);
      await tester.runAsync(() => seed(withCutout: true));
      await open(tester);
      await paintAcross(tester);

      await tester.tap(find.text('Let the app finish the edges'));
      await drain(tester);

      expect(
        find.textContaining('removed most of the garment'),
        findsOneWidget,
      );
      // The editor and the stroke are both still here.
      expect(find.text('Save cutout'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('undoing a pass brings the earlier strokes back', (
      tester,
    ) async {
      // A pass bakes the strokes into the new image and clears them, so
      // restoring only the image would leave them applied twice — and undoing
      // once would look like it had done nothing.
      final refined = await tester.runAsync(
        () => _png(const Color(0xFF00FF00)),
      );
      install(answer: refined);
      await tester.runAsync(() => seed(withCutout: true));
      await open(tester);
      await paintAcross(tester);

      await tester.tap(find.text('Let the app finish the edges'));
      await drain(tester);

      final undo = find.widgetWithIcon(IconButton, Icons.undo);
      await tester.tap(undo);
      await tester.pump();

      // The stroke from before the pass is back, so Undo is still live.
      expect(tester.widget<IconButton>(undo).onPressed, isNotNull);

      await tester.tap(undo);
      await tester.pump();

      // And now everything is undone.
      expect(tester.widget<IconButton>(undo).onPressed, isNull);
    });
  });
}

/// A gateway whose background remover answers with one fixed picture.
class _Remover extends AiGateway {
  _Remover({this.answer}) : super(baseUrl: Uri.parse('http://test.invalid/'));

  final Uint8List? answer;

  /// What the last call was given.
  ScanImage? received;

  @override
  Future<Uint8List?> cutout(ScanImage image) async {
    received = image;
    return answer;
  }
}

/// A cutout that kept almost nothing — a corner of a large frame.
///
/// What a failed segmentation actually returns: not an empty image, which
/// would be easy to spot, but a plausible-looking scrap.
Future<Uint8List> _mostlyTransparent({int size = 40}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 6, 6),
    Paint()..color = const Color(0xFFEEEEEE),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  picture.dispose();
  image.dispose();
  return data.buffer.asUint8List();
}
