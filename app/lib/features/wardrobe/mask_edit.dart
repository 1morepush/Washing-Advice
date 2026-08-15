/// Painting a cutout by hand.
///
/// The background remover is a classical one: it measures distance from the
/// colours at the frame's border, which handles a garment on a bed and does
/// not handle one held against a wall in a similar tone, with a hand and a
/// shadow in shot. It is also *deterministic*, so re-running it on the same
/// photograph produces exactly the same wrong answer. Fixing a bad cutout
/// therefore needs either a different photograph or a different mask, and this
/// is the mask.
///
/// The geometry and the compositing live here, apart from the widgets, so both
/// can be tested against real pixels rather than by looking at a screen — and
/// so the live preview and the saved file are produced by the same function
/// and cannot disagree.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Whether a stroke restores the garment or removes the background.
enum MaskMode {
  /// Bring back pixels the remover discarded.
  add,

  /// Rub out what it left behind.
  subtract,
}

/// One drag of a finger, in **image pixel** coordinates.
///
/// Not widget coordinates, deliberately. A stroke recorded where the finger
/// was on screen would carry the width of whatever the widget happened to be
/// at that moment, and the exported mask would not match the preview it was
/// drawn on.
final class MaskStroke {
  const MaskStroke({
    required this.mode,
    required this.points,
    required this.width,
  });

  final MaskMode mode;
  final List<Offset> points;

  /// Brush diameter, in image pixels.
  final double width;

  MaskStroke extendedTo(Offset point) =>
      MaskStroke(mode: mode, points: [...points, point], width: width);

  Path get path {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    // A single tap is a dot, and a zero-length path draws nothing — so give it
    // somewhere imperceptible to go.
    if (points.length == 1) {
      path.lineTo(points.first.dx + 0.01, points.first.dy);
      return path;
    }
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }
}

/// How an image of [imageSize] is laid out inside [widgetSize], and how to get
/// back from a finger to a pixel.
///
/// `BoxFit.contain`, matching what the editor draws, so the mapping is the
/// inverse of the real layout rather than an approximation of it.
final class MaskGeometry {
  const MaskGeometry({required this.destination, required this.scale});

  factory MaskGeometry.fit(Size imageSize, Size widgetSize) {
    final fitted = applyBoxFit(BoxFit.contain, imageSize, widgetSize);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & widgetSize,
    );
    return MaskGeometry(
      destination: destination,
      // Uniform under `contain`, so either axis gives the same number.
      scale: imageSize.width == 0 ? 1 : destination.width / imageSize.width,
    );
  }

  /// Where the image is drawn within the widget.
  final Rect destination;

  /// Widget pixels per image pixel.
  final double scale;

  /// The image pixel under a point in widget space.
  Offset toImage(Offset local) => Offset(
    (local.dx - destination.left) / scale,
    (local.dy - destination.top) / scale,
  );

  /// A brush drawn [widgetWidth] wide on screen, in image pixels — so the
  /// brush stays the same size under the finger whatever the zoom.
  double brushToImage(double widgetWidth) => widgetWidth / scale;
}

/// Draws [strokes] over [cutout] within [destination].
///
/// The one function both the live preview and the export call, so what is
/// saved is what was on screen.
///
/// [cutout] is the mask as it stands; null when the remover failed outright,
/// in which case the layer starts empty and the whole garment is painted in by
/// hand. [original] is the untouched photograph, and is what an additive
/// stroke draws — restoring true pixels rather than paint, so a repaired edge
/// carries the garment's actual colour.
void paintMask(
  ui.Canvas canvas, {
  required ui.Image original,
  required ui.Image? cutout,
  required List<MaskStroke> strokes,
  required Rect destination,
  required Size imageSize,
}) {
  final source = Offset.zero & imageSize;

  // `BlendMode.clear` clears within the current layer. Without an explicit one
  // it punches through everything already painted and shows as a hole over the
  // app's own background — which on CanvasKit reads as a black rectangle.
  canvas.saveLayer(destination, Paint());

  if (cutout != null) {
    canvas.drawImageRect(cutout, source, destination, Paint());
  }

  final scale = imageSize.width == 0
      ? 1.0
      : destination.width / imageSize.width;

  for (final stroke in strokes) {
    final brush = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.width * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // The stroke is recorded in image pixels; move it into the destination.
    //
    // Written out rather than built with `Matrix4`, which would mean depending
    // on `vector_math` for a scale and a translation. Column-major, so the
    // translation lives at 12 and 13.
    final path = stroke.path.transform(
      Float64List.fromList([
        scale, 0, 0, 0, //
        0, scale, 0, 0, //
        0, 0, 1, 0, //
        destination.left, destination.top, 0, 1,
      ]),
    );

    switch (stroke.mode) {
      case MaskMode.subtract:
        canvas.drawPath(path, brush..blendMode = BlendMode.clear);
      case MaskMode.add:
        // Stroke first, then the photograph through it with `srcIn`.
        //
        // The order matters and the obvious one is wrong. Drawing the image
        // and then the stroke with `dstIn` looks equivalent, but a draw only
        // blends the pixels it actually covers — so the image outside the
        // brush is never cleared and an "add" stroke restores the entire
        // photograph, background and all. Laying the mask down first and
        // drawing the image with `srcIn` covers the whole layer, so
        // everything the brush did not touch resolves to nothing.
        //
        // A mask rather than a clip because `Path` cannot turn a *stroked*
        // polyline into a fillable outline; this reuses the stroke rasteriser
        // that is already there and antialiases the brush edge for free. And
        // it draws the original rather than a colour, so a repaired edge
        // carries the garment's own pixels instead of a smear of paint.
        canvas
          ..saveLayer(destination, Paint())
          ..drawPath(path, brush..blendMode = BlendMode.srcOver)
          ..drawImageRect(
            original,
            source,
            destination,
            Paint()..blendMode = BlendMode.srcIn,
          )
          ..restore();
    }
  }

  canvas.restore();
}

