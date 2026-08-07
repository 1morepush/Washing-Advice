/// An [ImageStore] backed by its own small database.
///
/// The web build's answer to having no filesystem. See `image_database.dart`
/// for why this is a separate database rather than a table in the wardrobe's.
///
/// URIs are `wa-image:<name>` rather than the `data:` URIs the in-memory store
/// hands back. That difference is the whole point: a `data:` URI *is* the
/// image, so it survives a reload only by being copied into the wardrobe row,
/// which bloats every item and every sync payload with base64. A reference
/// keeps the bytes in one place and the row small.
library;

import 'dart:typed_data';

import 'image_database.dart';
import 'image_store.dart';

/// The scheme this store issues and answers to.
///
/// Deliberately not `file:` or `data:`, so a URI written by one store is never
/// silently mishandled by another — a wardrobe restored onto a different
/// platform hits an unreadable image and shows the colour swatch, rather than
/// reading bytes from somewhere it should not.
const String driftImageScheme = 'wa-image';

class DriftImageStore implements ImageStore {
  DriftImageStore(this._db);

  final ImageDatabase _db;

  @override
  Future<String> save(Uint8List bytes, {required String name}) async {
    await _db.put(name, bytes);
    return '$driftImageScheme:$name';
  }

  @override
  Future<Uint8List?> read(String uri) async {
    final name = _nameFrom(uri);
    return name == null ? null : _db.get(name);
  }

  @override
  Future<void> delete(String uri) async {
    final name = _nameFrom(uri);
    if (name != null) await _db.remove(name);
  }

  /// The name inside a URI this store issued, or null for anything else.
  ///
  /// Null rather than throwing, matching the interface's rule: an image can be
  /// missing or foreign, and a wardrobe that crashes instead of drawing a
  /// placeholder is worse than useless.
  String? _nameFrom(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !parsed.isScheme(driftImageScheme)) return null;
    final name = parsed.path;
    return name.isEmpty ? null : name;
  }
}
