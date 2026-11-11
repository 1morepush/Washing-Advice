/// The backup file: writing it, and reading it back with suspicion.
///
/// ## What is in it
///
/// One zip, which a person can keep, attach to an email, or open to look at:
///
/// ```text
/// manifest.json       format, format version, app version, created-at, counts
/// README.txt          what this is and how to use it, for whoever finds it
/// data/items.json     every garment, deleted ones included
/// data/events.json    the history
/// data/outfits.json   saved outfits
/// data/listings.json  the Sell tab
/// data/settings.json  the preferences worth keeping
/// data/images.json    which stored image each file is, and which were missing
/// images/00001-….png  the photographs and cutouts themselves
/// ```
///
/// Records are the same JSON the app already writes to its database and to
/// sync, so there is no second serialisation to keep in step with the first.
///
/// ## Why images are separate files, not inlined
///
/// A wardrobe is mostly pixels. As files in a zip they stay what they are, are
/// not wrapped in base64 (a third bigger and a copy of each in memory as a
/// string), and can be read one at a time. They are stored uncompressed: a
/// PNG or JPEG is already as small as it is going to get, and deflating it
/// again costs time and gains nothing.
///
/// ## Reading
///
/// [BackupReader.open] checks everything before it returns: the zip's own
/// checksums, the manifest, that every record decodes, that the counts add up,
/// that every image the index names is there and intact. Applying a restore
/// happens strictly after, so a damaged file is refused while nothing has been
/// touched.
///
/// A record that will not decode is damage, not something to skip. Skipping it
/// would restore the rest and report success, and in a *replace* the garment
/// it described would be gone from both places.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../events/wardrobe_event.dart';
import '../outfits/model/outfit.dart';
import '../selling/listing.dart';
import '../wardrobe/model/lifecycle.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'backup_manifest.dart';
import 'backup_snapshot.dart';

/// Gives back the bytes behind an image URI, or null if they are gone.
///
/// The same promise `ImageStore.read` makes, and for the same reason: a
/// missing picture is a fact to report, not a reason to refuse the backup of
/// everything else.
typedef BackupImageReader = Future<Uint8List?> Function(String uri);

/// How far along: [done] of [total] images, so far.
typedef BackupProgress = void Function(int done, int total);

/// A finished backup: the file, and what it says about itself.
final class BuiltBackup {
  const BuiltBackup({required this.bytes, required this.manifest});

  final Uint8List bytes;
  final BackupManifest manifest;
}

const _manifestFile = 'manifest.json';
const _itemsFile = 'data/items.json';
const _eventsFile = 'data/events.json';
const _outfitsFile = 'data/outfits.json';
const _listingsFile = 'data/listings.json';
const _settingsFile = 'data/settings.json';
const _imagesFile = 'data/images.json';

/// Builds backups.
abstract final class BackupWriter {
  /// Packs [snapshot] and every image it points at into one archive.
  ///
  /// Images are read one at a time through [readImage] and handed to the
  /// archive as they arrive, so at no point are there two copies of the
  /// wardrobe's pictures — the store's, and a list this function made first.
  /// The archive does hold them all until it is encoded, which is the cost of
  /// a zip written in one piece; see the README for the size that implies.
  ///
  /// Gives the event loop a turn every few images, so that a screen showing
  /// [onProgress] gets to draw it.
  static Future<BuiltBackup> build(
    BackupSnapshot snapshot, {
    required String appVersion,
    required DateTime createdAt,
    required BackupImageReader readImage,
    BackupProgress? onProgress,
  }) async {
    final archive = Archive();
    final uris = snapshot.imageUris.toList();

    final stored = <Map<String, Object?>>[];
    final missing = <String>[];
    for (var i = 0; i < uris.length; i++) {
      final uri = uris[i];
      onProgress?.call(i, uris.length);
      if (i % 4 == 3) await Future<void>.delayed(Duration.zero);

      final bytes = await readImage(uri);
      if (bytes == null || bytes.isEmpty) {
        missing.add(uri);
        continue;
      }
      final file = 'images/${(stored.length + 1).toString().padLeft(5, '0')}-'
          '${backupImageName(uri)}${_extensionFor(bytes)}';
      archive.add(ArchiveFile.noCompress(file, bytes.length, bytes));
      stored.add({'uri': uri, 'file': file});
    }
    onProgress?.call(uris.length, uris.length);

    final deleted = snapshot.items
        .where((i) => i.lifecycle == LifecycleState.removed)
        .length;
    final manifest = BackupManifest(
      appVersion: appVersion,
      createdAt: createdAt.toUtc(),
      counts: BackupCounts(
        items: snapshot.items.length - deleted,
        deletedItems: deleted,
        events: snapshot.events.length,
        outfits: snapshot.outfits.length,
        listings: snapshot.listings.length,
        images: stored.length,
        missingImages: missing.length,
      ),
    );

    // Everything else goes in front of the pictures, so that the part a
    // person would open to see what the file is sits at the start of it.
    final head = Archive()
      ..add(
        _json(_manifestFile, manifest.toJson(), pretty: true),
      )
      ..add(ArchiveFile.string('README.txt', _readme))
      ..add(_json(_itemsFile, [for (final i in snapshot.items) i.toJson()]))
      ..add(_json(_eventsFile, [for (final e in snapshot.events) e.toJson()]))
      ..add(_json(_outfitsFile, [for (final o in snapshot.outfits) o.toJson()]))
      ..add(
        _json(_listingsFile, [for (final l in snapshot.listings) l.toJson()]),
      )
      ..add(_json(_settingsFile, snapshot.settings))
      ..add(_json(_imagesFile, {'images': stored, 'missing': missing}));
    for (final file in archive) {
      head.add(file);
    }

    final bytes = ZipEncoder().encodeBytes(head, modified: createdAt.toUtc());
    return BuiltBackup(bytes: Uint8List.fromList(bytes), manifest: manifest);
  }

