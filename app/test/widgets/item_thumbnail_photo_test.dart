/// How a garment's photograph is drawn and how long it stays in memory.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/images/file_image_store.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/widgets/item_thumbnail.dart';

import '../support/fixtures.dart';

/// A solid-colour PNG of the given shape, made by the engine itself.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

WardrobeItem _itemWith(String uri) {
  final base = confidentItem(id: 'a', name: 'Jumper');
  return base.copyWith(
    photos: PhotoSet([
      ItemPhoto(
        uri: uri,
        role: PhotoRole.front,
        capturedAt: DateTime.utc(2026),
      ),
    ]),
  );
}

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

Widget _app(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('a portrait photo keeps its shape in a square thumbnail', (
    tester,
  ) async {
    final images = MemoryImageStore();
    final uri = (await tester.runAsync(
      () async => images.save(await _png(300, 600), name: 'tall'),
    ))!;
    final container = ProviderContainer(
      overrides: [imageStoreProvider.overrideWithValue(images)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(container, ItemThumbnail(item: _itemWith(uri), size: 100)),
    );
    await tester.runAsync(() => container.read(imageBytesProvider(uri).future));
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    final provider = image.image as ResizeImage;
    expect(provider.policy, ResizeImagePolicy.fit);

    // What the engine actually decodes: twice as tall as wide, as stored.
    // Under the old `exact` policy this was a square, and `contain` then had
    // nothing left to correct.
    final decoded = await _decodedSize(tester, provider);
    expect(decoded.height / decoded.width, closeTo(2, 0.02));
  });

  testWidgets('on a phone the file is handed to Flutter, not read as bytes', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('thumb');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = FileImageStore.inDirectory(dir);
    final uri = (await tester.runAsync(
      () async => store.save(await _png(600, 300), name: 'wide'),
    ))!;
    final container = ProviderContainer(
      overrides: [imageStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(container, ItemThumbnail(item: _itemWith(uri), size: 100)),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    expect(provider.imageProvider, isA<FileImage>());
    expect(provider.policy, ResizeImagePolicy.fit);
    expect(
      container.exists(imageBytesProvider(uri)),
      isFalse,
      reason: 'the photograph must not pass through Dart as bytes',
    );
  });

  testWidgets('a file that has vanished does not throw', (tester) async {
    final dir = Directory.systemTemp.createTempSync('thumb');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = FileImageStore.inDirectory(dir);
    final uri = (await tester.runAsync(
      () async => store.save(await _png(10, 10), name: 'vanished'),
    ))!;
    await tester.runAsync(() => store.delete(uri));
    final container = ProviderContainer(
      overrides: [imageStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _app(container, ItemThumbnail(item: _itemWith(uri), size: 100)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  group('bytes held for the browser and demo stores', () {
    Future<(ProviderContainer, List<String>)> build(
      int retain,
      int count,
    ) async {
      final images = MemoryImageStore();
      final uris = [
        for (var i = 0; i < count; i++)
          await images.save(Uint8List.fromList([i]), name: 'n$i'),
      ];
      final container = ProviderContainer(
        overrides: [
          imageStoreProvider.overrideWithValue(images),
          imageRetainCountProvider.overrideWithValue(retain),
        ],
      );
      addTearDown(container.dispose);
      return (container, uris);
    }

    test('are released once nothing is showing them', () async {
      final (container, uris) = await build(2, 5);

      for (final uri in uris) {
        final subscription = container.listen(
          imageBytesProvider(uri),
          (_, _) {},
        );
        await container.read(imageBytesProvider(uri).future);
        subscription.close();
      }
      await Future<void>.delayed(Duration.zero);

      // Only the last two are kept, for scrolling back; the rest are gone
      // rather than held for the life of the process.
      expect(
        [for (final uri in uris) container.exists(imageBytesProvider(uri))],
        [false, false, false, true, true],
      );
    });

    test('stay while something is still showing them', () async {
      final (container, uris) = await build(1, 3);

      for (final uri in uris) {
        container.listen(imageBytesProvider(uri), (_, _) {});
        await container.read(imageBytesProvider(uri).future);
      }
      await Future<void>.delayed(Duration.zero);

      expect(
        [for (final uri in uris) container.exists(imageBytesProvider(uri))],
        [true, true, true],
      );
    });
  });
}
