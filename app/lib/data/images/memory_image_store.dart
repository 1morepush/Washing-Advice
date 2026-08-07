/// An in-memory image store, for tests and the demo build.
///
/// It used to hand back `data:` URIs, which read pleasantly — the URI *is* the
/// image, so nothing has to look anything up. The shared contract suite showed
/// why that was wrong: `read` decoded the URI rather than consulting the map,
/// so **deleting an image had no observable effect**. Every other
/// implementation forgets a deleted image; this one kept answering with it, and
/// the map it maintained was never actually read.
///
/// A test double that behaves differently from the thing it stands in for is
/// worse than no double at all, so this now returns a reference like the
/// others. As a side effect the URIs stopped being base64 blobs the length of
/// the image, which were being written into wardrobe rows in every test.
library;

import 'dart:typed_data';

import 'image_store.dart';

/// The scheme this store issues and answers to.
const String memoryImageScheme = 'wa-memory';

class MemoryImageStore implements ImageStore {
  final Map<String, Uint8List> _bytes = {};

  /// How many images are held, for tests that assert nothing leaked.
  int get length => _bytes.length;

  @override
  Future<String> save(Uint8List bytes, {required String name}) async {
    // Keyed by name so a regenerated cutout replaces its predecessor rather
    // than accumulating, matching the other two stores.
    _bytes[name] = bytes;
    return '$memoryImageScheme:$name';
  }

  @override
  Future<Uint8List?> read(String uri) async {
    final name = _nameFrom(uri);
    return name == null ? null : _bytes[name];
  }

  @override
  Future<void> delete(String uri) async {
    final name = _nameFrom(uri);
    if (name != null) _bytes.remove(name);
  }

  String? _nameFrom(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !parsed.isScheme(memoryImageScheme)) return null;
    final name = parsed.path;
    return name.isEmpty ? null : name;
  }
}