/// Renders the edited mask to PNG bytes at the photograph's own resolution.
///
/// PNG is not a preference. A cutout is transparent, JPEG has no alpha
/// channel, and encoding this as one would turn the removed background black.
Future<Uint8List> renderMask({
  required ui.Image original,
  required ui.Image? cutout,
  required List<MaskStroke> strokes,
}) async {
  final size = Size(original.width.toDouble(), original.height.toDouble());
  final recorder = ui.PictureRecorder();

  paintMask(
    ui.Canvas(recorder),
    original: original,
    cutout: cutout,
    strokes: strokes,
    destination: Offset.zero & size,
    imageSize: size,
  );

  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(original.width, original.height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    // These hold memory the Dart collector does not account for on CanvasKit,
    // which is what the installed app runs on.
    picture.dispose();
  }
}

/// Renders the mask onto an opaque ground, for sending to the remover.
///
/// Not [renderMask] with a colour behind it, and the difference is the whole
/// point of this function existing.
///
/// A cutout is transparent, and a background remover that is handed
/// transparency flattens it — in practice onto black. Do that with a black
/// t-shirt and the garment and the removed background become the same colour,
/// so the only thing left with any contrast is whatever bedding the user has
/// not painted out yet. The remover then keeps the bedding and throws away the
/// shirt, which is not a subtle degradation: it returns an almost empty image.
///
/// So the ground is chosen against the garment rather than fixed. [background]
/// should be a colour the garment is not; the caller knows the garment's
/// palette and this does not.
Future<Uint8List> renderForRemoval({
  required ui.Image original,
  required ui.Image? cutout,
  required List<MaskStroke> strokes,
  required Color background,
}) async {
  final size = Size(original.width.toDouble(), original.height.toDouble());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  canvas.drawRect(Offset.zero & size, Paint()..color = background);
  paintMask(
    canvas,
    original: original,
    cutout: cutout,
    strokes: strokes,
    destination: Offset.zero & size,
    imageSize: size,
  );

  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(original.width, original.height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// A ground the garment will stand out against, from its CIE L* lightness.
///
/// Only has to be far enough away in brightness to keep an edge detectable,
/// so it flips on lightness rather than trying to be clever about hue: black
/// garments are the common case and white ones the other, and a mid-grey would
/// fail both at once.
///
/// Takes the number rather than an `ItemColor` so this file stays free of the
/// wardrobe model — it knows about pixels and nothing else. Mid-grey when the
/// garment's colour was never recorded, which is no worse than the fixed
/// choice it replaces and no better.
Color groundFor(double? lightness) {
  if (lightness == null) return const Color(0xFF808080);
  return lightness < 50 ? const Color(0xFFFFFFFF) : const Color(0xFF101010);
}

/// [proposed] limited to what [current] already kept.
///
/// The remover may only take pixels away, never put them back. A removal the
/// user painted by hand is a deliberate statement about their own garment —
/// they can see it and the model cannot — so a pass that restored the bedding
/// they had just wiped out would be overruling the one party who knows.
///
/// `dstIn` keeps the destination where the source is opaque, so drawing the
/// current mask over the proposal with it yields exactly the intersection.
Future<ui.Image> intersect({
  required ui.Image proposed,
  required ui.Image current,
}) async {
  final width = current.width;
  final height = current.height;
  final size = Size(width.toDouble(), height.toDouble());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  canvas.saveLayer(Offset.zero & size, Paint());
  // Scaled to the current mask's frame: the remover is free to answer at a
  // different resolution, and an intersection between two different grids
  // would silently trim an edge.
  canvas.drawImageRect(
    proposed,
    Offset.zero & Size(proposed.width.toDouble(), proposed.height.toDouble()),
    Offset.zero & size,
    Paint(),
  );
  canvas.drawImageRect(
    current,
    Offset.zero & size,
    Offset.zero & size,
    Paint()..blendMode = BlendMode.dstIn,
  );
  canvas.restore();

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// The fraction of [image] that is not transparent, from 0 to 1.
///
/// Measured on a small copy. The answer only has to be good enough to tell
/// "kept most of it" from "kept almost nothing", and reading the alpha of a
/// twelve-megapixel photograph to decide that would cost more than the request
/// it is checking.
Future<double> opaqueFraction(ui.Image image, {int sample = 64}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
    Offset.zero & Size(sample.toDouble(), sample.toDouble()),
    Paint()..filterQuality = FilterQuality.low,
  );

  final picture = recorder.endRecording();
  try {
    final small = await picture.toImage(sample, sample);
    try {
      final data = await small.toByteData();
      if (data == null) return 0;

      final bytes = data.buffer.asUint8List();
      var opaque = 0;
      for (var i = 3; i < bytes.length; i += 4) {
        // Half opacity rather than any at all: downscaling smears a hard edge
        // into a band of faint pixels, and counting those would report a
        // nearly empty image as a third full.
        if (bytes[i] > 127) opaque++;
      }
      return opaque / (sample * sample);
    } finally {
      small.dispose();
    }
  } finally {
    picture.dispose();
  }
}
