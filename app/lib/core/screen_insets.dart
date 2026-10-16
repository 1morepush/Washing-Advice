/// The edges of the screen that belong to the phone.
///
/// See `screen_insets_policy.dart` for what they are and why the web needs
/// them worked out; this is only the seam, by the same split as
/// `browser_chrome.dart` — the real reader on the web, nothing elsewhere.
library;

export 'screen_insets_policy.dart';
export 'screen_insets_stub.dart'
    if (dart.library.js_interop) 'screen_insets_web.dart';
