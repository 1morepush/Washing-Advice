/// Forcing a fresh copy of the app past a stale service worker and cache.
///
/// A PWA saved to an iOS home screen does not reliably notice a new
/// deployment on its own — Safari's background service-worker update checks
/// are known to be unreliable, and the fix people reach for is deleting the
/// icon, reopening in Safari, and saving it again. This gives the same result
/// — a genuinely fresh load — from inside the app itself.
///
/// The real work only exists on web: [dart.library.js_interop] is only
/// available there, so a non-web build (should one ever exist) links against
/// the no-op stub instead.
library;

export 'app_updater_stub.dart'
    if (dart.library.js_interop) 'app_updater_web.dart';
