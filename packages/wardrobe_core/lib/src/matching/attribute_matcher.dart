/// Attribute-based item matching.
///
/// Scores a scanned fingerprint against wardrobe items using structured
/// attributes: garment type, perceptual colour distance, brand, fibre
/// composition and size. Entirely offline and deterministic.
library;

import '../wardrobe/model/fabric.dart';
import '../wardrobe/model/item_color.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'fingerprint.dart';
import 'matcher.dart';

/// Weights for each comparable signal.
///
/// Colour and type dominate because they are the most reliably perceived and
/// the most discriminating. Brand is a strong positive when both sides know it
/// but must not punish the common case of an unreadable label, so a missing
/// brand contributes a neutral score rather than zero.
final class MatchWeights {
  const MatchWeights({
    this.type = 0.30,
    this.color = 0.35,
    this.brand = 0.15,
    this.composition = 0.12,
    this.size = 0.08,
  });

  final double type;
  final double color;
  final double brand;
  final double composition;
  final double size;

  double get total => type + color + brand + composition + size;
}

/// Matches items on their structured attributes.
final class AttributeMatcher implements ItemMatcher {
  const AttributeMatcher({
    this.weights = const MatchWeights(),
    this.weight = 1.0,
  });

  final MatchWeights weights;

  @override
  final double weight;

  @override
  String get name => 'attributes';

  @override
  List<MatchCandidate> rank(
    GarmentFingerprint probe,
    Iterable<WardrobeItem> candidates,
  ) {
    final scored = <MatchCandidate>[];

    for (final item in candidates) {
      final other = GarmentFingerprint.of(item);

      // A different garment type is a hard disqualification rather than a
      // penalty: a hoodie is never a mis-scan of a pair of jeans, and letting a
      // strong colour match override that produces nonsense.
      if (probe.type != other.type) continue;

      final contributions = <String, double>{
        'type': 1.0,
        'color': _colorScore(probe.colors, other.colors),
        'brand': _brandScore(probe.brand, other.brand),
        'composition': _compositionScore(probe.composition, other.composition),
        'size': _sizeScore(probe.sizeLabel, other.sizeLabel),
      };

      var total = contributions['type']! * weights.type +
          contributions['color']! * weights.color +
          contributions['brand']! * weights.brand +
          contributions['composition']! * weights.composition +
          contributions['size']! * weights.size;
      total /= weights.total;

      // Visible text is rare but nearly conclusive, so it adjusts the result
      // after normalisation rather than competing as one weight among many.
      final textScore = _textScore(
        probe.distinguishingText,
        other.distinguishingText,
      );
      if (textScore != null) {
        contributions['text'] = textScore;
        total = total * 0.7 + textScore * 0.3;
      }

      scored.add(
        MatchCandidate(
          itemId: item.id,
          score: total.clamp(0.0, 1.0),
          contributions: contributions,
        ),
      );
    }

    scored.sort((x, y) => y.score.compareTo(x.score));
    return scored;
  }

  /// Perceptual colour similarity, via CIEDE2000 on the dominant colours.
  ///
  /// A ΔE of 0 is identical and anything past about 25 is plainly a different
  /// colour, so the score falls linearly to zero across that range.
  double _colorScore(ColorPalette a, ColorPalette b) {
    final first = a.dominant;
    final second = b.dominant;
    if (first == null || second == null) return 0.5;

    final delta = ItemColor.difference(first, second);
    const noticeable = 25.0;
    final base = (1.0 - delta / noticeable).clamp(0.0, 1.0);

    // Agreeing on the overall colour family is worth a little on its own —
    // it keeps two slightly different navies scoring above a navy and a beige.
    final sameClass = a.colorClass == b.colorClass;
    return sameClass ? (base * 0.85 + 0.15) : base * 0.85;
  }

  /// Brand agreement. Neutral when either side is unknown, since an unreadable
  /// label is not evidence of a different garment.
  double _brandScore(String? a, String? b) {
    if (a == null || b == null) return 0.5;
    return _normalise(a) == _normalise(b) ? 1.0 : 0.0;
  }

  /// Composition overlap, as the shared percentage across fibres.
  ///
  /// Two garments both listing 80% cotton / 20% polyester share 100%; cotton
  /// against pure polyester shares nothing.
  double _compositionScore(FabricComposition a, FabricComposition b) {
    if (a.isEmpty || b.isEmpty) return 0.5;

    var shared = 0;
    for (final fiber in {...a.fibers, ...b.fibers}) {
      final x = a.percentOf(fiber);
      final y = b.percentOf(fiber);
      shared += x < y ? x : y;
    }
    return (shared / 100.0).clamp(0.0, 1.0);
  }

  double _sizeScore(String? a, String? b) {
    if (a == null || b == null) return 0.5;
    return _normalise(a) == _normalise(b) ? 1.0 : 0.0;
  }

  /// Similarity of any visible text, or null when neither has any.
  double? _textScore(String? a, String? b) {
    if (a == null || b == null) return null;
    final left = _normalise(a);
    final right = _normalise(b);
    if (left.isEmpty || right.isEmpty) return null;
    if (left == right) return 1.0;
    if (left.contains(right) || right.contains(left)) return 0.8;

    final leftWords = left.split(' ').toSet();
    final rightWords = right.split(' ').toSet();
    final overlap = leftWords.intersection(rightWords).length;
    final union = leftWords.union(rightWords).length;
    return union == 0 ? 0.0 : overlap / union;
  }

  String _normalise(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();
}
