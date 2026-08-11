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
///
/// [takenAt] separates photographs that share a role. A retaken front shot must
/// not be written over the one it replaces: the item keeps each photo's own
/// `width` and `height`, so overwriting the bytes and leaving the record
/// would leave the old dimensions describing the new picture. It also keeps the
/// original, which the user may want back if the second attempt is worse.
///
/// Omitted, the name is what it always was — images stored before retaking
/// existed keep their URIs, and nothing has to be migrated.
String imageName(
  ItemId id,
  PhotoRole role, {
  DateTime? takenAt,
  bool cutout = false,
}) =>
    '${id.value}-${role.name}'
    '${takenAt == null ? '' : '-${takenAt.toUtc().microsecondsSinceEpoch}'}'
    '${cutout ? '-cutout' : ''}';

/// The name for [photo]'s cutout.
///
/// Always timestamped, including for photographs whose own name is not — the
/// only requirement is that one photo's cutout does not collide with another's.
/// Regenerating a cutout for a photo stored before this existed therefore
/// writes a new file, so callers delete the superseded one rather than leaving
/// it behind.
String cutoutNameFor(ItemId id, ItemPhoto photo) =>
    imageName(id, photo.role, takenAt: photo.capturedAt, cutout: true);
