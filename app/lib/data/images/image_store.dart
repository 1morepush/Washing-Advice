/// Where photographs and cutouts live on disk.
///
/// Images do **not** go in the database. A wardrobe of two hundred garments
/// with a front shot and a cutout each is hundreds of megabytes; putting that
/// in SQLite makes every query slower, every backup enormous, and every read
/// of an item drag its pixels along whether or not anything is going to draw
/// them.
///
/// So the database stores a URI and the bytes sit beside it as files. That is
/// exactly what `ItemPhoto.uri` being "deliberately opaque" was for.
library;

import 'dart:typed_data';

import 'package:wardrobe_core/wardrobe_core.dart';

/// Reads and writes image bytes.
///
/// An interface because the web has no filesystem: the demo and any browser
/// build keep bytes in memory and hand back `data:` URIs, while a phone writes
/// real files. Nothing above this line knows which.
abstract interface class ImageStore {
  /// Stores [bytes] and returns the URI to record on the item.
  Future<String> save(Uint8List bytes, {required String name});

  /// Reads bytes back, or null if the file is gone.
  ///
  /// Null rather than throwing: an image can vanish when a user clears app
  /// storage or restores a backup that carried the database but not the
  /// files, and a wardrobe that crashes rather than showing a placeholder in
  /// that situation is worse than useless.
  Future<Uint8List?> read(String uri);

  Future<void> delete(String uri);
}

/// Names a stored image deterministically.
///
/// Derived from the item and role rather than random, so re-running a cutout
/// overwrites the old one instead of leaking a file per attempt.
String imageName(ItemId id, PhotoRole role, {bool cutout = false}) =>
    '${id.value}-${role.name}${cutout ? '-cutout' : ''}';
