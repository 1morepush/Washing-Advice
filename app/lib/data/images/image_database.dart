/// Image bytes, in their own database.
///
/// `image_store.dart` says images do not go in the database, and gives three
/// reasons: it slows every query, it makes backups enormous, and reading an
/// item drags its pixels along. Those are right, and they are all about the
/// *wardrobe* database — so this is a second, separate one that nothing else
/// ever opens. Reading an item still touches no bytes; the wardrobe file stays
/// small and portable; only drawing an image opens this at all.
///
/// It exists for the web, which has no filesystem. Until now a browser build
/// kept bytes in memory and lost every picture on reload, which is tolerable
/// for a demo and not for anyone actually using it. Drift's web backend
/// persists through IndexedDB or OPFS, so this is the same storage the
/// wardrobe already trusts rather than a new mechanism to get wrong.
///
/// Native platforms keep using `FileImageStore`. A filesystem is the right
/// place for files, and nothing here improves on it.
library;

import 'package:drift/drift.dart';

part 'image_database.g.dart';

/// One stored image, keyed by the name the app derives from item and role.
class StoredImages extends Table {
  /// `imageName(...)` — deterministic, so re-running a cutout replaces its
  /// predecessor instead of leaking a row per attempt.
  TextColumn get name => text()();

  BlobColumn get bytes => blob()();

  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}

@DriftDatabase(tables: [StoredImages])
class ImageDatabase extends _$ImageDatabase {
  ImageDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  Future<void> put(String name, Uint8List bytes) =>
      into(storedImages).insertOnConflictUpdate(
        StoredImagesCompanion.insert(
          name: name,
          bytes: bytes,
          savedAt: DateTime.now().toUtc(),
        ),
      );

  Future<Uint8List?> get(String name) async {
    final row = await (select(
      storedImages,
    )..where((t) => t.name.equals(name))).getSingleOrNull();
    return row?.bytes;
  }

  Future<void> remove(String name) =>
      (delete(storedImages)..where((t) => t.name.equals(name))).go();

  /// Total bytes held, for a future "clear cached images" control.
  Future<int> totalBytes() async {
    final rows = await select(storedImages).get();
    return rows.fold<int>(0, (sum, row) => sum + row.bytes.length);
  }
}