  static ArchiveFile _json(String name, Object? value, {bool pretty = false}) =>
      ArchiveFile.string(
        name,
        pretty
            ? const JsonEncoder.withIndent('  ').convert(value)
            : jsonEncode(value),
      );

  static String _extensionFor(Uint8List b) {
    bool starts(List<int> magic) =>
        b.length >= magic.length &&
        [for (var i = 0; i < magic.length; i++) b[i] == magic[i]]
            .every((x) => x);

    if (starts(const [0x89, 0x50, 0x4E, 0x47])) return '.png';
    if (starts(const [0xFF, 0xD8, 0xFF])) return '.jpg';
    if (starts(const [0x47, 0x49, 0x46, 0x38])) return '.gif';
    if (b.length >= 12 &&
        starts(const [0x52, 0x49, 0x46, 0x46]) &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return '.webp';
    }
    return '.bin';
  }

  static const _readme = 'This is a Washing Advice backup.\n'
      '\n'
      'To bring it back: open the app, go to Settings > Backup and choose\n'
      '"Restore from a backup". Please do not edit the files inside; the app\n'
      'checks them and will refuse a backup that has been changed.\n'
      '\n'
      'manifest.json says when it was made and what it holds. The pictures are\n'
      'in images/ and open in any image viewer.\n'
      '\n'
      'It does not contain your sync token or the server address, so that\n'
      'sharing this file never shares the key to a synced wardrobe.\n';
}

/// A backup that has been read and found sound, ready to be applied.
final class OpenedBackup {
  OpenedBackup._({
    required this.manifest,
    required this.snapshot,
    required Map<String, ArchiveFile> images,
    required this.missingImages,
    required this.sizeInBytes,
  }) : _images = images;

  final BackupManifest manifest;

  /// Every record in the file, decoded.
  final BackupSnapshot snapshot;

  /// URIs the records mention that were not in the archive when it was made.
  final List<String> missingImages;

  /// How big the file is, for showing alongside what it holds.
  final int sizeInBytes;

  final Map<String, ArchiveFile> _images;

  /// The URIs of the images the archive carries.
  Iterable<String> get imageUris => _images.keys;

  int get imageCount => _images.length;

  /// The bytes of one image, or null if the archive does not have it.
  ///
  /// Read from the archive when asked, not before, so restoring a large
  /// wardrobe holds one picture at a time rather than all of them twice.
  Uint8List? imageBytes(String uri) => _images[uri]?.readBytes();
}

/// Opens backups.
abstract final class BackupReader {
  /// Reads and fully validates [bytes], or throws a [BackupException].
  ///
  /// Synchronous on purpose: it does no I/O, and returning a future would only
  /// suggest it could be interleaved with something that changes the data it
  /// is checking.
  static OpenedBackup open(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } on Object {
      // The zip layer's own errors are about offsets and signatures. What
      // the person needs to know is that this file is not usable, and why
      // that is probably so.
      throw const BackupCorrupt(
        'This file could not be read. It may not be a backup, or it may have '
        'been cut short while it was copied or downloaded.',
      );
    }

    final manifestFile = archive.findFile(_manifestFile);
    if (manifestFile == null) {
      throw const BackupNotABackup('This file is not a Washing Advice backup.');
    }
    final manifest = BackupManifest.fromJson(
      _object(manifestFile, 'its label'),
    );

