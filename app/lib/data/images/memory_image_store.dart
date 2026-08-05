/// An in-memory image store.
///
/// Used on the web, where there is no filesystem, and by tests and the demo
/// build. Hands back `data:` URIs so an `Image.memory` is not needed anywhere
/// — the same widget renders a file path and a data URI alike.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'image_store.dart';

class MemoryImageStore implements ImageStore {
  final Map<String, Uint8List> _bytes = {};

  @override
  Future<String> save(Uint8List bytes, {required String name}) async {
    // Keyed by name so a regenerated cutout replaces its predecessor rather
    // than accumulating, matching the file store's behaviour.
    _bytes[name] = bytes;
    return 'data:image/png;name=$name;base64,${base64Encode(bytes)}';
  }

  @override
  Future<Uint8List?> read(String uri) async {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !parsed.isScheme('data')) return null;

    final comma = uri.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(uri.substring(comma + 1));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> delete(String uri) async {
    final name = Uri.tryParse(uri)?.queryParameters['name'];
    if (name != null) _bytes.remove(name);
  }
}
