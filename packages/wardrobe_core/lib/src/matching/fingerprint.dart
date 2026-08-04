/// The comparable signature of a garment.
///
/// A [GarmentFingerprint] is what a scan produces and what the matcher
/// compares. Keeping it separate from [WardrobeItem] means a freshly scanned
/// photo — which has no id, no history and no care profile — can be matched
/// against the wardrobe using exactly the same code path.
library;

import '../wardrobe/model/fabric.dart';
import '../wardrobe/model/item_attributes.dart';
import '../wardrobe/model/item_color.dart';
import '../wardrobe/model/wardrobe_item.dart';

/// A vector representation of an image.
///
/// Nothing in this milestone produces one — the type exists so that when a
/// visual model is added, the matcher, the storage schema and the wardrobe item
/// do not have to change shape around it. See `Feature.embeddingMatching`.
final class Embedding {
  const Embedding(this.values, {this.model = 'unknown'});

  /// The vector itself.
  final List<double> values;

  /// Which model produced it. Embeddings from different models are not
  /// comparable, so this must be checked before computing any distance.
  final String model;

  int get dimensions => values.length;

  /// Cosine similarity in `-1..1`, or null when the two are not comparable.
  static double? cosineSimilarity(Embedding a, Embedding b) {
    if (a.model != b.model || a.dimensions != b.dimensions) return null;
    if (a.dimensions == 0) return null;

    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.dimensions; i++) {
      dot += a.values[i] * b.values[i];
      normA += a.values[i] * a.values[i];
      normB += b.values[i] * b.values[i];
    }
    if (normA == 0 || normB == 0) return null;
    return dot / (_sqrt(normA) * _sqrt(normB));
  }

  static double _sqrt(double value) => value <= 0 ? 0 : _newtonSqrt(value);

  /// Avoids importing `dart:math` for a single call in a file that is
  /// otherwise pure data.
  static double _newtonSqrt(double value) {
    var guess = value;
    for (var i = 0; i < 24; i++) {
      guess = 0.5 * (guess + value / guess);
    }
    return guess;
  }

  Map<String, Object?> toJson() => {'model': model, 'values': values};

  static Embedding fromJson(Map<String, Object?> json) => Embedding(
        [
          for (final v in json['values']! as List<Object?>)
            (v! as num).toDouble(),
        ],
        model: json['model'] as String? ?? 'unknown',
      );

  @override
  String toString() => 'Embedding($model, ${dimensions}d)';
}

/// The comparable signature of one garment.
final class GarmentFingerprint {
  const GarmentFingerprint({
    required this.type,
    required this.colors,
    required this.composition,
    this.brand,
    this.pattern,
    this.sizeLabel,
    this.distinguishingText,
    this.embedding,
  });

  /// Builds a fingerprint from an item already in the wardrobe.
  factory GarmentFingerprint.of(WardrobeItem item) => GarmentFingerprint(
        type: item.type.value,
        colors: item.colors.value,
        composition: item.composition.value,
        brand: item.brand?.value,
        pattern: item.pattern?.value,
        sizeLabel: item.sizeLabel,
        distinguishingText: item.distinguishingText,
      );

  final ItemType type;
  final ColorPalette colors;
  final FabricComposition composition;
  final String? brand;
  final Pattern? pattern;
  final String? sizeLabel;

  /// Text visible on the garment — a slogan, a team name, a graphic caption.
  ///
  /// Unusually discriminating when present: two black t-shirts are hard to tell
  /// apart until one of them says "Nirvana".
  final String? distinguishingText;

  /// A visual embedding, when one is available.
  final Embedding? embedding;

  @override
  String toString() => 'GarmentFingerprint(${type.label}, '
      '${colors.dominant?.name ?? colors.dominant}, ${brand ?? "no brand"})';
}
