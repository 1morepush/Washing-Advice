/// The `ImageStore` contract, run against all three implementations.
///
/// There was no shared suite, which is how three implementations of a
/// four-method interface could quietly differ about what a missing image, a
/// foreign URI or an overwrite means. Each was tested — or not — on its own.
///
/// Every implementation ships: files on a phone, a database on the web, memory
/// in tests and the demo. A caller cannot tell which it has, so they had better
/// agree.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/images/drift_image_store.dart';
import 'package:washing_advice/data/images/file_image_store.dart';
import 'package:washing_advice/data/images/image_database.dart';
import 'package:washing_advice/data/images/image_store.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';

void main() {
  final temporary = <Directory>[];
  final databases = <ImageDatabase>[];

  tearDown(() async {
    for (final db in databases) {
      await db.close();
    }
    databases.clear();
    for (final directory in temporary) {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
    temporary.clear();
  });

  ImageStore memory() => MemoryImageStore();

  ImageStore files() {
    final directory = Directory.systemTemp.createTempSync('image-store-');
    temporary.add(directory);
    return FileImageStore.inDirectory(directory);
  }

  ImageDatabase openDatabase() {
    final db = ImageDatabase(NativeDatabase.memory());
    databases.add(db);
    return db;
  }

  ImageStore drift() => DriftImageStore(openDatabase());

  runImageStoreContract('MemoryImageStore', memory);
  runImageStoreContract('FileImageStore', files);
  runImageStoreContract('DriftImageStore', drift);

  group('DriftImageStore specifics', () {
    test('hands back a reference, not the image itself', () async {
      // The reason it exists rather than reusing the memory store's `data:`
      // URIs: a `data:` URI *is* the image, so persisting it means copying
      // base64 into the wardrobe row and into every sync payload thereafter.
      final uri = await drift().save(_bytes(4096), name: 'tee-front');

      expect(uri, 'wa-image:tee-front');
      expect(uri.length, lessThan(64));
    });

    test('survives the store being reopened over the same database', () async {
      // The whole point on the web: a reload must not empty the wardrobe of
      // its pictures.
      final db = openDatabase();
      final uri = await DriftImageStore(db).save(_bytes(16), name: 'tee-front');

      expect(await DriftImageStore(db).read(uri), _bytes(16));
    });

    test('reports what it is holding', () async {
      final db = openDatabase();
      final store = DriftImageStore(db);

      await store.save(_bytes(100), name: 'a');
      await store.save(_bytes(250), name: 'b');

      expect(await db.totalBytes(), 350);
    });
  });
}

void runImageStoreContract(String name, ImageStore Function() create) {
  group('$name: the contract', () {
    late ImageStore store;

    setUp(() => store = create());

    test('what is saved can be read back exactly', () async {
      final bytes = _bytes(2048);
      final uri = await store.save(bytes, name: 'tee-front');

      expect(await store.read(uri), bytes);
    });

    test('an empty image is not mistaken for a missing one', () async {
      // A zero-byte file is a real thing that a failed write leaves behind,
      // and it must not read back as null — that is how a bug becomes a
      // silently blank wardrobe.
      final uri = await store.save(Uint8List(0), name: 'tee-front');

      expect(await store.read(uri), isNotNull);
      expect(await store.read(uri), isEmpty);
    });

    test('saving the same name replaces rather than accumulating', () async {
      // Names are derived from item and role precisely so re-running a cutout
      // overwrites its predecessor instead of leaking one per attempt.
      await store.save(_bytes(10), name: 'tee-front');
      final second = await store.save(_bytes(20), name: 'tee-front');

      expect(await store.read(second), hasLength(20));
    });

    test('a deleted image is null, not an exception', () async {
      // Storage can be cleared, or a backup restored that carried the database
      // and not the images. A wardrobe that crashes rather than drawing a
      // placeholder is worse than useless.
      final uri = await store.save(_bytes(8), name: 'tee-front');
      await store.delete(uri);

      expect(await store.read(uri), isNull);
    });

    test('a URI from a different store does not resolve', () async {
      // Exactly what happens when a wardrobe moves between platforms.
      for (final foreign in [
        'file:///somewhere/else.png',
        'wa-image:not-here',
        'https://example.invalid/x.png',
      ]) {
        expect(await store.read(foreign), isNull, reason: foreign);
      }
    });

    test('nonsense is null rather than a crash', () async {
      for (final rubbish in ['', 'not a uri at all', '::::', 'wa-image:']) {
        expect(await store.read(rubbish), isNull, reason: rubbish);
      }
    });

    test('deleting something absent is not an error', () async {
      await store.delete('wa-image:never-existed');
      await store.delete('file:///nope.png');
    });

    test('two names do not collide', () async {
      final front = await store.save(_bytes(10), name: 'tee-front');
      final cutout = await store.save(_bytes(20), name: 'tee-front-cutout');

      expect(await store.read(front), hasLength(10));
      expect(await store.read(cutout), hasLength(20));
    });

    test('deleting one leaves the other', () async {
      final front = await store.save(_bytes(10), name: 'tee-front');
      final cutout = await store.save(_bytes(20), name: 'tee-front-cutout');

      await store.delete(front);

      expect(await store.read(front), isNull);
      expect(await store.read(cutout), hasLength(20));
    });

    test('works with the names the app actually derives', () async {
      // Rather than with hand-written strings, so a change to `imageName`
      // cannot produce something a store mishandles.
      final derived = imageName(const ItemId('abc-123'), PhotoRole.front);
      final uri = await store.save(_bytes(12), name: derived);

      expect(await store.read(uri), hasLength(12));
    });
  });
}

Uint8List _bytes(int length) =>
    Uint8List.fromList(List.generate(length, (i) => i % 256));