    List<Map<String, Object?>> records(String file, String what, int expected) {
      final entry = archive.findFile(file);
      if (entry == null) {
        if (expected == 0) return const [];
        throw BackupCorrupt(
          'This backup is incomplete: the list of $what is missing.',
        );
      }
      final decoded = _decode(entry, 'the list of $what');
      if (decoded is! List<Object?>) {
        throw BackupCorrupt('The list of $what in this backup is damaged.');
      }
      final out = <Map<String, Object?>>[];
      for (final record in decoded) {
        if (record is! Map<String, Object?>) {
          throw BackupCorrupt('The list of $what in this backup is damaged.');
        }
        out.add(record);
      }
      if (out.length != expected) {
        throw BackupCorrupt(
          'This backup is incomplete: it should hold $expected $what but '
          'holds ${out.length}.',
        );
      }
      return out;
    }

    List<T> decodeAll<T>(
      String what,
      List<Map<String, Object?>> raw,
      T Function(Map<String, Object?>) decode,
    ) {
      final out = <T>[];
      for (var i = 0; i < raw.length; i++) {
        try {
          out.add(decode(raw[i]));
        } on Object {
          throw BackupCorrupt(
            'Entry ${i + 1} of the $what in this backup could not be read, '
            'so none of it has been used.',
          );
        }
      }
      return out;
    }

    final counts = manifest.counts;
    final items = decodeAll(
      'garments',
      records(_itemsFile, 'garments', counts.items + counts.deletedItems),
      WardrobeItem.fromJson,
    );
    final deleted =
        items.where((i) => i.lifecycle == LifecycleState.removed).length;
    if (deleted != counts.deletedItems) {
      throw const BackupCorrupt(
        'This backup is inconsistent: its list of garments does not match '
        'what its label says.',
      );
    }

    final events = decodeAll(
      'history entries',
      records(_eventsFile, 'history entries', counts.events),
      WardrobeEvent.fromJson,
    );
    final outfits = decodeAll(
      'outfits',
      records(_outfitsFile, 'outfits', counts.outfits),
      Outfit.fromJson,
    );
    final listings = decodeAll(
      'listings',
      records(_listingsFile, 'listings', counts.listings),
      Listing.fromJson,
    );

    // Preferences are a convenience. Damaged ones are dropped rather than
    // refusing a backup whose garments are all sound.
    var settings = const <String, Object?>{};
    if (archive.findFile(_settingsFile) case final entry?) {
      try {
        settings = _object(entry, 'its settings');
      } on BackupException {
        settings = const {};
      }
    }

    final images = <String, ArchiveFile>{};
    final missing = <String>[];
    if (archive.findFile(_imagesFile) case final entry?) {
      final index = _object(entry, 'its list of photos');
      final listed = index['images'];
      if (listed is! List<Object?>) {
        throw const BackupCorrupt(
            'The list of photos in this backup is damaged.');
      }
      for (final row in listed) {
        final uri = row is Map<String, Object?> ? row['uri'] : null;
        final file = row is Map<String, Object?> ? row['file'] : null;
        if (uri is! String || file is! String) {
          throw const BackupCorrupt(
            'The list of photos in this backup is damaged.',
          );
        }
        final stored = archive.findFile(file);
        if (stored == null) {
          throw const BackupCorrupt(
            'This backup is incomplete: a photograph it lists is missing.',
          );
        }
        // Reading it is what proves it is intact.
        try {
          stored.readBytes();
        } on Object {
          throw const BackupCorrupt(
            'A photograph in this backup is damaged, so none of it has been '
            'used.',
          );
        }
        images[uri] = stored;
      }
      if (index['missing'] case final List<Object?> gone) {
        missing.addAll(gone.whereType<String>());
      }
    }
    if (images.length != counts.images) {
      throw BackupCorrupt(
        'This backup is incomplete: it should hold ${counts.images} photos '
        'but holds ${images.length}.',
      );
    }

    return OpenedBackup._(
      manifest: manifest,
      snapshot: BackupSnapshot(
        items: items,
        events: events,
        outfits: outfits,
        listings: listings,
        settings: settings,
      ),
      images: images,
      missingImages: missing,
      sizeInBytes: bytes.length,
    );
  }

  static Map<String, Object?> _object(ArchiveFile file, String what) {
    final decoded = _decode(file, what);
    if (decoded is! Map<String, Object?>) {
      throw BackupCorrupt('$what in this backup is damaged.');
    }
    return decoded;
  }

  static Object? _decode(ArchiveFile file, String what) {
    try {
      return jsonDecode(utf8.decode(file.readBytes() ?? Uint8List(0)));
    } on Object {
      throw BackupCorrupt('$what in this backup is damaged.');
    }
  }
}
