/// Decoding the server's scan responses into core types.
///
/// Kept apart from the HTTP client so parsing can be tested against the shared
/// fixtures in `contracts/examples/` without a socket. Those same fixtures are
/// parsed by the Python tests, which is what stops the two sides of the wire
/// drifting apart.
///
/// Nothing here invents a value. A field the server did not send stays absent,
/// because absence is meaningful all the way down: an unstated care field is
/// filled from the rule table, whereas a stated one overrides it.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

/// Thrown when a response cannot be read as the contract describes.
///
/// Distinct from a transport failure: this one means the client and server
/// disagree about the shape of the world, which is a bug rather than a network
/// blip and must not be presented to the user as "try again".
class ScanContractError implements Exception {
  ScanContractError(this.message);

  final String message;

  @override
  String toString() => 'ScanContractError: $message';
}

/// How a result was arrived at.
///
/// Surfaced rather than logged: "answered from memory in 4 ms" is the visible
/// proof that the cost-ordered pipeline is doing its job, and during
/// development it is the difference between trusting the cache and hoping.
final class ScanDiagnostics {
  const ScanDiagnostics({
    this.stagesRun = const [],
    this.stageAnswered,
    this.servedFromCache = false,
    this.elapsedMs = 0,
  });

  final List<String> stagesRun;
  final String? stageAnswered;
  final bool servedFromCache;
  final int elapsedMs;

  static ScanDiagnostics fromJson(Map<String, Object?> json) => ScanDiagnostics(
    stagesRun: [
      for (final stage in (json['stagesRun'] as List<Object?>?) ?? const [])
        stage! as String,
    ],
    stageAnswered: json['stageAnswered'] as String?,
    servedFromCache: json['servedFromCache'] as bool? ?? false,
    elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
  );
}

/// A scan result together with how it was produced.
final class ScanEnvelope<T> {
  const ScanEnvelope({required this.result, required this.diagnostics});

  final T result;
  final ScanDiagnostics diagnostics;
}

// --- Decoders ---------------------------------------------------------------

GarmentScanResult garmentResultFromJson(Map<String, Object?> json) {
  T require<T>(String field) {
    final value = json[field];
    if (value is! T) {
      throw ScanContractError('garment scan is missing "$field"');
    }
    return value;
  }

  Confident<V>? optional<V extends Object>(
    String field,
    V Function(Object? raw) decode,
  ) {
    final raw = json[field];
    return raw == null
        ? null
        : Confident.fromJson(raw as Map<String, Object?>, decode);
  }

  return GarmentScanResult(
    type: Confident.fromJson(
      require<Map<String, Object?>>('type'),
      (raw) => ItemType.values.byName(raw! as String),
    ),
    // Colour is required by the core but optional on the wire, because a
    // provider can fail to read it. An empty palette is the honest stand-in and
    // classifies as darks, which is the safe pile to guess.
    colors:
        optional(
          'colors',
          (raw) => ColorPalette.fromJson(raw! as List<Object?>),
        ) ??
        Confident(
          ColorPalette.empty(),
          confidence: 0,
          source: Provenance.fallbackDefault,
        ),
    composition: optional(
      'composition',
      (raw) => FabricComposition.fromJson(raw! as Map<String, Object?>),
    ),
    brand: optional('brand', (raw) => raw! as String),
    pattern: optional(
      'pattern',
      (raw) => Pattern.values.byName(raw! as String),
    ),
    sleeveLength: optional(
      'sleeveLength',
      (raw) => SleeveLength.values.byName(raw! as String),
    ),
    fit: optional('fit', (raw) => Fit.values.byName(raw! as String)),
    styleCut: optional(
      'styleCut',
      (raw) => StyleCut.values.byName(raw! as String),
    ),
    seasons: {
      for (final raw in (json['seasons'] as List<Object?>?) ?? const [])
        Season.values.byName(raw! as String),
    },
    suggestedName: json['suggestedName'] as String?,
    distinguishingText: json['distinguishingText'] as String?,
  );
}

CareTagScanResult careTagResultFromJson(Map<String, Object?> json) {
  final instructions = json['instructions'];
  if (instructions is! Map<String, Object?>) {
    throw ScanContractError('care tag scan is missing "instructions"');
  }

  return CareTagScanResult(
    // `CareConstraint.fromJson` preserves absent-versus-null, which is the
    // whole point of the type. Do not "helpfully" default anything here.
    instructions: CareConstraint.fromJson(instructions),
    confidence: (json['confidence']! as num).toDouble(),
    composition: json['composition'] == null
        ? null
        : Confident.fromJson(
            json['composition']! as Map<String, Object?>,
            (raw) => FabricComposition.fromJson(raw! as Map<String, Object?>),
          ),
    symbolsFound: [
      for (final symbol in (json['symbolsFound'] as List<Object?>?) ?? const [])
        symbol! as String,
    ],
    unreadableSymbolCount:
        (json['unreadableSymbolCount'] as num?)?.toInt() ?? 0,
    rawText: json['rawText'] as String?,
    language: json['language'] as String?,
  );
}

PileScanResult pileResultFromJson(Map<String, Object?> json) => PileScanResult(
  items: [
    for (final raw in (json['items'] as List<Object?>?) ?? const [])
      _detectedItemFromJson(raw! as Map<String, Object?>),
  ],
  partiallyObscuredCount:
      (json['partiallyObscuredCount'] as num?)?.toInt() ?? 0,
);

DetectedItem _detectedItemFromJson(Map<String, Object?> json) => DetectedItem(
  scan: garmentResultFromJson(json['scan']! as Map<String, Object?>),
  boundingBox: BoundingBox.fromJson(
    json['boundingBox']! as Map<String, Object?>,
  ),
  detectionConfidence: (json['detectionConfidence']! as num).toDouble(),
);
