/// The HTML shell the installed app actually launches into.
///
/// `web/index.html` carries three colours that have to agree with `AppTheme`
/// and cannot be derived from it: the two `theme-color` meta tags and the
/// stylesheet that paints the page before Flutter's first frame. They are the
/// first thing anyone sees when they tap the home screen icon, and being
/// wrong there looks exactly like the app being broken — which is what a
/// white strip above a dark app was.
///
/// Nothing in the build checks them, so this does. Reading the file rather
/// than a copy of the values is the point: a test that restated them would
/// drift alongside the thing it was meant to pin.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/core/theme.dart';

String _hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

void main() {
  final html = File('web/index.html').readAsStringSync();

  final light = _hex(AppTheme.light().colorScheme.surface.toARGB32());
  final dark = _hex(AppTheme.dark().colorScheme.surface.toARGB32());

  test('the browser chrome is told each theme\'s real surface colour', () {
    expect(
      html,
      contains(
        '<meta name="theme-color" media="(prefers-color-scheme: light)" '
        'content="$light">',
      ),
    );
    expect(
      html,
      contains(
        '<meta name="theme-color" media="(prefers-color-scheme: dark)" '
        'content="$dark">',
      ),
    );
  });

  test('the page is painted the same colour before Flutter starts', () {
    // Otherwise the app opens on a white flash in the dark theme, which is
    // the status bar problem again a few hundred milliseconds earlier.
    expect(html, contains('background-color: $light;'));
    expect(html, contains('background-color: $dark;'));
  });

  test('iOS is asked for a status bar that is never the wrong colour', () {
    // `default` is a white strip with dark text, which is what sat above the
    // dark theme and read as a fault. iOS has no theme-following option, so
    // `black` is the choice that is legible either way. See the reasoning in
    // the file itself.
    expect(
      html,
      contains(
        '<meta name="apple-mobile-web-app-status-bar-style" content="black">',
      ),
    );

    // Safari ignores the style above without this, and Flutter's own template
    // only emits the unprefixed spelling.
    expect(
      html,
      contains('<meta name="apple-mobile-web-app-capable" content="yes">'),
    );
  });
}
