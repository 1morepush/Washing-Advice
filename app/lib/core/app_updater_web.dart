/// The real implementation: unregister every service worker this origin has
/// registered, empty every named cache, then reload.
///
/// Each step is best-effort — a registration or cache that fails to clear
/// should not stop the others, and should never stop the reload that follows,
/// since a reload is the one step that still helps even if the rest partly
/// failed.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

const canForceAppUpdate = true;

Future<void> forceAppUpdate() async {
  try {
    final registrations = await web.window.navigator.serviceWorker
        .getRegistrations()
        .toDart;
    for (final registration in registrations.toDart) {
      await registration.unregister().toDart;
    }
  } catch (_) {
    // Best-effort — an origin with nothing registered, or a browser that
    // refuses for its own reasons, should not block the reload below.
  }

  try {
    final cacheNames = await web.window.caches.keys().toDart;
    for (final name in cacheNames.toDart) {
      await web.window.caches.delete(name.toDart).toDart;
    }
  } catch (_) {
    // Same as above.
  }

  web.window.location.reload();
}
