/// How much of the screen's edge belongs to the phone, not to the app.
///
/// A phone with rounded corners and a home indicator draws over the last few
/// millimetres of its own screen. Content that reaches that far is clipped by
/// the corners and sat on by the indicator: a bottom bar whose first and last
/// labels fall in those corners reads as slightly cut off, and a screenshot of
/// it looks fine, because a screenshot is a rectangle and the glass is not.
///
/// Native builds are told these amounts by the platform. A web page is told
/// by CSS, as `env(safe-area-inset-*)`, and Flutter's web engine does not
/// forward it — so for the installed web app this is worked out on this side.
/// Kept apart from the part that reads the page so the rule can be tested
/// without one.
library;

import 'dart:math' as math;

/// Logical pixels reserved along each edge.
class ScreenInsets {
  const ScreenInsets({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  static const zero = ScreenInsets();

  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  bool operator ==(Object other) =>
      other is ScreenInsets &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'ScreenInsets($left, $top, $right, $bottom)';
}

/// The height of the home indicator's zone on every iPhone that has one, held
/// upright. Apple has used 34 points since the iPhone X.
const homeIndicatorHeight = 34.0;

/// The insets to honour, given what the page itself measured.
///
/// [measured] is `env(safe-area-inset-*)` as the browser reports it, and is
/// trusted whenever it says anything: a page that has asked for the full
/// screen is told the truth. When it says nothing about the bottom — which is
/// what an installed web app on an iPhone reports even while the home
/// indicator sits over its last row — the answer is inferred, and only where
/// the inference is safe: an installed app, on an iPhone, held upright, on a
/// screen long enough to be one of the phones that has the indicator at all.
/// The older iPhones with a home button are all 16:9 and fail the last test, so
/// they are not given a gap they have no use for.
ScreenInsets resolveScreenInsets({
  required ScreenInsets measured,
  required bool installed,
  required bool onIphone,
  required bool portrait,
  required double screenWidth,
  required double screenHeight,
}) {
  if (measured.bottom > 0) return measured;

  final longSide = math.max(screenWidth, screenHeight);
  final shortSide = math.min(screenWidth, screenHeight);
  final hasHomeIndicator = shortSide > 0 && longSide / shortSide > 2.0;

  if (installed && onIphone && portrait && hasHomeIndicator) {
    return ScreenInsets(
      left: measured.left,
      top: measured.top,
      right: measured.right,
      bottom: homeIndicatorHeight,
    );
  }
  return measured;
}
