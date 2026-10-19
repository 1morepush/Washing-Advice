/// The one way a stored photograph is loaded.
///
/// A garment's thumbnail and a listing's photograph show the same kind of
/// thing, and the care in loading one — the file handed to Flutter and not read
/// into Dart, a browser's bytes held only as long as they are wanted, a missing
/// picture standing aside for something else — has to be the care taken of the
/// other. The garment thumbnail's own tests hold that for garments; these hold
/// it for the widget it is now built on, and that the thumbnail really is.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/images/file_image_store.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/widgets/item_thumbnail.dart';
import 'package:washing_advice/widgets/stored_image.dart';

import '../support/fixtures.dart';
import '../support/photos.dart';

const _fallback = Text('fallback');

/// The size the engine decodes [provider] to.
Future<Size> _decodedSize(WidgetTester tester, ImageProvider provider) async {
  // The widget started this decode inside the test's fake clock; let the
  // engine finish it for real, then let the widget tree hear about it.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  final size = await tester.runAsync(() async {
    final stream = provider.resolve(ImageConfiguration.empty);
    final result = Completer<ui.Image>();
    final listener = ImageStreamListener(
      (info, _) => result.complete(info.image),
    );
    stream.addListener(listener);
    final image = await result.future.timeout(const Duration(seconds: 5));
    stream.removeListener(listener);
    return Size(image.width.toDouble(), image.height.toDouble());
  });
  return size!;
}

/// One device pixel to a logical one, so a decoded size reads as the box's.
///
/// The test window is three to one, which is right for the layout tests and
/// would make every number here three times the one in the sentence.
void _onePixelToOne(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// [child] in a [side]-dp square, the way a grid cell would give it.
Widget _app(ProviderContainer container, Widget child, {double side = 100}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: side, height: side, child: child),
          ),
        ),
      ),
    );

