/// A complete set of care instructions for one item.
///
/// Aggregates the five ISO 3758 symbols plus the written warnings, and carries
/// the provenance of the whole set so callers know whether they are looking at
/// a manufacturer's label or the system's best guess.
library;

import '../../shared/confidence.dart';
import 'care_symbols.dart';

/// Everything the system believes about how to treat one item.
final class CareInstructions {
  const CareInstructions({
    required this.wash,
    required this.bleach,
    required this.dry,
    required this.iron,
    required this.professional,
    this.warnings = const {},
  });

  /// The conservative fallback when nothing is known.
  ///
  /// Cool gentle wash, no bleach, air dry, cool iron. Survivable by nearly
  /// every textile, at the cost of taking longer to dry. Recorded at
  /// [Provenance.fallbackDefault] wherever it is used, so any real evidence
  /// immediately displaces it.
  const CareInstructions.conservative()
      : wash = const WashCare.unknown(),
        bleach = BleachAllowance.none,
        dry = const DryCare.unknown(),
        iron = const IronCare.unknown(),
        professional = const ProfessionalCare.unspecified(),
        warnings = const {};

  final WashCare wash;
  final BleachAllowance bleach;
  final DryCare dry;
  final IronCare iron;
  final ProfessionalCare professional;
  final Set<CareWarning> warnings;

  /// Whether this item can go through a domestic wash at all.
  bool get isMachineWashable => wash.method == WashMethod.machine;

  /// Whether the item needs to be kept out of a shared load.
  bool get requiresIsolation => warnings.contains(CareWarning.washSeparately);

  /// Combines two sets of instructions into one satisfying both.
  ///
  /// Used when a care label and a fibre rule both have something to say, and
  /// when working out the settings a whole load must run at. Always resolves
  /// toward the safer option: the merge of "40 degrees" and "30 degrees" is 30.
  CareInstructions restrictiveMerge(CareInstructions other) => CareInstructions(
        wash: wash.restrictiveMerge(other.wash),
        bleach: bleach.stricter(other.bleach),
        dry: dry.restrictiveMerge(other.dry),
        iron: iron.restrictiveMerge(other.iron),
        professional: professional.restrictiveMerge(other.professional),
        warnings: {...warnings, ...other.warnings},
      );

  CareInstructions copyWith({
    WashCare? wash,
    BleachAllowance? bleach,
    DryCare? dry,
    IronCare? iron,
    ProfessionalCare? professional,
    Set<CareWarning>? warnings,
  }) =>
      CareInstructions(
        wash: wash ?? this.wash,
        bleach: bleach ?? this.bleach,
        dry: dry ?? this.dry,
        iron: iron ?? this.iron,
        professional: professional ?? this.professional,
        warnings: warnings ?? this.warnings,
      );

  CareInstructions withWarnings(Iterable<CareWarning> extra) =>
      copyWith(warnings: {...warnings, ...extra});

  Map<String, Object?> toJson() => {
        'wash': wash.toJson(),
        'bleach': bleach.name,
        'dry': dry.toJson(),
        'iron': iron.toJson(),
        'professional': professional.toJson(),
        'warnings': warnings.map((w) => w.name).toList(),
      };

  static CareInstructions fromJson(Map<String, Object?> json) =>
      CareInstructions(
        wash: WashCare.fromJson(json['wash']! as Map<String, Object?>),
        bleach: BleachAllowance.values.byName(json['bleach']! as String),
        dry: DryCare.fromJson(json['dry']! as Map<String, Object?>),
        iron: IronCare.fromJson(json['iron']! as Map<String, Object?>),
        professional: ProfessionalCare.fromJson(
          json['professional']! as Map<String, Object?>,
        ),
        warnings: {
          for (final raw in (json['warnings'] as List<Object?>? ?? const []))
            CareWarning.values.byName(raw! as String),
        },
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CareInstructions &&
          other.wash == wash &&
          other.bleach == bleach &&
          other.dry == dry &&
          other.iron == iron &&
          other.professional == professional &&
          other.warnings.length == warnings.length &&
          other.warnings.containsAll(warnings);

  @override
  int get hashCode => Object.hash(
        wash,
        bleach,
        dry,
        iron,
        professional,
        Object.hashAllUnordered(warnings),
      );

  @override
  String toString() => 'CareInstructions($wash, ${bleach.name}, $dry, $iron)';
}

/// [CareInstructions] together with how they were arrived at.
///
/// Provenance is tracked for the set as a whole rather than per field. That is
/// a deliberate simplification: a care label is read in one act, so its fields
/// share a source and a confidence. If per-field provenance is ever needed —
/// say a label whose wash symbol is legible but whose dry symbol is creased —
/// this is the type that grows a map, and callers are unaffected.
final class CareProfile {
  const CareProfile({
    required this.instructions,
    required this.source,
    required this.confidence,
    this.lastReviewedAt,
  });

  /// A profile the user entered or corrected themselves.
  const CareProfile.fromUser(this.instructions)
      : source = Provenance.userEdited,
        confidence = 1.0,
        lastReviewedAt = null;

  /// The conservative default, at zero confidence so anything displaces it.
  const CareProfile.unknown()
      : instructions = const CareInstructions.conservative(),
        source = Provenance.fallbackDefault,
        confidence = 0.0,
        lastReviewedAt = null;

  final CareInstructions instructions;
  final Provenance source;
  final double confidence;

  /// When a human last confirmed this was right.
  final DateTime? lastReviewedAt;

  ConfidenceBand get band => ConfidenceThresholds.bandFor(confidence);

  /// Whether the app should act on this without checking with the user first.
  bool get isTrusted => band == ConfidenceBand.high;

  /// Whether the user should be asked to scan the care label.
  ///
  /// True when the belief is weak enough that acting on it risks damage — a
  /// guess from a photograph, or a bare fallback.
  bool get shouldPromptForTagScan =>
      band == ConfidenceBand.low &&
      source != Provenance.userEdited &&
      source != Provenance.tagScan;

  CareProfile copyWith({
    CareInstructions? instructions,
    Provenance? source,
    double? confidence,
    DateTime? lastReviewedAt,
  }) =>
      CareProfile(
        instructions: instructions ?? this.instructions,
        source: source ?? this.source,
        confidence: confidence ?? this.confidence,
        lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      );

  Map<String, Object?> toJson() => {
        'instructions': instructions.toJson(),
        'source': source.name,
        'confidence': confidence,
        if (lastReviewedAt != null)
          'lastReviewedAt': lastReviewedAt!.toIso8601String(),
      };

  static CareProfile fromJson(Map<String, Object?> json) => CareProfile(
        instructions: CareInstructions.fromJson(
          json['instructions']! as Map<String, Object?>,
        ),
        source: Provenance.values.byName(json['source']! as String),
        confidence: (json['confidence']! as num).toDouble(),
        lastReviewedAt: json['lastReviewedAt'] == null
            ? null
            : DateTime.parse(json['lastReviewedAt']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CareProfile &&
          other.instructions == instructions &&
          other.source == source &&
          other.confidence == confidence &&
          other.lastReviewedAt == lastReviewedAt;

  @override
  int get hashCode =>
      Object.hash(instructions, source, confidence, lastReviewedAt);

  @override
  String toString() =>
      'CareProfile(${source.name}, ${(confidence * 100).round()}%)';
}
