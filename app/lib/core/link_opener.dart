/// Opening a link outside the app.
///
/// Sell sends a person to pages they have to look at for themselves: the
/// listings a suggested price was built on, and the Depop, eBay and Google
/// searches beside it. A price is only as good as the look taken at what it
/// rests on, which is why each of those is a link and not a number.
///
/// **Why a port.** Launching a page is a platform call, and a widget test that
/// tapped a link would try to make it. Behind [LinkOpener], a test records
/// which link was opened (`RecordingLinkOpener` in the tests) and launches
/// nothing, and the screen cannot tell the difference.
///
/// **Why external.** [LaunchMode.externalApplication] gives the address to the
/// system instead of showing it in a view inside this app. The system opens it
/// in whatever handles that address, so on an iPhone a depop.com link can open
/// in the Depop app, where the person is already signed in, rather than in a
/// browser tab they have to sign in to again. Whether it does is the phone's
/// decision, and nothing here depends on it: with no such app the link opens in
/// the browser.
library;

import 'package:url_launcher/url_launcher.dart';

/// Opens an address outside the app.
abstract interface class LinkOpener {
  /// Opens [uri], and says whether anything opened.
  ///
  /// False when nothing on the device could. Never an exception: a link that
  /// would not open is something to tell the person about, in the words of the
  /// screen they tapped it on, and not a failure for the screen to catch.
  Future<bool> open(Uri uri);
}

/// Opens links with the platform's own launcher.
final class UrlLauncherLinkOpener implements LinkOpener {
  const UrlLauncherLinkOpener();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      // A platform channel that errors, or a device with nothing to open the
      // address with. Both come to the same thing for the person.
      return false;
    }
  }
}
