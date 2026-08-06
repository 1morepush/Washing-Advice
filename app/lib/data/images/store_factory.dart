/// Choosing an image store for the platform.
///
/// A filesystem is the right place for files, so native platforms write files.
/// The web has none, and used to keep bytes in memory — which meant a browser
/// build lost every picture on reload. It now uses a small database of its
/// own, which Drift persists through IndexedDB or OPFS: the same storage the
/// wardrobe already relies on there, rather than a new mechanism to get wrong.
///
/// `MemoryImageStore` is still used by tests and by the demo, where losing
/// everything on reload is the desired behaviour rather than a limitation.
library;

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'drift_image_store.dart';
import 'file_image_store.dart';
import 'image_database.dart';
import 'image_store.dart';

Future<ImageStore> openImageStore() async {
  if (!kIsWeb) return FileImageStore.open();

  // A separate database file from the wardrobe's, so the wardrobe stays small
  // and nothing that reads an item ever opens this.
  return DriftImageStore(
    ImageDatabase(driftDatabase(name: 'washing_advice_images')),
  );
}
