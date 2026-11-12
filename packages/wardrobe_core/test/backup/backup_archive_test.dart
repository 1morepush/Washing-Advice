/// The backup file: that everything goes in, comes out equal, and that a file
/// which is not sound is refused before anything is touched.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';
import '../support/selling_fixtures.dart';

final _made = DateTime.utc(2026, 11, 11, 9, 30);

/// Bytes that start like a PNG and differ per [seed], so two images never
/// compare equal by accident.
Uint8List png(int seed, {int length = 64}) => Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      for (var i = 0; i < length; i++) (seed * 31 + i) & 0xFF,
    ]);

WardrobeItem garment(
  String id, {
  List<ItemPhoto> photos = const [],
  DateTime? updatedAt,
  LifecycleState lifecycle = LifecycleState.active,
}) =>
    buildItem(id: id, lifecycle: lifecycle).copyWith(
      photos: PhotoSet(photos),
      updatedAt: updatedAt ?? DateTime.utc(2026, 3, 15, 10, 30),
    );

ItemPhoto photo(String uri, {String? cutout, PhotoRole? role}) => ItemPhoto(
      uri: uri,
      cutoutUri: cutout,
      role: role ?? PhotoRole.front,
      capturedAt: DateTime.utc(2026, 2, 1),
      width: 800,
      height: 1000,
      isPrimary: true,
    );

Outfit outfit(String id, {DateTime? updatedAt}) => Outfit(
      id: OutfitId(id),
      name: 'Saturday',
      itemIds: const [ItemId('a'), ItemId('b')],
      occasion: Occasion.everyday,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: updatedAt ?? DateTime.utc(2026, 8, 1),
    );

Future<BuiltBackup> build(
  BackupSnapshot snapshot, {
  Map<String, Uint8List> images = const {},
  BackupProgress? onProgress,
}) =>
    BackupWriter.build(
      snapshot,
      appVersion: '0.34.0',
      createdAt: _made,
      readImage: (uri) async => images[uri],
      onProgress: onProgress,
    );

