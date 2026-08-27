/// Cropping a photograph, checked against real pixels.
///
/// The geometry is worth pinning because it is the part that can be subtly
/// wrong and still look plausible: a rect dragged inside-out, a corner pushed
/// past the frame, a crop that silently discards edges nobody asked to lose.
/// The encoding is worth pinning because the whole point is handing the remover
/// a tighter frame — a crop that came back the same size would be a no-op with
/// a progress spinner.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/features/scan/crop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = Size(200, 100);

  /// A picture with a red left half and a blue right half, so a crop can be
  /// checked by reading the colour back rather than by trusting an offset.
  Future<ui.Image> twoTone() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()..color = const Color(0xFFFF0000),
    );
    canvas.drawRect(
      const Rect.fromLTWH(100, 0, 100, 100),
      Paint()..color = const Color(0xFF0000FF),
    );
    return recorder.endRecording().toImage(200, 100);
  }

  group('keeping the rectangle sane', () {
    test('a crop inside the frame is left alone', () {
      const wanted = Rect.fromLTRB(20, 10, 180, 90);

      expect(clampCrop(wanted, size), wanted);
    });

    test('a crop dragged outside the frame is pulled back in', () {
      final clamped = clampCrop(const Rect.fromLTRB(-50, -50, 400, 400), size);

      expect(clamped.left, 0);
      expect(clamped.top, 0);
      expect(clamped.right, 200);
      expect(clamped.bottom, 100);
    });

    test('a rectangle dragged inside-out never survives as a mirrored one', () {
      // Right of left, bottom of top. Left unchecked this comes back as a
      // negative rect and reappears later as a crop of somewhere else.
      final clamped = clampCrop(const Rect.fromLTRB(150, 80, 20, 10), size);

      expect(clamped.width, greaterThan(0));
      expect(clamped.height, greaterThan(0));
    });

    test('a crop cannot be dragged down to nothing', () {
      final clamped = clampCrop(const Rect.fromLTRB(100, 50, 100, 50), size);

      // A tenth of the shorter edge, which is 100 here.
      expect(clamped.width, greaterThanOrEqualTo(10));
      expect(clamped.height, greaterThanOrEqualTo(10));
    });
  });

  group('what the finger has hold of', () {
    const crop = Rect.fromLTRB(20, 20, 180, 80);

    test('a corner is taken over the body it sits on', () {
      // Both are true at a corner, and resizing is the one somebody meant.
      expect(
        handleAt(crop, const Offset(20, 20), tolerance: 8),
        CropHandle.topLeft,
      );
      expect(
        handleAt(crop, const Offset(180, 80), tolerance: 8),
        CropHandle.bottomRight,
      );
    });

    test('the middle moves the whole rectangle', () {
      expect(
        handleAt(crop, const Offset(100, 50), tolerance: 8),
        CropHandle.body,
      );
    });

    test('a finger outside it has hold of nothing', () {
      expect(handleAt(crop, const Offset(2, 2), tolerance: 8), isNull);
    });
  });

  group('dragging', () {
    test('a corner resizes and leaves the opposite one alone', () {
      final dragged = dragHandle(
        crop: const Rect.fromLTRB(20, 20, 180, 80),
        handle: CropHandle.topLeft,
        point: const Offset(40, 30),
        delta: const Offset(20, 10),
        imageSize: size,
      );

      expect(dragged.topLeft, const Offset(40, 30));
      expect(dragged.bottomRight, const Offset(180, 80));
    });

    test('the body shifts by the movement, not to the finger', () {
      // Shifting *to* the finger makes a rectangle grabbed near its edge jump
      // to centre itself the moment it is touched.
      final dragged = dragHandle(
        crop: const Rect.fromLTRB(20, 20, 120, 80),
        handle: CropHandle.body,
        point: const Offset(30, 30),
        delta: const Offset(10, 5),
        imageSize: size,
      );

      expect(dragged, const Rect.fromLTRB(30, 25, 130, 85));
    });

    test('dragging past the edge stops at the edge', () {
      final dragged = dragHandle(
        crop: const Rect.fromLTRB(20, 20, 120, 80),
        handle: CropHandle.body,
        point: const Offset(0, 0),
        delta: const Offset(500, 500),
        imageSize: size,
      );

      expect(dragged.right, lessThanOrEqualTo(200));
      expect(dragged.bottom, lessThanOrEqualTo(100));
    });
  });

  group('exporting', () {
    test('the cropped half is the colour it should be', () async {
      // The real check. An off-by-one in the offset gives a picture that looks
      // right in a thumbnail and is of the wrong half.
      final source = await twoTone();

      final bytes = await renderCrop(
        original: source,
        crop: const Rect.fromLTRB(100, 0, 200, 100),
      );

      final decoded = img.decodeJpg(bytes)!;
      final pixel = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
      expect(pixel.b, greaterThan(200));
      expect(pixel.r, lessThan(60));
    });

    test('the export is the size of the crop, not of the photograph', () async {
      final source = await twoTone();

      final bytes = await renderCrop(
        original: source,
        crop: const Rect.fromLTRB(50, 25, 150, 75),
      );

      final decoded = img.decodeJpg(bytes)!;
      expect(decoded.width, 100);
      expect(decoded.height, 50);
    });

    test('it comes back as a JPEG, not a PNG', () async {
      // A PNG of the same pixels is several megabytes, paid on every upload
      // over mobile data. The capture layer caps the long edge for the same
      // reason and it would be odd to undo that here.
      final source = await twoTone();

      final bytes = await renderCrop(
        original: source,
        crop: const Rect.fromLTRB(0, 0, 100, 100),
      );

      expect(bytes.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    });
  });

  group('cropping a scan image', () {
    ScanImageFixture fixture() => ScanImageFixture();

    test('a crop that removes nothing hands back the original bytes', () async {
      // Re-encoding a full-frame crop would spend a JPEG generation to return
      // a slightly worse copy of what already existed.
      final source = await twoTone();
      final original = fixture().image;

      final result = await cropScanImage(
        image: original,
        decoded: source,
        crop: wholeFrame(size),
      );

      expect(identical(result, original), isTrue);
    });

    test('a real crop replaces the bytes and records the new size', () async {
      final source = await twoTone();

      final result = await cropScanImage(
        image: fixture().image,
        decoded: source,
        crop: const Rect.fromLTRB(0, 0, 100, 100),
      );

      expect(result.mimeType, 'image/jpeg');
      expect(result.width, 100);
      expect(result.height, 100);
      expect(result.bytes, isNot(fixture().image.bytes));
    });

    test('a crop is smaller than the photograph it came from', () async {
      // The point of the feature, and the thing a PNG export would have
      // quietly reversed.
      final source = await twoTone();
      final whole = await renderCrop(original: source, crop: wholeFrame(size));

      final part = await renderCrop(
        original: source,
        crop: const Rect.fromLTRB(0, 0, 50, 50),
      );

      expect(part.length, lessThan(whole.length));
    });
  });
}

/// A stand-in photograph, so the tests are not asserting against real bytes
/// they cannot see.
class ScanImageFixture {
  final image = ScanImage(
    bytes: Uint8List.fromList(List.filled(64, 7)),
    mimeType: 'image/jpeg',
    width: 200,
    height: 100,
  );
}
