/// Confidence and provenance tracking for every fact the system believes.
///
/// The app perceives the world through a camera and a language model, so almost
/// nothing it knows is certain. Rather than laundering guesses into facts, every
/// derived value is wrapped in [Confident], carrying both how sure we are and
/// where the belief came from. That is what lets the UI ask "Is this your gray
/// Nike hoodie?" instead of silently mis-washing a garment.
library;

/// Where a believed fact came from, ordered by how much it should be trusted.
///
/// The ordinal order matters: [resolutionRank] uses it to break ties when two
/// sources disagree about the same field.
enum Provenance {
  /// A conservative default applied when nothing at all is known.
  fallbackDefault,

  /// A vision model's reading of a photograph. The weakest real evidence — the
  /// model is guessing at fibre content and construction from pixels.
  aiInference,

  /// Derived deterministically from fibre composition via the care rule table.
  /// Outranks [aiInference] because the derivation itself is exact and
  /// conservative, even when the composition feeding it was inferred.
  careRule,

  /// Read from a physical care label. The manufacturer's own instruction.
  tagScan,

  /// The human corrected it. Always wins; people know things the camera cannot
  /// see, like that a garment already shrank once.
  userEdited;

  /// Higher wins when two sources claim the same field.
  int get resolutionRank => index;
}

/// How much weight to give a belief, for callers that want a coarse decision
/// rather than a raw number.
enum ConfidenceBand {
  /// Trust it silently.
  high,

  /// Usable, but worth confirming with the user before acting destructively.
  medium,

  /// Do not act on this without asking.
  low,
}

/// Central thresholds so "how sure is sure enough" is one decision, not a
/// number scattered across the codebase.
abstract final class ConfidenceThresholds {
  /// At or above this, a belief is acted on without asking.
  static const double high = 0.85;

  /// At or above this, a belief is usable but should be confirmed.
  static const double medium = 0.55;

  /// Below [medium] the value is treated as a suggestion only.
  static ConfidenceBand bandFor(double confidence) {
    if (confidence >= high) return ConfidenceBand.high;
    if (confidence >= medium) return ConfidenceBand.medium;
    return ConfidenceBand.low;
  }
}

/// A value the system believes, together with how strongly and on what basis.
///
/// Immutable. [T] is constrained to [Object] so that "unknown" is expressed by
/// a null [Confident] rather than by a confident belief in null.
final class Confident<T extends Object> {
  Confident(this.value, {required this.confidence, required this.source})
      : assert(
          confidence >= 0.0 && confidence <= 1.0,
          'confidence must be within 0..1, got $confidence',
        );

  /// A fact stated by the user. Certain by definition.
  Confident.fromUser(this.value)
      : confidence = 1.0,
        source = Provenance.userEdited;

  /// A conservative default. Recorded at zero confidence so it always loses to
  /// real evidence, while still being a usable value.
  Confident.fallback(this.value)
      : confidence = 0.0,
        source = Provenance.fallbackDefault;

  final T value;

  /// How sure we are, in `0..1`.
  final double confidence;

  /// What kind of evidence produced this.
  final Provenance source;

  ConfidenceBand get band => ConfidenceThresholds.bandFor(confidence);

  bool get isTrusted => band == ConfidenceBand.high;

  /// True when this is worth surfacing to the user for confirmation: good
  /// enough to propose, not good enough to assume.
  bool get needsConfirmation => band == ConfidenceBand.medium;

  /// Transforms the held value, preserving confidence and provenance.
  Confident<R> map<R extends Object>(R Function(T value) transform) =>
      Confident(transform(value), confidence: confidence, source: source);

  /// Reduces confidence to reflect an additional uncertain step.
  ///
  /// Used when a belief is derived from another belief — deriving care rules
  /// from an AI-guessed fibre composition cannot be more certain than the
  /// composition guess itself was.
  Confident<T> attenuatedBy(double factor) => Confident(
        value,
        confidence: confidence * factor.clamp(0.0, 1.0),
        source: source,
      );

  /// Picks the belief that should win when two sources describe the same field.
  ///
  /// Stronger provenance wins outright; within the same provenance the more
  /// confident belief wins. Deliberately not confidence-only: a hesitant care
  /// label still beats a breezy guess from a photograph.
  static Confident<T> resolve<T extends Object>(
    Confident<T> a,
    Confident<T> b,
  ) {
    final rankDelta = a.source.resolutionRank - b.source.resolutionRank;
    if (rankDelta != 0) return rankDelta > 0 ? a : b;
    return a.confidence >= b.confidence ? a : b;
  }

  Map<String, Object?> toJson(Object? Function(T value) encodeValue) => {
        'value': encodeValue(value),
        'confidence': confidence,
        'source': source.name,
      };

  static Confident<T> fromJson<T extends Object>(
    Map<String, Object?> json,
    T Function(Object? raw) decodeValue,
  ) =>
      Confident(
        decodeValue(json['value']),
        confidence: (json['confidence']! as num).toDouble(),
        source: Provenance.values.byName(json['source']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Confident<T> &&
          other.value == value &&
          other.confidence == confidence &&
          other.source == source;

  @override
  int get hashCode => Object.hash(value, confidence, source);

  @override
  String toString() =>
      'Confident($value, ${(confidence * 100).round()}%, ${source.name})';
}
