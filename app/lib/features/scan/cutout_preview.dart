/// Framing a worn cutout for a tile.
///
/// A worn-photo cutout covers its whole detection box, so the editor can line
/// it up with the opaque crop beside it. That frame is mostly transparent
/// margin once a shirt is cut out of it, and a tile that draws it whole shows a
/// small garment in a big empty square. The stored cutout stays the full frame;
/// only the picture handed to a tile is trimmed to where the garment is.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:wardrobe_core/wardrobe_core.dart';

/// Alpha at or below this is empty for framing: the feathered edge's faintest
/// pixels must not keep a whole margin alive.
const _visibleAlpha = 12;

/// Room left around the garment, as a share of its longer edge.
const _margin = 0.04;

/// [cutout] trimmed to where it is visible, plus a small margin; [cutout]
/// itself when it cannot be decoded, has nothing visible or is already tight.
ScanImage trimmedForTile(ScanImage cutout) {
  try {
    final decoded = img.decodePng(Uint8List.fromList(cutout.bytes));
    if (decoded == null || !decoded.hasAlpha) return cutout;

    var left = decoded.width;
    var top = decoded.height;
    var right = -1;
    var bottom = -1;
    for (final pixel in decoded) {
      if (pixel.a <= _visibleAlpha) continue;
      if (pixel.x < left) left = pixel.x;
      if (pixel.x > right) right = pixel.x;
      if (pixel.y < top) top = pixel.y;
      if (pixel.y > bottom) bottom = pixel.y;
    }
    if (right < 0) return cutout;

    final margin =
        (((right - left + 1) > (bottom - top + 1)
                    ? right - left + 1
                    : bottom - top + 1) *
                _margin)
            .ceil();
    final x = (left - margin).clamp(0, decoded.width - 1);
    final y = (top - margin).clamp(0, decoded.height - 1);
    final width = (right + margin + 1).clamp(1, decoded.width) - x;
    final height = (bottom + margin + 1).clamp(1, decoded.height) - y;
    if (x == 0 &&
        y == 0 &&
        width == decoded.width &&
        height == decoded.height) {
      return cutout;
    }

    final cropped = img.copyCrop(
      decoded,
      x: x,
      y: y,
      width: width,
      height: height,
    );
    return ScanImage(
      bytes: img.encodePng(cropped),
      mimeType: 'image/png',
      width: width,
      height: height,
    );
  } on Exception {
    return cutout;
  }
}
