/// Licence texts for what the app bundles, for Flutter's licence page.
///
/// Flutter lists the licences of its packages by itself; a font that is only an
/// asset is not one, so its licence is registered here. The SIL Open Font
/// License asks that the notice travel with the font.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registers the bundled font's licence. Each call adds another registration,
/// so the licence page would list the font once per call: `main` calls it
/// exactly once, before `runApp`.
void registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/Nunito-OFL.txt');
    yield LicenseEntryWithLineBreaks(['Nunito (font)'], text);
  });
}
