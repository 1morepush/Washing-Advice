/// The contract the AI layer must satisfy.
///
/// The core defines *what* a scan must produce; it deliberately contains no
/// implementation. Gemini, an on-device pipeline, a fake for tests, or a future
/// model all sit behind [VisionPort], so nothing in the domain knows or cares
/// which is in use.
///
/// Every perceived field arrives wrapped in [Confident], because that is the
/// honest shape of a model's output and the app's prompting behaviour depends
/// on it.
library;

import '../care/rules/care_rule.dart';
import '../shared/confidence.dart';
import '../wardrobe/model/fabric.dart';
import '../wardrobe/model/item_attributes.dart';
import '../wardrobe/model/item_color.dart';

/// Bytes plus enough context for a provider to work with.
final class ScanImage {
  const ScanImage({
    required this.bytes,
    this.mimeType = 'image/jpeg',
    this.width,
    this.height,
  });

  final List<int> bytes;
  final String mimeType;
  final int? width;
  final int? height;

  int get sizeBytes => bytes.length;

  @override
  String toString() => 'ScanImage($mimeType, $sizeBytes bytes)';
}

/// What a single-garment scan produces.
final class GarmentScanResult {
  const GarmentScanResult({
    required this.type,
    required this.colors,
    this.composition,
    this.brand,
    this.pattern,
    this.sleeveLength,
    this.fit,
    this.styleCut,
    this.seasons = const {},
    this.suggestedName,
    this.distinguishingText,
    this.rawModelResponse,
  });

  final Confident<ItemType> type;
  final Confident<ColorPalette> colors;
  final Confident<FabricComposition>? composition;
  final Confident<String>? brand;
  final Confident<Pattern>? pattern;
  final Confident<SleeveLength>? sleeveLength;
  final Confident<Fit>? fit;
  final Confident<StyleCut>? styleCut;
  final Set<Season> seasons;

  /// A name to prefill, e.g. `'Grey Nike hoodie'`.
  final String? suggestedName;

  /// Any text visible on the garment, which strongly aids re-identification.
  final String? distinguishingText;

  /// The provider's unparsed response, kept for debugging prompt changes.
  final String? rawModelResponse;

  @override
  String toString() => 'GarmentScanResult(${type.value.label})';
}

/// What a care-label scan produces.
///
/// The instructions come back as a [CareConstraint] rather than a complete
/// [CareInstructions] on purpose: a label states only some things, and a
/// creased or faded one states even fewer. Null means "not stated", which the
/// resolver treats very differently from a stated prohibition.
final class CareTagScanResult {
  const CareTagScanResult({
    required this.instructions,
    required this.confidence,
    this.composition,
    this.symbolsFound = const [],
    this.unreadableSymbolCount = 0,
    this.rawText,
    this.rawModelResponse,
  });

  /// The care requirements legible on the label.
  final CareConstraint instructions;

  /// Overall confidence in the reading.
  final double confidence;

  /// Fibre composition printed on the label, when present.
  final Confident<FabricComposition>? composition;

  /// Identifiers of the symbols recognised, for showing the user what was read.
  final List<String> symbolsFound;

  /// How many symbols were visible but could not be interpreted.
  ///
  /// Drives an honest "part of this label could not be read" prompt rather than
  /// silently returning an incomplete answer.
  final int unreadableSymbolCount;

  /// The raw OCR text.
  final String? rawText;

  final String? rawModelResponse;

  bool get isComplete => unreadableSymbolCount == 0;

  @override
  String toString() => 'CareTagScanResult(${symbolsFound.length} symbols, '
      '${(confidence * 100).round()}%)';
}

/// One garment located within a photo of a pile.
final class DetectedItem {
  const DetectedItem({
    required this.scan,
    required this.boundingBox,
    required this.detectionConfidence,
  });

  /// The attributes read for this garment.
  final GarmentScanResult scan;

  /// Where it sits in the image.
  final BoundingBox boundingBox;

  /// How sure the model is that this is a distinct garment, as opposed to how
  /// sure it is about the garment's attributes.
  final double detectionConfidence;

  @override
  String toString() => 'DetectedItem(${scan.type.value.label})';
}

/// A rectangle in normalised image coordinates, `0..1` from the top left.
///
/// Normalised so the value survives the image being resized or re-encoded
/// between the device and the provider.
final class BoundingBox {
  const BoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;

  double get bottom => top + height;

  double get area => width * height;

  /// Fraction of the smaller box that the two share, used to drop duplicate
  /// detections of one garment.
  double overlapWith(BoundingBox other) {
    final overlapWidth = (right < other.right ? right : other.right) -
        (left > other.left ? left : other.left);
    final overlapHeight = (bottom < other.bottom ? bottom : other.bottom) -
        (top > other.top ? top : other.top);
    if (overlapWidth <= 0 || overlapHeight <= 0) return 0;

    final intersection = overlapWidth * overlapHeight;
    final smaller = area < other.area ? area : other.area;
    return smaller == 0 ? 0 : intersection / smaller;
  }

  Map<String, Object?> toJson() => {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };

  static BoundingBox fromJson(Map<String, Object?> json) => BoundingBox(
        left: (json['left']! as num).toDouble(),
        top: (json['top']! as num).toDouble(),
        width: (json['width']! as num).toDouble(),
        height: (json['height']! as num).toDouble(),
      );

  @override
  String toString() => 'BoundingBox($left, $top, $width x $height)';
}

/// What scanning a whole pile produces.
final class PileScanResult {
  const PileScanResult({
    required this.items,
    this.partiallyObscuredCount = 0,
    this.rawModelResponse,
  });

  final List<DetectedItem> items;

  /// Garments visible but too obscured to identify.
  ///
  /// Reported rather than hidden, because "I found 6 items, and 2 more are
  /// buried" lets the user reshuffle the pile and rescan.
  final int partiallyObscuredCount;

  final String? rawModelResponse;

  int get count => items.length;

  @override
  String toString() => 'PileScanResult($count items)';
}

/// The interface every vision provider implements.
abstract interface class VisionPort {
  /// Identifies a single garment from one or more photographs.
  Future<GarmentScanResult> scanGarment(List<ScanImage> images);

  /// Reads a care label.
  Future<CareTagScanResult> scanCareTag(ScanImage image);

  /// Finds and identifies every garment in a photo of a pile.
  Future<PileScanResult> scanPile(ScanImage image);
}

/// Remembers what has already been learned, so repeat scans are cheap.
///
/// The "AI memory" idea: a brand's care instructions, a previously read label,
/// a known composition. Looking these up before calling a model makes scanning
/// faster, cheaper and more consistent over time.
///
/// The interface lives here; the implementation belongs to the backend, which
/// is where the storage and the model calls are.
abstract interface class KnowledgeCache {
  /// A previously read label matching this signature, if any.
  Future<CareTagScanResult?> careForLabelSignature(String signature);

  /// Records a label reading against its signature.
  Future<void> rememberLabel(String signature, CareTagScanResult result);

  /// Typical composition for a brand and garment type, learned from past
  /// scans — a useful prior when a label is unreadable.
  Future<Confident<FabricComposition>?> compositionPriorFor({
    required String brand,
    required ItemType type,
  });
}
