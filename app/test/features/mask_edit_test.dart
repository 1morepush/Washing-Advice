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

  group('preparing a canvas for the remover', () {
    test('what is sent has no transparency left in it', () async {
      // The bug this exists for. A cutout is transparent, a remover handed
      // transparency flattens it — in practice onto black — and a black
      // t-shirt then becomes the same colour as the background it is supposed
      // to be separated from. It keeps the bedding and throws the shirt away.
      final original = await _solid(const Color(0xFF101010));
      final cutout = await _solid(const Color(0xFF101010));

      final png = await renderForRemoval(
        original: original,
        cutout: cutout,
        strokes: [across(MaskMode.subtract)],
        background: const Color(0xFFFFFFFF),
      );

      // Where the stroke removed the garment there is now ground, not a hole.
      final removed = await _pixel(png, 20, 20);
      expect(removed.alpha, 255);
      expect(removed.red, 255);
      // And the garment itself is untouched.
      expect((await _pixel(png, 2, 2)).red, 0x10);

      original.dispose();
      cutout.dispose();
    });

    test('the ground is chosen against the garment', () {
      // A near-black garment gets a white ground and vice versa. A fixed
      // colour would fail one of the two commonest cases outright.
      expect(groundFor(12), const Color(0xFFFFFFFF));
      expect(groundFor(94), const Color(0xFF101010));
    });

    test('and is a mid-grey when the color was never recorded', () {
      expect(groundFor(null), const Color(0xFF808080));
    });
  });

  group('limiting what the remover may do', () {
    test('it can take pixels away', () async {
      final current = await _solid(const Color(0xFF204080));
      final proposed = await _empty();

      final result = await intersect(proposed: proposed, current: current);
      expect(await opaqueFraction(result), lessThan(0.05));

      current.dispose();
      proposed.dispose();
      result.dispose();
    });

    test('but it cannot put back what the user removed', () async {
      // The user's own removals are a deliberate statement about their own
      // garment — they can see it and the model cannot — so a pass that
      // restored the bedding they had just wiped out would be overruling the
      // one party who knows.
      final current = await _empty();
      final proposed = await _solid(const Color(0xFF204080));

      final result = await intersect(proposed: proposed, current: current);
      expect(await opaqueFraction(result), lessThan(0.05));

      current.dispose();
      proposed.dispose();
      result.dispose();
    });

    test('what both keep survives', () async {
      final current = await _solid(const Color(0xFF204080));
      final proposed = await _solid(const Color(0xFF204080));

      final result = await intersect(proposed: proposed, current: current);
      expect(await opaqueFraction(result), greaterThan(0.95));

      current.dispose();
      proposed.dispose();
      result.dispose();
    });

    test('a proposal at a different resolution still lines up', () async {
      // The remover is free to answer at whatever size it likes, and an
      // intersection between two different grids would silently trim an edge.
      final current = await _solid(const Color(0xFF204080), size: 40);
      final proposed = await _solid(const Color(0xFF204080), size: 100);

      final result = await intersect(proposed: proposed, current: current);
      expect(result.width, 40);
      expect(await opaqueFraction(result), greaterThan(0.95));

      current.dispose();
      proposed.dispose();
      result.dispose();
    });
  });

  group('measuring how much is left', () {
    test('a full image reads as full', () async {
      final image = await _solid(const Color(0xFF204080));
      expect(await opaqueFraction(image), greaterThan(0.95));
      image.dispose();
    });

    test('an empty one reads as empty', () async {
      final image = await _empty();
      expect(await opaqueFraction(image), lessThan(0.05));
      image.dispose();
    });

    test('half an image reads as about half', () async {
      // The number that decides whether a pass is a tidier edge or a failed
      // segmentation, so it has to be roughly right rather than merely
      // ordered.
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 40, 20),
        Paint()..color = const Color(0xFF204080),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(40, 40);
      picture.dispose();

      expect(await opaqueFraction(image), closeTo(0.5, 0.06));
      image.dispose();
    });
  });
}
