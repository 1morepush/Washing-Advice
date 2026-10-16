# Bundled fonts

**Nunito**, weights 400, 600, 700 and 800 (Regular, SemiBold, Bold, ExtraBold).
Copyright 2014 The Nunito Project Authors (https://github.com/googlefonts/nunito).
Licensed under the [SIL Open Font License, version 1.1](https://scripts.sil.org/OFL);
the licence text is `Nunito-OFL.txt` and is registered with Flutter's
`LicenseRegistry` (`lib/core/licences.dart`), so it appears on the licence page.

The static TTFs come from the `@expo-google-fonts/nunito` npm package, which
repackages the Google Fonts release unmodified.

## Why it is bundled, and everywhere

The "Rinse" look is set in Nunito, and the font ships inside the app on every
platform, so nothing is downloaded at run time. That also settles the web
build, which has no system fonts: CanvasKit renders text itself and, with no
font asset, fetches Roboto from Google's CDN on first paint. That made the
first paint depend on a network the app otherwise does not need, and in a
sandboxed CI container the request simply fails — screenshots with every icon
and not one word. (Web used to bundle Liberation Sans for that reason; Nunito
replaces it.) It is the same goal as the `--no-web-resources-cdn` build flag.

Characters Nunito lacks (emoji, some symbols) fall back to the platform font.
