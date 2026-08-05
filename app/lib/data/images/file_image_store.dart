/// The on-device image store.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'image_store.dart';

class FileImageStore implements ImageStore {
  FileImageStore._(this._directory);

  /// Opens the store, creating its directory.
  ///
  /// Under the *support* directory rather than documents or cache: these files
  /// are not user documents to be browsed, and they are not disposable either
  /// — the OS may evict a cache directory at any time, which would silently
  /// empty someone's wardrobe of its pictures.
  static Future<FileImageStore> open() async {
    final base = await getApplicationSupportDirectory();
    final directory = Directory(p.join(base.path, 'images'));
    await directory.create(recursive: true);
    return FileImageStore._(directory);
  }

  final Directory _directory;

  @override
  Future<String> save(Uint8List bytes, {required String name}) async {
    final file = File(p.join(_directory.path, '$name.png'));
    await file.writeAsBytes(bytes, flush: true);
    return file.uri.toString();
  }

  @override
  Future<Uint8List?> read(String uri) async {
    final file = _fileFor(uri);
    if (file == null || !file.existsSync()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> delete(String uri) async {
    final file = _fileFor(uri);
    if (file != null && file.existsSync()) await file.delete();
  }

  /// Resolves a stored URI back to a file, refusing anything outside the
  /// store's own directory.
  ///
  /// The URI comes out of the database, and a database can be restored from a
  /// backup written by another install or another device. Following an
  /// arbitrary path from it would let a corrupted or hostile row read any file
  /// the app can reach.
  File? _fileFor(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !parsed.isScheme('file')) return null;

    final path = p.normalize(parsed.toFilePath());
    if (!p.isWithin(_directory.path, path)) return null;
    return File(path);
  }
}
