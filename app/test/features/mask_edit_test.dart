/// The compositing behind the cutout editor, checked against real pixels.
///
/// Everything here is deliberately separable from the gestures: a stroke list
/// and two images in, PNG bytes out. That is what makes it possible to assert
/// that a subtract stroke really produces transparency and an additive one
/// really restores the original colour, rather than looking at a screenshot
/// and believing it.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/features/wardrobe/mask_edit.dart';

/// A solid [colour] square, [size] on a side.
Future<ui.Image> _solid(Color colour, {int size = 40}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = colour,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  return image;
}

/// Fully transparent, standing in for a cutout that removed everything.
Future<ui.Image> _empty({int size = 40}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  return image;
}

/// The pixel at ([x], [y]) of a rendered PNG, as ARGB.
Future<({int alpha, int red, int green, int blue})> _pixel(
  Uint8List png,
  int x,
  int y,
) async {
  final decoded = await decodeImageFromList(png);
  final data = (await decoded.toByteData())!;
  final offset = (y * decoded.width + x) * 4;
  decoded.dispose();
  return (
    red: data.getUint8(offset),
    green: data.getUint8(offset + 1),
    blue: data.getUint8(offset + 2),
    alpha: data.getUint8(offset + 3),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A stroke straight across the middle, wide enough to cover the centre.
  MaskStroke across(MaskMode mode) => MaskStroke(
    mode: mode,
    points: const [Offset(0, 20), Offset(40, 20)],
    width: 20,
  );

  test('an untouched mask comes back as the cutout it started from', () async {
    final original = await _solid(const Color(0xFF204080));
    final cutout = await _solid(const Color(0xFF204080));

    final png = await renderMask(
      original: original,
      cutout: cutout,
      strokes: const [],
    );

    expect((await _pixel(png, 20, 20)).alpha, 255);
  });

  test('a subtract stroke makes the garment transparent there', () async {
    final original = await _solid(const Color(0xFF204080));
    final cutout = await _solid(const Color(0xFF204080));

    final png = await renderMask(
      original: original,
      cutout: cutout,
      strokes: [across(MaskMode.subtract)],
    );

    expect((await _pixel(png, 20, 20)).alpha, 0);
    // And only there — a corner well away from the stroke is untouched.
    expect((await _pixel(png, 2, 2)).alpha, 255);
  });

  test('an add stroke restores the original pixels, not paint', () async {
    // The reason additive strokes draw the photograph through a mask rather
    // than painting a colour: a repaired edge has to carry the garment's own
    // pixels, or it shows as a smear of whatever the brush colour was.
    final original = await _solid(const Color(0xFF204080));
    final cutout = await _empty();

    final png = await renderMask(
      original: original,
      cutout: cutout,
      strokes: [across(MaskMode.add)],
    );

    final restored = await _pixel(png, 20, 20);
    expect(restored.alpha, 255);
    expect(restored.red, 0x20);
    expect(restored.green, 0x40);
    expect(restored.blue, 0x80);
  });

  test('a cutout that failed entirely can still be painted in', () async {
    // `cutoutUri` is null when the remover could not separate anything. The
    // editor has to work from the photograph alone in that case, or the one
    // situation most in need of a hand-drawn mask is the one that cannot have
    // one.
    final original = await _solid(const Color(0xFF11AA33));

    final png = await renderMask(
      original: original,
      cutout: null,
      strokes: [across(MaskMode.add)],
    );

    expect((await _pixel(png, 20, 20)).alpha, 255);
    expect((await _pixel(png, 2, 2)).alpha, 0);
  });

  test(
    'strokes apply in order, so a mistake can be painted back out',
    () async {
      final original = await _solid(const Color(0xFF204080));
      final cutout = await _solid(const Color(0xFF204080));

      final png = await renderMask(
        original: original,
        cutout: cutout,
        strokes: [across(MaskMode.subtract), across(MaskMode.add)],
      );

      expect((await _pixel(png, 20, 20)).alpha, 255);
    },
  );

  group('mapping a finger to a pixel', () {
    test('accounts for the letterbox a tall image leaves', () {
      // A 40x80 image in a 100x100 box is drawn 50 wide, centred: 25 either
      // side. A tap at the left edge of the *image* is therefore at x=25 on
      // screen, and reading it as x=0 would put every stroke 20 pixels out.
      final geometry = MaskGeometry.fit(
        const Size(40, 80),
        const Size(100, 100),
      );

      expect(geometry.destination.left, 25);
      expect(geometry.scale, 1.25);
      expect(geometry.toImage(const Offset(25, 0)), const Offset(0, 0));
      expect(geometry.toImage(const Offset(75, 100)), const Offset(40, 80));
    });

    test('a brush keeps its on-screen size whatever the image resolution', () {
      // A 20dp brush on a photograph shown at half size has to be 40 image
      // pixels wide, or it draws far finer than it looks under the finger.
      final geometry = MaskGeometry.fit(
        const Size(200, 200),
        const Size(100, 100),
      );

      expect(geometry.brushToImage(20), 40);
    });
  });
}
