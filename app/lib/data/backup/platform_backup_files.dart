/// The real [BackupFiles] for whichever platform this is built for.
///
/// Chosen at compile time by the same conditional export the rest of the app
/// uses for browser-only code (`browser_chrome.dart`, `app_updater.dart`): the
/// browser build never sees `dart:io` or the share plugin, and the phone build
/// never sees `package:web`.
library;

export 'platform_backup_files_native.dart'
    if (dart.library.js_interop) 'platform_backup_files_web.dart';
