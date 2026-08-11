/// Whether two colours look right together.
///
/// This is the one genuinely subjective judgement in the core, so it is
/// isolated in a single small file with an explicit model behind it rather
/// than scattered through the outfit builder as tuned constants.
///
/// ## The wheel this uses is not the one from school
///
/// Hue here is CIELAB h°, and CIELAB is built on the *opponent* axes of human
/// vision: `a` runs red to green, `b` runs blue to yellow. So the colours that
/// come out opposite are the optical complements — red against cyan, yellow
/// against blue — not the pigment-mixing complements of the red-yellow-blue
/// wheel taught in art classes. Measured from real swatches, red sits at 34°
/// and mid-green at 140°: barely more than a right angle apart, not opposite.
/// Red and green being a *difficult* pairing rather than a natural one is,
/// famously, how they behave on actual clothes.
///
/// The bands below were therefore set from measured garment colours rather
/// than from wheel intuition, and the test file pins them against a table of
/// named swatches so that recalibrating means looking at real colours again.
///
/// ## The model
///
/// * A **neutral** goes with anything. Most wardrobes are mostly neutral, so
///   this case dominates in practice and must be the one that behaves best.
/// * Colours **close in hue** are safe, whether that reads as one shade or as
///   neighbours.
/// * Colours **opposite in hue** are deliberate and read as a choice.
/// * The **middle** — far enough apart to look unrelated, near enough to look
///   accidental — is the clash.
///
/// Two caveats stated once rather than implied throughout. Hue angle is
/// meaningless near the neutral axis, so chroma is always checked first. And
/// this scores *colour only*: it has no opinion on pattern, texture or
/// proportion, which is why a suggestion is a starting point rather than a
/// verdict, and why the builder always shows its reasoning.
library;

import '../wardrobe/model/item_color.dart';

/// Below this the colours are near enough to read as one.
///
/// Measured: brick red and burgundy are 12° apart, tan and rust 16°, and a
/// mid red and a mid orange 25° — all of which people describe as shades of
/// the same thing.
const double _sameHue = 30;

/// Below this they are neighbours: red to yellow is 58°, orange to yellow 34°.
const double _neighboring = 75;

/// At or above this they read as opposites. Blue against yellow measures 169°
/// and red against teal 149°, which are the two classic pairings that work.
const double _opposite = 145;

/// How well two colours sit together, `0..1`.
///
/// Symmetric, and never returns 0 — a clash is a weak suggestion, not an
/// impossibility, and a hard zero would let one questionable pairing veto an
/// otherwise good outfit.
double harmonyBetween(ItemColor x, ItemColor y) {
  if (x.isNeutral && y.isNeutral) return _neutralPair(x, y);
  if (x.isNeutral || y.isNeutral) return 0.85;

  final difference = hueDifference(x.hue, y.hue);
  if (difference < _sameHue) return 0.9;
  if (difference < _neighboring) return 0.8;
  if (difference >= _opposite) return 0.8;
  return 0.5;
}

/// The shorter way round the wheel between two hue angles, `0..180`.
double hueDifference(double x, double y) {
  final raw = (x - y).abs() % 360;
  return raw > 180 ? 360 - raw : raw;
}

/// Two neutrals, judged on lightness contrast instead of hue.
///
/// Black with cream is a decision; black with charcoal reads as an accident of
/// laundry rather than an outfit. So neutrals score well when they are clearly
/// different or clearly the same, and least well in the narrow band between.
double _neutralPair(ItemColor x, ItemColor y) {
  final contrast = (x.lightness - y.lightness).abs();
  if (contrast >= 30) return 1;
  if (contrast <= 8) return 0.9;
  return 0.7;
}

/// Harmony across a whole outfit, `0..1`.
///
/// The *lowest* pairwise score, not the average. One jarring pair spoils an
/// outfit no matter how well the other items agree, and averaging would let
/// three safe neutrals bury it.
double harmonyOf(List<ItemColor> colors) {
  if (colors.length < 2) return 1;

  var worst = 1.0;
  for (var i = 0; i < colors.length; i++) {
    for (var j = i + 1; j < colors.length; j++) {
      final score = harmonyBetween(colors[i], colors[j]);
      if (score < worst) worst = score;
    }
  }
  return worst;
}

/// A short phrase explaining how two colours relate, for the reasons shown
/// beside a suggestion.
///
/// Returns null when there is nothing worth saying — a neutral pairing with
/// something is unremarkable, and "these both go with everything" is noise.
String? describePairing(ItemColor x, ItemColor y) {
  if (x.isNeutral && y.isNeutral) {
    return (x.lightness - y.lightness).abs() >= 30
        ? 'Strong light–dark contrast'
        : null;
  }
  if (x.isNeutral || y.isNeutral) return null;

  final difference = hueDifference(x.hue, y.hue);
  if (difference < _sameHue) return 'Shades of one color';
  if (difference < _neighboring) return 'Neighboring colors';
  if (difference >= _opposite) {
    return 'Opposite colors, which set each other off';
  }
  return 'An awkward gap between these colors';
}
