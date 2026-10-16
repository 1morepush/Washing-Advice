/// Photographed garments for widget tests, backed by a [MemoryImageStore].
///
/// The pictures are real PNGs made by the engine, because the viewer decodes
/// what it is given; a stub of bytes would only ever show its error state.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';

/// A solid-colour PNG of the given shape.
Future<Uint8List> pngBytes(int width, int height, {Color? color}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color ?? const Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// [item] with one photograph per entry of [roles], each stored in [store].
///
/// [shape] is the pixel size of every picture; [cutouts] gives each a cutout
/// too, half the size so the two can be told apart, which is what a list
/// thumbnail would prefer.
Future<WardrobeItem> photographed(
  WidgetTester tester,
  MemoryImageStore store,
  WardrobeItem item, {
  List<PhotoRole> roles = const [PhotoRole.front],
  (int, int) shape = (300, 400),
  bool cutouts = false,
}) async {
  final photos = <ItemPhoto>[];
  for (final (index, role) in roles.indexed) {
    final name = '${item.id.value}-${role.name}-$index';
    final uri = (await tester.runAsync(
      () async => store.save(await pngBytes(shape.$1, shape.$2), name: name),
    ))!;
    String? cutout;
    if (cutouts) {
      cutout = (await tester.runAsync(
        () async => store.save(
          await pngBytes(
            shape.$1 ~/ 2,
            shape.$2 ~/ 2,
            color: const Color(0xFF993366),
          ),
          name: '$name-cutout',
        ),
      ))!;
    }
    photos.add(
      ItemPhoto(
        uri: uri,
        cutoutUri: cutout,
        role: role,
        capturedAt: DateTime.utc(2026, 1, index + 1),
      ),
    );
  }
  return item.copyWith(photos: PhotoSet(photos));
}

/// Lets the engine finish decoding, then lets the widgets hear about it.
///
/// Not `pumpAndSettle`: a viewer that is still loading shows a spinner, which
/// never settles.
Future<void> settleImages(WidgetTester tester) async {
  // Frames first, so the route is built and every decode has been started.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
