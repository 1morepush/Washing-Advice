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
