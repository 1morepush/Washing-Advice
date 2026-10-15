/// The HTML shell the installed app actually launches into.
///
/// `web/index.html` carries colours that have to agree with `AppTheme` and
/// cannot be derived from it: the two `theme-color` meta tags, the stylesheet
/// that paints the page before Flutter's first frame, and the small script that
/// swaps both for the look somebody chose in Settings. They are the first thing
/// anyone sees when they tap the home screen icon, and being wrong there looks
/// exactly like the app being broken — which is what a white strip above a dark
/// app was, and what a white flash before a black one would be.
///
/// Nothing in the build checks them, so this does. Reading the file rather
/// than a copy of the values is the point: a test that restated them would
/// drift alongside the thing it was meant to pin.
///
/// What this cannot do is run the script. It pins what the script reads and
/// what it writes; that it behaves was checked in a real browser, and a change
/// to its logic wants the same.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/core/theme.dart';

String _hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

void main() {
  final html = File('web/index.html').readAsStringSync();

  // The page with its runs of whitespace folded to one space, for the rules
  // and the script that are laid out over several lines.
  final flat = html.replaceAll(RegExp(r'\s+'), ' ');

  final light = _hex(AppTheme.light().colorScheme.surface.toARGB32());
  final dark = _hex(AppTheme.dark().colorScheme.surface.toARGB32());
  final amoled = _hex(AppTheme.amoled().colorScheme.surface.toARGB32());

  /// The three looks that name a surface. Match phone names none: it is the
  /// phone's to decide, which is the media query.
  final explicit = {
    Appearance.light: light,
    Appearance.dark: dark,
    Appearance.amoled: amoled,
  };

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

  group('a look chosen in Settings', () {
    test('paints its own surface before Flutter starts', () {
      // Otherwise AMOLED on a phone in light mode opens on a white flash and
      // then goes black, which is the dark-theme flash again with the colours
      // the other way round.
      for (final MapEntry(key: look, value: surface) in explicit.entries) {
        expect(
          flat,
          contains(
            'html[data-appearance="${look.name}"], '
            'html[data-appearance="${look.name}"] body { '
            'background-color: $surface; }',
          ),
          reason: look.name,
        );
      }
    });

    test('is applied by a script that knows the same looks and colours', () {
      for (final MapEntry(key: look, value: surface) in explicit.entries) {
        expect(flat, contains("${look.name}: '$surface'"), reason: look.name);
      }
    });

    test('leaves Match phone to the phone', () {
      // A surface for it in the script would pin the page to one colour scheme
      // for everybody who has not chosen, which is the bug the media queries
      // exist to prevent.
      expect(flat, isNot(contains("${Appearance.system.name}: '")));
      expect(
        flat,
        isNot(contains('data-appearance="${Appearance.system.name}"')),
      );
    });

    test('reads the key the settings store writes', () async {
      // Taken from the store itself, so a renamed key fails here and not on a
      // phone. The `flutter.` in front is the preferences plugin's own prefix
      // on the web, and the value arrives JSON-encoded, quotes and all, which
      // is what the script's `JSON.parse` is for.
      SharedPreferences.setMockInitialValues({});
      await SettingsStore(
        await SharedPreferences.getInstance(),
      ).setAppearance(Appearance.amoled);
      final key = (await SharedPreferences.getInstance()).getKeys().single;

      expect(html, contains("localStorage.getItem('flutter.$key')"));
      expect(html, contains('JSON.parse('));
    });

    test('recolours both of the theme-color tags', () {
      // Both, whatever the phone's own setting: a choice that only reached the
      // tag for the phone's current mode would be undone by the phone changing
      // its mind at sunset.
      expect(
        flat,
        contains("document.querySelectorAll('meta[name=\"theme-color\"]')"),
      );
    });
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
