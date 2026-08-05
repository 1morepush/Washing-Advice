/// Choosing an image store for the platform.
///
/// The web has no filesystem, so it keeps bytes in memory — which also means a
/// browser build loses its pictures on reload. That is an acceptable trade for
/// what the web build is for (trying the app, and taking screenshots) and is
/// stated in the README rather than left to be discovered.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'file_image_store.dart';
import 'image_store.dart';
import 'memory_image_store.dart';

Future<ImageStore> openImageStore() async =>
    kIsWeb ? MemoryImageStore() : await FileImageStore.open();
