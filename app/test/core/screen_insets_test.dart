/// Who owns the last few millimetres of the screen.
///
/// An installed web app on an iPhone is told nothing about the home indicator
/// or the rounded corners, so the bottom bar's end labels sat in them and read
/// as cut off — in the glass, not in a screenshot. These pin when the app
/// leaves room, and, as much, when it does not: a gap on a phone that has no
/// use for one is a bar floating off the bottom for nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/core/screen_insets_policy.dart';

ScreenInsets _resolve({
  ScreenInsets measured = ScreenInsets.zero,
  bool installed = true,
  bool onIphone = true,
  bool portrait = true,
  double width = 393,
  double height = 852,
}) => resolveScreenInsets(
  measured: measured,
  installed: installed,
  onIphone: onIphone,
  portrait: portrait,
  screenWidth: width,
  screenHeight: height,
);

void main() {
  test('an installed app on a modern iPhone, upright, leaves room for the '
      'home indicator', () {
    expect(_resolve().bottom, homeIndicatorHeight);
    expect(_resolve().bottom, 34);
  });

  test('what the page measured is believed whenever it says anything', () {
    const measured = ScreenInsets(bottom: 20, left: 5);
    expect(_resolve(measured: measured), measured);
    // Even where it disagrees with the guess, in either direction.
    expect(_resolve(measured: const ScreenInsets(bottom: 50)).bottom, 50);
    expect(_resolve(measured: const ScreenInsets(bottom: 1)).bottom, 1);
  });

  test('a measured side is kept when only the bottom has to be inferred', () {
    final resolved = _resolve(measured: const ScreenInsets(left: 3, top: 7));
    expect(resolved.left, 3);
    expect(resolved.top, 7);
    expect(resolved.bottom, 34);
  });

  test('an iPhone with a home button gets no gap it has no use for', () {
    // Every one of them is 16:9.
    expect(_resolve(width: 375, height: 667).bottom, 0);
    expect(_resolve(width: 414, height: 736).bottom, 0);
  });

  test('a browser tab is left alone: the browser draws its own chrome', () {
    expect(_resolve(installed: false).bottom, 0);
  });

  test('anything that is not an iPhone is left alone', () {
    expect(_resolve(onIphone: false).bottom, 0);
  });

  test(
    'sideways, the guess is not made (the bottom inset is different there)',
    () {
      expect(_resolve(portrait: false).bottom, 0);
    },
  );

  test('a screen of unknown size is not guessed at', () {
    expect(_resolve(width: 0, height: 0).bottom, 0);
  });

  test('every iPhone that has a home indicator is tall enough to be '
      'recognised', () {
    const sizes = {
      'X / 11 Pro': (375.0, 812.0),
      '11 / XR': (414.0, 896.0),
      '12 / 13 / 14': (390.0, 844.0),
      '12 mini / 13 mini': (360.0, 780.0),
      '14 Pro / 15 / 16': (393.0, 852.0),
      '14 Pro Max / 15 Plus': (430.0, 932.0),
      '16 Pro Max': (440.0, 956.0),
    };
    for (final entry in sizes.entries) {
      final (w, h) = entry.value;
      expect(
        _resolve(width: w, height: h).bottom,
        homeIndicatorHeight,
        reason: entry.key,
      );
    }
  });
}
