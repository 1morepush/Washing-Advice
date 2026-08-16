/// The physical condition of an item.
///
/// Automatic detection of fading, pilling and holes is a later milestone, but
/// the *model* exists now so observations can be recorded by hand, tracked over
/// time, and fed to the care engine. Condition genuinely changes care advice: a
/// garment already pilling should be washed inside out on a gentler cycle.
///
/// See `Feature.conditionDetection` — the vision side of this is not built yet.
library;

/// A kind of wear that can be observed on an item.
enum WearType {
  fading('Fading'),
  pilling('Pilling'),
  hole('Hole'),
  tear('Tear'),
  stain('Stain'),
  stretchedOut('Stretched out'),
  shrunk('Shrunk'),
  looseSeam('Loose seam'),
  brokenFastener('Broken fastener'),
  odour('Persistent odor');

  const WearType(this.label);

  final String label;

  /// Whether this is likely to get worse in a normal wash, and so should
  /// downgrade the item to a gentler cycle.
  bool get worsensWithWashing => switch (this) {
        fading || pilling || hole || tear || looseSeam || stretchedOut => true,
        stain || shrunk || brokenFastener || odour => false,
      };

  /// Whether this can honestly get *better*.
  ///
  /// A stain comes out, a seam is sewn up, a button is replaced, a smell
  /// washes away. Fading, pilling, holes and stretch do not undo themselves —
  /// so a fresh observation reporting less of one of those than is already on
  /// record is something being looked at less carefully, not a garment
  /// recovering. That distinction is what stops a hurried glance overwriting a
  /// careful one.
  bool get isReversible => switch (this) {
        stain || looseSeam || brokenFastener || odour => true,
        fading || pilling || hole || tear || stretchedOut || shrunk => false,
      };
}

/// How bad an observed problem is.
enum WearSeverity {
  slight('Slight'),
  moderate('Moderate'),
  severe('Severe');

  const WearSeverity(this.label);

  final String label;
}

/// One observation of wear.
final class WearObservation {
  const WearObservation({
    required this.type,
    required this.severity,
    required this.observedAt,
    this.note,
    this.photoUri,
  });

  final WearType type;
  final WearSeverity severity;
  final DateTime observedAt;
  final String? note;

  /// Optional evidence, so change can be compared over time.
  final String? photoUri;

  Map<String, Object?> toJson() => {
        'type': type.name,
        'severity': severity.name,
        'observedAt': observedAt.toIso8601String(),
        if (note != null) 'note': note,
        if (photoUri != null) 'photoUri': photoUri,
      };

  static WearObservation fromJson(Map<String, Object?> json) => WearObservation(
        type: WearType.values.byName(json['type']! as String),
        severity: WearSeverity.values.byName(json['severity']! as String),
        observedAt: DateTime.parse(json['observedAt']! as String),
        note: json['note'] as String?,
        photoUri: json['photoUri'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WearObservation &&
          other.type == type &&
          other.severity == severity &&
          other.observedAt == observedAt &&
          other.note == note &&
          other.photoUri == photoUri;

  @override
  int get hashCode => Object.hash(type, severity, observedAt, note, photoUri);

  @override
  String toString() =>
      'WearObservation(${severity.name} ${type.name} @ $observedAt)';
}

/// Overall assessment of an item's condition, derived from its observations.
enum ConditionGrade {
  pristine('Like new'),
  good('Good'),
  worn('Visibly worn'),
  damaged('Damaged'),
  endOfLife('End of life');

  const ConditionGrade(this.label);

  final String label;
}

/// The accumulated condition of a single item.
final class ConditionAssessment {
  ConditionAssessment(List<WearObservation> observations)
      : _observations = List.unmodifiable(
          // Explicitly typed: `List.unmodifiable` takes an `Iterable<dynamic>`,
          // and without this the literal infers as `List<dynamic>` and the
          // comparator loses its types.
          <WearObservation>[...observations]
            ..sort((x, y) => y.observedAt.compareTo(x.observedAt)),
        );

  /// Private const path, so [pristine] can be used as a default argument.
  const ConditionAssessment._const(this._observations);

  /// An item with no recorded wear.
  static const ConditionAssessment pristine = ConditionAssessment._const([]);

  final List<WearObservation> _observations;

  /// Most recent first.
  List<WearObservation> get observations => _observations;

  bool get isPristine => _observations.isEmpty;

  /// The most recent observation of each wear type.
  ///
  /// Earlier observations are kept for history, but only the latest describes
  /// the item's present state.
  Map<WearType, WearObservation> get current {
    final latest = <WearType, WearObservation>{};
    for (final observation in _observations) {
      latest.putIfAbsent(observation.type, () => observation);
    }
    return Map.unmodifiable(latest);
  }

  /// An overall grade, driven by the worst current problem and how many there
  /// are. Two moderate problems read worse than one.
  ConditionGrade get grade {
    final active = current.values.toList();
    if (active.isEmpty) return ConditionGrade.pristine;

    final severe =
        active.where((o) => o.severity == WearSeverity.severe).length;
    final moderate =
        active.where((o) => o.severity == WearSeverity.moderate).length;

    if (severe >= 2) return ConditionGrade.endOfLife;
    if (severe == 1) return ConditionGrade.damaged;
    if (moderate >= 2) return ConditionGrade.worn;
    if (moderate == 1) return ConditionGrade.worn;
    return ConditionGrade.good;
  }

  /// Whether the item should be handled more gently than its label demands.
  ///
  /// Care labels describe a new garment. Once something is pilling or has a
  /// loose seam, a normal cycle will finish the job.
  bool get warrantsGentlerCare => current.values.any(
        (o) => o.type.worsensWithWashing && o.severity != WearSeverity.slight,
      );

  ConditionAssessment record(WearObservation observation) =>
      ConditionAssessment([..._observations, observation]);

  List<Object?> toJson() => _observations.map((o) => o.toJson()).toList();

  static ConditionAssessment fromJson(List<Object?> json) =>
      ConditionAssessment([
        for (final entry in json)
          WearObservation.fromJson(entry! as Map<String, Object?>),
      ]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConditionAssessment &&
          other._observations.length == _observations.length &&
          Iterable<int>.generate(_observations.length)
              .every((i) => _observations[i] == other._observations[i]);

  @override
  int get hashCode => Object.hashAll(_observations);

  @override
  String toString() => 'ConditionAssessment(${grade.label}, '
      '${_observations.length} observations)';
}
