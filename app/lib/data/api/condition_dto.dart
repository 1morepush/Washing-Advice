/// A garment looked over for wear, on the wire.
///
/// What comes back is **unvetted**, the same as stain advice and outfit
/// proposals. A wear observation is not cosmetic: it moves the condition
/// grade, it can push a garment to end-of-life, and through
/// `warrantsGentlerCare` it changes how the thing is washed from the next load
/// onward. Handing one straight to the repository would let a shadow in the
/// weave rewrite laundry advice on evidence nobody saw.
///
/// `ConditionReview` in the core turns these into proposals worth putting to a
/// user, and only a user turns one of those into a `WearObservation`. The types
/// are deliberately distinct at each step, which is what makes skipping one a
/// compile error rather than an oversight.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

import 'scan_dto.dart';

/// Reads the observations out of a `result` object.
///
/// An entry naming a wear type this build has never heard of is dropped rather
/// than thrown on. The server can ship a new kind of wear before the app knows
/// it, and refusing the whole reading over one unknown entry would lose the
/// hole in the elbow because a new word arrived beside it.
List<ObservedWear> observedWearFromJson(Map<String, Object?> json) {
  final observed = json['observed'];
  if (observed is! List) {
    throw ScanContractError('the reading had no "observed"');
  }

  final wear = <ObservedWear>[];

  for (final entry in observed) {
    if (entry is! Map<String, Object?>) continue;

    final type = _typeFrom(entry['type']);
    final severity = _severityFrom(entry['severity']);
    final confidence = entry['confidence'];
    if (type == null || severity == null || confidence is! num) continue;

    // A smell cannot be seen. The server drops these too, and both ends do it
    // because an app that reported one from a photograph would be making a
    // claim about the physical world it cannot possibly have checked.
    if (type == WearType.odour) continue;

    wear.add(
      ObservedWear(
        type: type,
        severity: severity,
        confidence: confidence.toDouble().clamp(0.0, 1.0),
        note: _nonEmpty(entry['note']),
      ),
    );
  }

  return wear;
}

WearType? _typeFrom(Object? raw) {
  if (raw is! String) return null;
  for (final type in WearType.values) {
    if (type.name == raw) return type;
  }
  return null;
}

WearSeverity? _severityFrom(Object? raw) {
  if (raw is! String) return null;
  for (final severity in WearSeverity.values) {
    if (severity.name == raw) return severity;
  }
  return null;
}

String? _nonEmpty(Object? raw) =>
    raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
