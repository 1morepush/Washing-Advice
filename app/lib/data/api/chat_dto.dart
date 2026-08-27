/// Asking a question in words, on the wire.
///
/// The wardrobe goes up as compact facts for the reason the stylist's does: the
/// app already holds them and is surer about them than a fresh look would be.
/// What it keeps is different, though. A stylist needs to know what a garment
/// looks like; this needs to know how it is washed, so pattern and fit come out
/// and the care line goes in.
///
/// The care line carries whether it was *read* or *worked out*. That is the one
/// field here that can cost somebody a garment: an inference relayed with the
/// confidence of a sewn-in label is how a wool jumper ends up in a tumble
/// dryer. The distinction exists in the domain already — `CareProfile.source` —
/// and this is the seam where it would be easiest to quietly drop.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

import '../../features/wardrobe/care_text.dart';

/// One garment, as the assistant is told about it.
Map<String, Object?> chatGarmentJson(WardrobeItem item) => {
  'name': item.displayName,
  'type': item.type.value.label,
  // Named colours where the scan produced a name, hex otherwise — the same
  // fallback every other screen shows, so the model is told what the user was
  // told.
  'colors': [for (final c in item.colors.value.colors) c.name ?? c.hex],
  'fabric': ?_nonEmpty(item.composition.value.label),
  'care': chatCareSummary(item),
  if (careIsGuess(item)) 'careIsGuess': true,
  'state': ?_stateLabel(item),
};

/// The care summary in the same words the item screen uses.
///
/// Deliberately built from the same helpers the item screen and the stain
/// adviser use rather than phrased afresh. A second wording here would be a
/// second thing to keep true, and the failure would be silent: the assistant
/// confidently describing a garment slightly differently from the screen the
/// user is looking at.
String chatCareSummary(WardrobeItem item) {
  final care = item.effectiveCare;
  return [
    washSummary(care.wash),
    drySummary(care.dry),
    care.bleach.label,
    if (dryCleanSummary(care) case final String line) line,
  ].join('. ');
}

/// Whether that summary is an inference rather than an instruction.
///
/// A label reading and a correction the user typed are both things somebody
/// *stated*, and the assistant may relay them as such. Everything else is the
/// app working it out and must be relayed as that.
///
/// `careRule` sits on the inference side, which is worth saying because it is
/// the tempting one to promote: the rule table's derivation is exact and
/// conservative, and it outranks a photograph for that reason. But exact is
/// not the same as *stated*. It is a correct deduction from a fibre content
/// that may itself have been guessed off a picture, and a garment ruined by it
/// is ruined just the same.
bool careIsGuess(WardrobeItem item) => switch (item.care.source) {
  Provenance.tagScan || Provenance.userEdited => false,
  Provenance.careRule ||
  Provenance.aiInference ||
  Provenance.fallbackDefault => true,
};

/// Where the garment is right now, when that is worth a word.
///
/// Only the states that change what an answer should say. "Active" is the
/// ordinary case and naming it on every line of a forty-garment wardrobe would
/// be forty wasted clauses.
String? _stateLabel(WardrobeItem item) => switch (item.lifecycle) {
  LifecycleState.inLaundry => 'in the basket',
  LifecycleState.beingWashed => 'in the machine',
  LifecycleState.beingRepaired => 'away for repair',
  LifecycleState.stored => 'in storage',
  LifecycleState.purchased => 'ordered, not arrived',
  // Everything else is either the ordinary case or an item that is no longer
  // owned, and an unowned garment never reaches this list.
  _ => null,
};

String? _nonEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
