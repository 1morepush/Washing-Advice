/// Whether one colour can be told from another, in numbers.
///
/// Shared because "does this stand out against that" is asked of a theme, of a
/// thumbnail's backdrop and of a card's edge, and three tests each carrying
/// their own formula would be three chances to get the 0.05 wrong.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

/// The WCAG contrast ratio between two opaque colours: 1 for identical, 21 for
/// black on white.
///
/// The measure that fits the question being asked here, which is whether a
/// shape can be seen against what is behind it. Real screens and real eyes add
/// their own opinions, and the ratios asserted against this are chosen with that
/// in mind: they pin "clearly there" and "clearly not a panel", not a threshold
/// anyone has measured on a phone.
double contrastBetween(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