void main() {
  /// A byte store with one [width]x[height] photograph in it.
  Future<(ProviderContainer, String)> bytesHolding(
    WidgetTester tester, {
    int width = 300,
    int height = 400,
    int retain = 24,
  }) async {
    final images = MemoryImageStore();
    final uri = (await tester.runAsync(
      () async => images.save(await pngBytes(width, height), name: 'photo'),
    ))!;
    final container = ProviderContainer(
      overrides: [
        imageStoreProvider.overrideWithValue(images),
        imageRetainCountProvider.overrideWithValue(retain),
      ],
    );
    addTearDown(container.dispose);
    return (container, uri);
  }

  /// Pumps [photo] and waits for its bytes, as the browser's store would
  /// deliver them.
  Future<void> show(
    WidgetTester tester,
    ProviderContainer container,
    String uri,
    StoredImage photo,
  ) async {
    await tester.pumpWidget(_app(container, photo));
    await tester.runAsync(() => container.read(imageBytesProvider(uri).future));
    await tester.pump();
  }

  group('from a store of bytes', () {
    testWidgets('the stored photograph is drawn', (tester) async {
      final (container, uri) = await bytesHolding(tester);

      await show(
        tester,
        container,
        uri,
        StoredImage(uri: uri, fallback: _fallback),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).imageProvider, isA<MemoryImage>());
    });

    testWidgets('and the fallback stands in while the bytes are on their way', (
      tester,
    ) async {
      final (container, uri) = await bytesHolding(tester);

      await tester.pumpWidget(
        _app(container, StoredImage(uri: uri, fallback: _fallback)),
      );

      expect(find.text('fallback'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a photograph that is not in the store is not an error', (
      tester,
    ) async {
      final (container, _) = await bytesHolding(tester);
      const gone = '$memoryImageScheme:never-saved';

      await show(
        tester,
        container,
        gone,
        const StoredImage(uri: gone, fallback: _fallback),
      );

      expect(find.text('fallback'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and bytes that are not a picture show the fallback too', (
      tester,
    ) async {
      final images = MemoryImageStore();
      final uri = await images.save(
        Uint8List.fromList([1, 2, 3, 4]),
        name: 'not-an-image',
      );
      final container = ProviderContainer(
        overrides: [imageStoreProvider.overrideWithValue(images)],
      );
      addTearDown(container.dispose);

      await show(
        tester,
        container,
        uri,
        StoredImage(uri: uri, fallback: _fallback),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(find.text('fallback'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('from a store of files', () {
    late Directory directory;
    late FileImageStore store;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('stored-image');
      store = FileImageStore.inDirectory(directory);
    });

    tearDown(() => directory.deleteSync(recursive: true));

    testWidgets('the file is handed to Flutter and not read as bytes', (
      tester,
    ) async {
      final uri = (await tester.runAsync(
        () async => store.save(await pngBytes(600, 300), name: 'wide'),
      ))!;
      final container = ProviderContainer(
        overrides: [imageStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _app(container, StoredImage(uri: uri, fallback: _fallback)),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).imageProvider, isA<FileImage>());
      expect(
        container.exists(imageBytesProvider(uri)),
        isFalse,
        reason: 'the photograph must not pass through Dart as bytes',
      );
    });

    testWidgets('a file that has vanished shows the fallback', (tester) async {
      final uri = (await tester.runAsync(
        () async => store.save(await pngBytes(10, 10), name: 'vanished'),
      ))!;
      await tester.runAsync(() => store.delete(uri));
      final container = ProviderContainer(
        overrides: [imageStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _app(container, StoredImage(uri: uri, fallback: _fallback)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(find.text('fallback'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('how it is decoded', () {
    testWidgets('contained, a portrait photograph keeps its shape', (
      tester,
    ) async {
      _onePixelToOne(tester);
      final (container, uri) = await bytesHolding(
        tester,
        width: 300,
        height: 600,
      );

      await show(
        tester,
        container,
        uri,
        StoredImage(uri: uri, fit: BoxFit.contain, fallback: _fallback),
      );

      final provider = tester.widget<Image>(find.byType(Image)).image;
      expect((provider as ResizeImage).policy, ResizeImagePolicy.fit);
      final decoded = await _decodedSize(tester, provider);
      // Twice as tall as wide, as stored, with the longer side the box's.
      expect(decoded.height / decoded.width, closeTo(2, 0.02));
      expect(decoded.height, 100);
    });

    testWidgets('cropped to fill, it is decoded larger than its box', (
      tester,
    ) async {
      // Cropping scales a photograph until its shorter side meets the box, so
      // one decoded only to the box's size would be drawn a third larger than
      // it was decoded.
      _onePixelToOne(tester);
      final (container, uri) = await bytesHolding(
        tester,
        width: 300,
        height: 400,
      );

      await show(
        tester,
        container,
        uri,
        StoredImage(uri: uri, fallback: _fallback),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      final decoded = await _decodedSize(tester, image.image as ResizeImage);
      expect(decoded.width, greaterThanOrEqualTo(100));
      expect(decoded.height, 150);
      expect(decoded.height / decoded.width, closeTo(400 / 300, 0.02));
    });

    testWidgets('at twice the pixel ratio, twice the pixels', (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final (container, uri) = await bytesHolding(
        tester,
        width: 600,
        height: 600,
      );

      await show(
        tester,
        container,
        uri,
        StoredImage(uri: uri, fit: BoxFit.contain, fallback: _fallback),
      );

      final decoded = await _decodedSize(
        tester,
        tester.widget<Image>(find.byType(Image)).image,
      );
      expect(decoded, const Size(200, 200));
    });

    testWidgets('in a box with no bounds it is decoded at its stored size', (
      tester,
    ) async {
      final (container, uri) = await bytesHolding(tester);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: UnconstrainedBox(
                child: StoredImage(uri: uri, fallback: _fallback),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => container.read(imageBytesProvider(uri).future),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<MemoryImage>());
    });

    testWidgets('and passes on how it was asked to be drawn', (tester) async {
      final (container, uri) = await bytesHolding(tester);

      await show(
        tester,
        container,
        uri,
        StoredImage(
          uri: uri,
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.high,
          semanticLabel: 'Cover photo',
          fallback: _fallback,
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.fitWidth);
      expect(image.alignment, Alignment.topCenter);
      expect(image.filterQuality, FilterQuality.high);
      expect(image.semanticLabel, 'Cover photo');
    });
  });

  group('one path for every photograph', () {
    testWidgets('a garment\'s thumbnail draws its photograph with it', (
      tester,
    ) async {
      final images = MemoryImageStore();
      final container = ProviderContainer(
        overrides: [imageStoreProvider.overrideWithValue(images)],
      );
      addTearDown(container.dispose);
      final item = await photographed(
        tester,
        images,
        confidentItem(id: 'a', name: 'Jumper'),
      );

      await tester.pumpWidget(
        _app(container, ItemThumbnail(item: item, size: 100)),
      );

      final stored = tester.widget<StoredImage>(find.byType(StoredImage));
      expect(stored.uri, item.photos.displayImageUri);
      // The garment's own choices, not the listing's: a cutout is contained.
      expect(stored.fit, BoxFit.contain);
    });

    testWidgets('and one with no photograph does not load anything', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [imageStoreProvider.overrideWithValue(MemoryImageStore())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _app(
          container,
          ItemThumbnail(
            item: confidentItem(id: 'a', name: 'Jumper'),
            size: 100,
          ),
        ),
      );

      expect(find.byType(StoredImage), findsNothing);
    });

    testWidgets('a photograph is kept for a while after it leaves the screen', (
      tester,
    ) async {
      final (container, uri) = await bytesHolding(tester);
      await show(
        tester,
        container,
        uri,
        StoredImage(uri: uri, fallback: _fallback),
      );

      await tester.pumpWidget(_app(container, const SizedBox.shrink()));
      await tester.pump();

      // Scrolling a row away and back should not read the file again.
      expect(container.exists(imageBytesProvider(uri)), isTrue);
    });

    testWidgets('and let go once the retained few are used up', (tester) async {
      final (container, uri) = await bytesHolding(tester, retain: 0);
      await show(
        tester,
        container,
        uri,
        StoredImage(uri: uri, fallback: _fallback),
      );

      await tester.pumpWidget(_app(container, const SizedBox.shrink()));
      await tester.pump();

      expect(container.exists(imageBytesProvider(uri)), isFalse);
    });
  });
}
