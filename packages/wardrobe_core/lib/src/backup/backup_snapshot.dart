/// Everything a backup holds, as plain values.
///
/// A snapshot is what *would* be written or what *was* read: the records, with
/// no opinion on where they came from or where they are going. Keeping it a
/// value is what lets the merge rules be tested with lists, and lets the app
/// feed it from Drift and the tests from memory.
library;

import 'dart:collection';

import '../events/wardrobe_event.dart';
import '../outfits/model/outfit.dart';
import '../selling/listing.dart';
import '../wardrobe/model/lifecycle.dart';
import '../wardrobe/model/photo.dart';
import '../wardrobe/model/wardrobe_item.dart';

final class BackupSnapshot {
  const BackupSnapshot({
    this.items = const [],
    this.events = const [],
    this.outfits = const [],
    this.listings = const [],
    this.settings = const {},
  });

  /// Every garment, **including deleted ones**.
  ///
  /// A deleted garment is a row with a lifecycle of `removed`, kept so the
  /// deletion can travel. A backup that left those out would restore to a
  /// state in which the garment had never been deleted.
  final List<WardrobeItem> items;
  final List<WardrobeEvent> events;
  final List<Outfit> outfits;
  final List<Listing> listings;

  /// The preferences worth carrying to another phone, as the app chose to
  /// name them. Opaque to the core: it holds them and gives them back, and
  /// the app alone knows what a key means. See `PortableSettings` in the app.
  final Map<String, Object?> settings;

  /// Garments somebody can see, i.e. not deleted.
  int get liveItemCount =>
      items.where((i) => i.lifecycle != LifecycleState.removed).length;

  /// Every image any record points at, each once, in the order met.
  ///
  /// Photographs and cutouts of garments, and the photographs on listings. A
  /// listing started from a garment points at the garment's own files, so the
  /// same URI turns up twice; storing it once is the point of a set.
  Set<String> get imageUris {
    final uris = LinkedHashSet<String>();
    for (final item in items) {
      for (final photo in item.photos.photos) {
        uris.add(photo.uri);
        if (photo.cutoutUri case final String cutout) uris.add(cutout);
      }
    }
    for (final listing in listings) {
      for (final photo in listing.photos) {
        uris.add(photo.uri);
      }
    }
    return uris;
  }
}

/// Re-pointing records at images stored somewhere new.
///
/// An image's URI is the *storage's* name for it — a file path on one phone, a
/// database key in a browser — so a record restored onto a different device
/// has to be told where its pictures now are. Everything not in the map is
/// left as it was, which is right for an image that could not be backed up:
/// the record keeps its old reference and the app shows a placeholder, exactly
/// as it did before.
extension RemapImages on WardrobeItem {
  WardrobeItem withImageUris(Map<String, String> moved) {
    if (moved.isEmpty || photos.isEmpty) return this;
    return copyWith(
      photos: PhotoSet([
        for (final photo in photos.photos)
          ItemPhoto(
            uri: moved[photo.uri] ?? photo.uri,
            cutoutUri: photo.cutoutUri == null
                ? null
                : (moved[photo.cutoutUri] ?? photo.cutoutUri),
            role: photo.role,
            capturedAt: photo.capturedAt,
            width: photo.width,
            height: photo.height,
            isPrimary: photo.isPrimary,
          ),
      ]),
    );
  }
}

extension RemapListingImages on Listing {
  Listing withImageUris(Map<String, String> moved) {
    if (moved.isEmpty || photos.isEmpty) return this;
    return copyWith(
      photos: [
        for (final photo in photos)
          photo.copyWith(uri: moved[photo.uri] ?? photo.uri),
      ],
    );
  }
}

/// A name to store an image under when it is restored.
///
/// Taken from the original URI rather than invented, because the app names its
/// images from what they are of (the garment, the shot, the moment) and two
/// restores of the same backup must land on the same names — otherwise each
/// one would leave a second copy of every photograph behind.
///
/// Anything that could climb out of the images directory when joined to a
/// path is replaced, because the URI comes out of a file a person was handed
/// and nothing stops it having been written by hand.
String backupImageName(String uri) {
  final parsed = Uri.tryParse(uri);
  final segments = parsed == null
      ? const <String>[]
      : [
          for (final s in parsed.pathSegments)
            if (s.isNotEmpty) s,
        ];

  var stem = segments.isEmpty ? '' : segments.last;
  stem = stem.replaceFirst(
    RegExp(r'\.(png|jpe?g|webp|gif|bin)$', caseSensitive: false),
    '',
  );

  final safe = stem
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
      .replaceAll('..', '_')
      .replaceFirst(RegExp(r'^\.+'), '');

  // Altered, empty or long: still usable, but no longer *the* name, so the
  // original is folded in to keep two different ones from landing together.
  if (safe.isEmpty || safe != stem || safe.length > 120) {
    final head = safe.length > 80 ? safe.substring(0, 80) : safe;
    return '${head.isEmpty ? 'image' : head}-${_hash(uri)}';
  }
  return safe;
}

/// One restore name per URI, no two alike.
///
/// Two different URIs can have one name — a file path and a database key that
/// both end in `abc-front` — and the second written would replace the first.
/// The later one is renamed; the earlier keeps the name it would have had on
/// its own, which is what a second restore will produce again.
Map<String, String> restoreNames(Iterable<String> uris) {
  final taken = <String>{};
  final names = <String, String>{};
  for (final uri in uris) {
    final base = backupImageName(uri);
    var name = base;
    var n = 2;
    while (!taken.add(name)) {
      name = '$base-${n++}';
    }
    names[uri] = name;
  }
  return names;
}

/// A short, stable digest. Not for security: it only has to differ.
String _hash(String text) {
  var h = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}
