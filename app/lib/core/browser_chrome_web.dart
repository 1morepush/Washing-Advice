/// The real implementation: say which choice is in force on the page itself,
/// and recolour the two `theme-color` tags to match.
///
/// Everything here is named in `web/index.html`, which does the same job once,
/// early, from local storage: the `data-appearance` attribute its stylesheet
/// keys on, and the `media` queries that tell its two tags apart.
/// `test/web_shell_test.dart` pins the page's side of that. A name that drifted
/// on this side would find nothing to recolour and say nothing, so changing one
/// means changing both.
///
/// Best-effort, like `forceAppUpdate`: the choice is already saved by the time
/// this runs, and a browser that will not let the page touch its own head is
/// not a reason to fail it.
library;

import 'dart:ui' show Color;

import 'package:web/web.dart' as web;

import 'theme.dart';

void paintBrowserChrome(Appearance appearance) {
  try {
    final root = web.document.documentElement;
    if (appearance == Appearance.system) {
      // Back to the stylesheet's own media query, which asks the phone.
      root?.removeAttribute('data-appearance');
    } else {
      root?.setAttribute('data-appearance', appearance.name);
    }

    final surfaces = appearance.surfaces;
    _setThemeColor('light', surfaces.whenLight);
    _setThemeColor('dark', surfaces.whenDark);
  } catch (_) {
    // See the library comment.
  }
}

/// Sets the tag the browser reads when the phone is in [scheme] mode.
void _setThemeColor(String scheme, Color color) {
  final rgb = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  web.document
      .querySelector(
        'meta[name="theme-color"][media="(prefers-color-scheme: $scheme)"]',
      )
      ?.setAttribute('content', '#$rgb');
}
