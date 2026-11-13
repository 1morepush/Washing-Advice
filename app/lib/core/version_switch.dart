/// Moving between the versions the web site keeps published.
///
/// The browser's half lives in `version_switch_web.dart`; everywhere else the
/// stand-in says there is nothing to move to, the same split as
/// `app_updater.dart`.
library;

export 'version_switch_base.dart';
export 'version_switch_stub.dart'
    if (dart.library.js_interop) 'version_switch_web.dart';