/// A copy of [bytes] with some entries replaced, removed or added.
///
/// An archive's file list cannot be edited in place, so a variant of a good
/// backup is made by writing a new one.
Uint8List rezip(
  Uint8List bytes, {
  Map<String, String> replace = const {},
  Set<String> remove = const {},
  Map<String, String> add = const {},
}) {
  final out = Archive();
  for (final file in ZipDecoder().decodeBytes(bytes)) {
    if (remove.contains(file.name)) continue;
    out.add(
      replace.containsKey(file.name)
          ? ArchiveFile.string(file.name, replace[file.name]!)
          : ArchiveFile.noCompress(
              file.name,
              file.size,
              file.readBytes()!,
            ),
    );
  }
  for (final entry in add.entries) {
    out.add(ArchiveFile.string(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(out));
}

/// The JSON in one entry of a backup.
Object? json(Uint8List bytes, String name) => jsonDecode(
      utf8.decode(ZipDecoder().decodeBytes(bytes).findFile(name)!.readBytes()!),
    );

void main() {
  group('a backup round trip', () {
    late BackupSnapshot snapshot;
    late Map<String, Uint8List> images;

    setUp(() {
      images = {
        'file:///d/a-front.png': png(1),
        'file:///d/a-front-cutout.png': png(2),
        'wa-image:b-back': png(3, length: 500),
        'store://cover.jpg': png(4),
      };
      snapshot = BackupSnapshot(
        items: [
          garment(
            'a',
            photos: [
              photo(
                'file:///d/a-front.png',
                cutout: 'file:///d/a-front-cutout.png',
              ),
            ],
          ),
          garment('b',
              photos: [photo('wa-image:b-back', role: PhotoRole.back)]),
          garment('gone', lifecycle: LifecycleState.removed),
        ],
        events: [
          wornEvent('a', DateTime.utc(2026, 3, 1)),
          washedEvent('a', DateTime.utc(2026, 3, 2), temperatureC: 40),
          ItemRepaired(
            id: const EventId('repair-1'),
            itemId: const ItemId('b'),
            occurredAt: DateTime.utc(2026, 3, 3),
            description: 'new button',
          ),
        ],
        outfits: [outfit('o1')],
        listings: [fullListing()],
        settings: const {
          'washerBrand': 'bosch',
          'splitDrying': true,
          'customWasherProfile': {'name': 'x'},
        },
      );
    });

    test('brings back every record, equal', () async {
      final built = await build(snapshot, images: images);
      final opened = BackupReader.open(built.bytes);

      expect(opened.snapshot.items, snapshot.items);
      expect(opened.snapshot.events, snapshot.events);
      expect(opened.snapshot.outfits, snapshot.outfits);
      expect(opened.snapshot.listings, snapshot.listings);
      expect(opened.snapshot.settings, snapshot.settings);
    });

    test('brings back every image, byte for byte', () async {
      final built = await build(snapshot, images: images);
      final opened = BackupReader.open(built.bytes);

      expect(opened.imageUris.toSet(), images.keys.toSet());
      for (final entry in images.entries) {
        expect(opened.imageBytes(entry.key), entry.value, reason: entry.key);
      }
    });

    test('says what it holds, in the manifest and on opening', () async {
      final built = await build(snapshot, images: images);

      const expected = BackupCounts(
        items: 2,
        deletedItems: 1,
        events: 3,
        outfits: 1,
        listings: 1,
        images: 4,
        // The listing's second photograph is not among the images given.
        missingImages: 1,
      );
      expect(built.manifest.counts, expected);
      expect(built.manifest.appVersion, '0.34.0');
      expect(built.manifest.createdAt, _made);
      expect(built.manifest.formatVersion, backupFormatVersion);

      final opened = BackupReader.open(built.bytes);
      expect(opened.manifest.counts, expected);
      expect(opened.manifest.createdAt, _made);
      expect(opened.sizeInBytes, built.bytes.length);
    });

    test('summarises itself the way a person would', () {
      const counts = BackupCounts(
        items: 84,
        images: 212,
        listings: 3,
        deletedItems: 5,
      );
      expect(counts.summary, '84 garments, 212 photos, 3 listings');
      expect(
        const BackupCounts(items: 1, outfits: 1, events: 1).summary,
        '1 garment, 1 outfit, 1 history entry',
      );
      expect(const BackupCounts().summary, '0 garments');
    });

    test('stores a shared image once', () async {
      // A listing started from a garment points at the garment's own file.
      final shared = BackupSnapshot(
        items: [
          garment('a', photos: [photo('wa-image:shared')])
        ],
        listings: [
          draftListing(
            photos: const [
              ListingPhoto(uri: 'wa-image:shared', shot: ListingShot.cover),
            ],
          ),
        ],
      );
      final built = await build(
        shared,
        images: {'wa-image:shared': png(9)},
      );

      expect(built.manifest.counts.images, 1);
    });

    test('keeps records whose pictures were already gone, and says so',
        () async {
      final built =
          await build(snapshot, images: {...images}..remove('wa-image:b-back'));
      final opened = BackupReader.open(built.bytes);

      expect(built.manifest.counts.missingImages, 2);
      expect(built.manifest.counts.images, 3);
      expect(opened.missingImages, contains('wa-image:b-back'));
      expect(opened.snapshot.items, snapshot.items);
      expect(opened.imageBytes('wa-image:b-back'), isNull);
    });

    test('reports progress through the images', () async {
      final seen = <(int, int)>[];
      await build(snapshot,
          images: images, onProgress: (d, t) => seen.add((d, t)));

      expect(seen.first, (0, 5));
      expect(seen.last, (5, 5));
    });

    test('is a plain zip a person can open', () async {
      final built = await build(snapshot, images: images);
      final archive = ZipDecoder().decodeBytes(built.bytes);
      final names = [for (final f in archive) f.name];

      expect(names,
          containsAll(['manifest.json', 'README.txt', 'data/items.json']));
      expect(names.where((n) => n.startsWith('images/')), hasLength(4));
      expect(
        names.where((n) => n.startsWith('images/')),
        everyElement(matches(RegExp(r'^images/\d{5}-[A-Za-z0-9._-]+\.png$'))),
      );
    });

    test('carries no sync credential, whatever it is given', () async {
      // The app never puts one in; this pins that the archive adds none.
      final built = await build(snapshot, images: images);
      final text = utf8.decode(built.bytes, allowMalformed: true);
      expect(text, isNot(contains('syncToken')));
    });
  });

  group('an empty wardrobe', () {
    test('still makes a backup that opens', () async {
      final built = await build(const BackupSnapshot());
      final opened = BackupReader.open(built.bytes);

      expect(opened.manifest.counts, const BackupCounts());
      expect(opened.snapshot.items, isEmpty);
    });
  });

  group('reading tolerantly', () {
    Future<Uint8List> sample() async => (await build(
          BackupSnapshot(
            items: [
              garment('a', photos: [photo('wa-image:a')]),
            ],
            events: [wornEvent('a', DateTime.utc(2026, 3, 1))],
          ),
          images: {'wa-image:a': png(1)},
        ))
            .bytes;

    test('ignores keys it does not know, at every level', () async {
      final bytes = await sample();
      final manifest = json(bytes, 'manifest.json') as Map<String, Object?>;
      manifest['somethingNew'] = {'a': 1};
      (manifest['counts']! as Map<String, Object?>)['holograms'] = 7;
      final items = json(bytes, 'data/items.json') as List<Object?>;
      (items.first! as Map<String, Object?>)['futureField'] = 'ignored';

      final opened = BackupReader.open(
        rezip(
          bytes,
          replace: {
            'manifest.json': jsonEncode(manifest),
            'data/items.json': jsonEncode(items),
          },
          add: {'data/hats.json': '[]'},
        ),
      );
      expect(opened.snapshot.items.single.id, const ItemId('a'));
    });

    test('treats a missing settings file and app version as nothing', () async {
      final bytes = await sample();
      final manifest = json(bytes, 'manifest.json') as Map<String, Object?>
        ..remove('appVersion');

      final opened = BackupReader.open(
        rezip(
          bytes,
          remove: {'data/settings.json'},
          replace: {'manifest.json': jsonEncode(manifest)},
        ),
      );
      expect(opened.snapshot.settings, isEmpty);
      expect(opened.manifest.appVersion, 'unknown');
    });

    test('drops damaged settings rather than refusing sound garments',
        () async {
      final bytes = rezip(
        await sample(),
        replace: {'data/settings.json': '[not json'},
      );

      expect(BackupReader.open(bytes).snapshot.settings, isEmpty);
    });
  });

  group('refusing', () {
    Future<Uint8List> good() async => (await build(
          BackupSnapshot(
            items: [
              garment('a', photos: [photo('wa-image:a')]),
            ],
            events: [wornEvent('a', DateTime.utc(2026, 3, 1))],
          ),
          images: {'wa-image:a': png(1, length: 4000)},
        ))
            .bytes;

    Matcher refusedAs<T extends BackupException>() => throwsA(isA<T>());

    test('a backup from a newer format, with a clear message', () async {
      final original = await good();
      final manifest = json(original, 'manifest.json') as Map<String, Object?>;
      manifest['formatVersion'] = backupFormatVersion + 1;
      manifest['appVersion'] = '9.9.0';
      // Even a layout this build could not parse: the version is read first.
      manifest.remove('counts');
      final bytes = rezip(
        original,
        replace: {'manifest.json': jsonEncode(manifest)},
      );

      expect(
        () => BackupReader.open(bytes),
        throwsA(
          isA<BackupTooNew>()
              .having((e) => e.found, 'found', backupFormatVersion + 1)
              .having((e) => e.message, 'message', contains('newer version'))
              .having((e) => e.message, 'message', contains('9.9.0'))
              .having((e) => e.message, 'message', contains('Update the app')),
        ),
      );
    });

    test('text that is not a zip at all', () {
      expect(
        () => BackupReader.open(Uint8List.fromList(utf8.encode('hello there'))),
        refusedAs<BackupCorrupt>(),
      );
      expect(() => BackupReader.open(Uint8List(0)), refusedAs<BackupCorrupt>());
    });

    test('a zip that is some other zip', () {
      final other = Archive()..add(ArchiveFile.string('notes.txt', 'hi'));
      final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(other));

      expect(() => BackupReader.open(bytes), refusedAs<BackupNotABackup>());
    });

    test('a manifest that names another format', () {
      final other = Archive()
        ..add(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({'format': 'something-else', 'formatVersion': 1}),
          ),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(other));

      expect(() => BackupReader.open(bytes), refusedAs<BackupNotABackup>());
    });

    test('a file cut short, at any length', () async {
      final bytes = await good();

      // The central directory lives at the end, so any cut removes it, and
      // none may come back as a half-read wardrobe.
      for (final length in [
        0,
        1,
        10,
        bytes.length ~/ 3,
        bytes.length ~/ 2,
        bytes.length - 30,
        bytes.length - 1,
      ]) {
        expect(
          () => BackupReader.open(Uint8List.sublistView(bytes, 0, length)),
          throwsA(isA<BackupException>()),
          reason: 'cut to $length of ${bytes.length}',
        );
      }
    });

    test('an image whose bytes were altered', () async {
      final bytes = Uint8List.fromList(await good());
      // Find the stored image's run and flip a byte inside it.
      final marker = png(1, length: 4000);
      var at = -1;
      for (var i = 0; i + 100 < bytes.length && at < 0; i++) {
        var same = true;
        for (var j = 0; j < 100; j++) {
          if (bytes[i + j] != marker[j]) {
            same = false;
            break;
          }
        }
        if (same) at = i;
      }
      expect(at, isNonNegative, reason: 'image is stored uncompressed');
      bytes[at + 2000] ^= 0xFF;

      expect(() => BackupReader.open(bytes), throwsA(isA<BackupException>()));
    });

    test('a list that says one thing while the label says another', () async {
      final bytes = rezip(
        await good(),
        replace: {'data/events.json': '[]'},
      );

      expect(
        () => BackupReader.open(bytes),
        throwsA(
          isA<BackupCorrupt>().having(
            (e) => e.message,
            'message',
            contains('incomplete'),
          ),
        ),
      );
    });

    test('a data file that is missing', () async {
      final bytes = rezip(await good(), remove: {'data/items.json'});

      expect(() => BackupReader.open(bytes), refusedAs<BackupCorrupt>());
    });

    test('a record that cannot be read, naming which', () async {
      final bytes = rezip(
        await good(),
        replace: {
          'data/items.json': jsonEncode([
            {'id': 'a'},
          ]),
        },
      );

      expect(
        () => BackupReader.open(bytes),
        throwsA(
          isA<BackupCorrupt>()
              .having((e) => e.message, 'message', contains('Entry 1'))
              .having((e) => e.message, 'message', contains('garments')),
        ),
      );
    });

    test('an image the index lists but the file lacks', () async {
      final original = await good();
      final names = [
        for (final f in ZipDecoder().decodeBytes(original))
          if (f.name.startsWith('images/')) f.name,
      ];
      final bytes = rezip(original, remove: names.toSet());

      expect(() => BackupReader.open(bytes), refusedAs<BackupCorrupt>());
    });

    test('a manifest that is not JSON', () async {
      final bytes = rezip(
        await good(),
        replace: {'manifest.json': '{{{'},
      );

      expect(() => BackupReader.open(bytes), refusedAs<BackupCorrupt>());
    });
  });

  group('file names and sizes', () {
    test('is dated, and zero-padded', () {
      expect(
        backupFileName(DateTime(2026, 11, 11, 22)),
        'washing-advice-backup-2026-11-11.zip',
      );
      expect(
        backupFileName(DateTime(2026, 1, 5)),
        'washing-advice-backup-2026-01-05.zip',
      );
    });

    test('sizes read like a person would say them', () {
      expect(backupSizeLabel(0), '0 B');
      expect(backupSizeLabel(999), '999 B');
      expect(backupSizeLabel(1500), '1.5 KB');
      expect(backupSizeLabel(812000), '812 KB');
      expect(backupSizeLabel(12400000), '12.4 MB');
      expect(backupSizeLabel(2300000000), '2.3 GB');
    });
  });

  group('image names on restore', () {
    test('come from what the image is, whatever store it was in', () {
      expect(backupImageName('file:///d/images/abc-front-123.png'),
          'abc-front-123');
      expect(backupImageName('wa-image:abc-front-123'), 'abc-front-123');
      expect(backupImageName('wa-memory:abc-front-123'), 'abc-front-123');
    });

    test('cannot climb out of a directory', () {
      for (final hostile in [
        'file:///d/../../etc/passwd',
        'wa-image:../../x',
        'wa-image:..',
        'wa-image:a%2F..%2Fb',
        r'file:///d/a\..\b.png',
        '',
        'not a uri at all ///',
      ]) {
        final name = backupImageName(hostile);
        expect(name, isNotEmpty, reason: hostile);
        expect(name, matches(RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]*$')),
            reason: hostile);
        expect(name, isNot(contains('..')), reason: hostile);
      }
    });

    test('differ when the URIs differ, even if their names would not', () {
      final names = restoreNames([
        'file:///one/abc.png',
        'wa-image:abc',
        'file:///two/abc.png',
      ]);

      expect(names.values.toSet(), hasLength(3));
      expect(names['file:///one/abc.png'], 'abc');
    });

    test('are the same every time', () {
      final uris = ['wa-image:x', 'file:///y/x.png', 'wa-image:z'];
      expect(restoreNames(uris), restoreNames(uris));
    });
  });

  group('remapping images', () {
    test('re-points a garment and a listing, and leaves the rest alone', () {
      final item = garment(
        'a',
        photos: [photo('old:front', cutout: 'old:cut'), photo('old:keep')],
      );
      final moved =
          item.withImageUris({'old:front': 'new:front', 'old:cut': 'new:cut'});

      expect(moved.photos.photos.first.uri, 'new:front');
      expect(moved.photos.photos.first.cutoutUri, 'new:cut');
      expect(moved.photos.photos.last.uri, 'old:keep');
      expect(moved.updatedAt, item.updatedAt);
      expect(moved.photos.photos.first.role, item.photos.photos.first.role);

      final listing = draftListing(
        photos: const [ListingPhoto(uri: 'old:front', shot: ListingShot.cover)],
      ).withImageUris({'old:front': 'new:front'});
      expect(listing.photos.single.uri, 'new:front');
      expect(listing.photos.single.shot, ListingShot.cover);
    });
  });
}
