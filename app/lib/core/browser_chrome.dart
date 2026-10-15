/// The colours a browser draws around the page, which Flutter cannot reach.
///
/// The address bar of a browser tab, and the status bar above an installed web
/// app, take their colour from `<meta name="theme-color">`, not from anything
/// painted on the canvas. `web/index.html` sets them before Flutter has started,
/// from the stored choice. This is for a choice made *during* a session, which
/// would otherwise leave a light bar over an app that has just gone black.
///
/// The real work only exists on web, by the same split as `app_updater.dart`:
/// anywhere else there is no page to colour, and a phone's status bar takes its
/// colour from the app bar, which Flutter already paints.
library;

export 'browser_chrome_stub.dart'
    if (dart.library.js_interop) 'browser_chrome_web.dart';
