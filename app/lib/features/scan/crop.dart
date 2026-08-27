/// Cropping a photograph before anything is asked about it.
///
/// The background remover is classical: it measures how far each pixel is from
/// the colours at the frame's border. That works when the border is background
/// and fails when it is a patterned duvet, a floorboard, or the edge of another
/// garment — and no amount of re-running it helps, because it is deterministic
/// and will produce the same wrong answer every time.
///
/// A crop changes the question rather than the answer. Framing tightly on the
/// garment means the border it samples really is background, which is the one
/// case it handles well. It also helps identification, for the plainer reason
/// that half a bedroom in shot is half a bedroom the model has to ignore.
///
/// The geometry and the encoding live here, apart from the widgets, so both can
/// be tested against real pixels rather than by looking at a screen.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:wardrobe_core/wardrobe_core.dart';

/// The smallest crop worth allowing, as a fraction of the shorter edge.
///
/// Not zero, because a rect dragged to nothing is a photograph of nothing, and
/// the gesture that produces it is nearly always a mis-drag rather than an
/// intention.
const _minFraction = 0.1;

/// Where a crop starts: the whole frame.
///
/// Deliberately not inset. An inset default would quietly discard the edges for
/// anybody who opened the cropper, glanced at it and pressed Done — losing
/// pixels they never asked to lose. Starting at the full frame makes Done a
/// no-op until somebody actually drags something.
Rect wholeFrame(Size imageSize) => Offset.zero & imageSize;

/// Keeps [crop] inside [imageSize] and no smaller than [_minFraction].
///
/// Applied on every drag rather than only on save, so the rectangle on screen
/// is always one that could really be exported.
Rect clampCrop(Rect crop, Size imageSize) {
  final minSide = (imageSize.shortestSide * _minFraction).clamp(
    1.0,
    imageSize.shortestSide,
  );

  // Width and height first, so a rect dragged inside-out cannot survive as a
  // negative one and reappear later as a mirrored crop.
  var left = crop.left.clamp(0.0, imageSize.width - minSide);
  var top = crop.top.clamp(0.0, imageSize.height - minSide);
  var right = crop.right.clamp(left + minSide, imageSize.width);
  var bottom = crop.bottom.clamp(top + minSide, imageSize.height);

  // Re-clamped after the fact: pushing an edge to its limit can leave the
  // opposite one outside the frame on a very small image.
  left = left.clamp(0.0, right - minSide);
  top = top.clamp(0.0, bottom - minSide);

  return Rect.fromLTRB(left, top, right, bottom);
}

/// Which handle a finger has taken hold of.
enum CropHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,

  /// The middle, which moves the whole rectangle rather than resizing it.
  body,
}

/// The handle nearest [point], or null if the finger landed nowhere useful.
///
/// [tolerance] is in the same coordinates as everything else here, so a caller
/// converts a comfortable finger radius on screen into image pixels once rather
/// than this file guessing at a screen it cannot see.
CropHandle? handleAt(Rect crop, Offset point, {required double tolerance}) {
  final corners = {
    CropHandle.topLeft: crop.topLeft,
    CropHandle.topRight: crop.topRight,
    CropHandle.bottomLeft: crop.bottomLeft,
    CropHandle.bottomRight: crop.bottomRight,
  };

  for (final MapEntry(key: handle, value: corner) in corners.entries) {
    if ((point - corner).distance <= tolerance) return handle;
  }

  return crop.contains(point) ? CropHandle.body : null;
}

/// Moves [handle] to [point], returning the rectangle that results.
///
/// Dragging a corner past its opposite is allowed to happen and then corrected
/// by [clampCrop], rather than being blocked mid-gesture: a rectangle that
/// stops following the finger reads as a broken screen.
Rect dragHandle({
  required Rect crop,
  required CropHandle handle,
  required Offset point,
  required Offset delta,
  required Size imageSize,
}) {
  final moved = switch (handle) {
    CropHandle.topLeft => Rect.fromLTRB(
      point.dx,
      point.dy,
      crop.right,
      crop.bottom,
    ),
    CropHandle.topRight => Rect.fromLTRB(
      crop.left,
      point.dy,
      point.dx,
      crop.bottom,
    ),
    CropHandle.bottomLeft => Rect.fromLTRB(
      point.dx,
      crop.top,
      crop.right,
      point.dy,
    ),
    CropHandle.bottomRight => Rect.fromLTRB(
      crop.left,
      crop.top,
      point.dx,
      point.dy,
    ),
    // Shifted rather than resized, and shifted by the finger's movement rather
    // than to its position, so the rectangle does not jump to centre itself
    // under a finger that grabbed it near an edge.
    CropHandle.body => crop.shift(delta),
  };

  return clampCrop(moved, imageSize);
}

/// Whether [crop] would actually remove anything.
///
/// A no-op crop should not be re-encoded: doing so would spend a JPEG
/// generation to hand back a slightly worse copy of what already existed.
bool cropsAnything(Rect crop, Size imageSize) =>
    crop.left > 0.5 ||
    crop.top > 0.5 ||
    crop.right < imageSize.width - 0.5 ||
    crop.bottom < imageSize.height - 0.5;

/// The cropped region of [original], as a JPEG.
///
/// JPEG rather than PNG, which is what `dart:ui` would hand back on its own.
/// The photograph arrived as a JPEG of a few hundred kilobytes and a PNG of the
/// same pixels is several megabytes — a cost paid on every upload, over mobile
/// data, for a photograph that is about to be described in a sentence. The
/// capture layer caps the long edge at 1600px for exactly this reason and it
/// would be odd to undo that here.
///
/// [quality] matches the capture layer's, so a cropped photograph is not
/// visibly worse than an uncropped one.
Future<Uint8List> renderCrop({
  required ui.Image original,
  required Rect crop,
  int quality = 85,
}) async {
  final bounds = clampCrop(
    crop,
    Size(original.width.toDouble(), original.height.toDouble()),
  );

  final raw = await original.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (raw == null) {
    throw StateError('the photograph could not be read back for cropping');
  }

  final whole = img.Image.fromBytes(
    width: original.width,
    height: original.height,
    bytes: raw.buffer,
    numChannels: 4,
  );

  final cropped = img.copyCrop(
    whole,
    x: bounds.left.round(),
    y: bounds.top.round(),
    width: bounds.width.round().clamp(1, original.width),
    height: bounds.height.round().clamp(1, original.height),
  );

  return img.encodeJpg(cropped, quality: quality);
}

/// [image], cropped to [crop], or the original when the crop changes nothing.
Future<ScanImage> cropScanImage({
  required ScanImage image,
  required ui.Image decoded,
  required Rect crop,
}) async {
  final size = Size(decoded.width.toDouble(), decoded.height.toDouble());
  if (!cropsAnything(crop, size)) return image;

  final bounds = clampCrop(crop, size);
  return ScanImage(
    bytes: await renderCrop(original: decoded, crop: bounds),
    mimeType: 'image/jpeg',
    width: bounds.width.round(),
    height: bounds.height.round(),
  );
}
