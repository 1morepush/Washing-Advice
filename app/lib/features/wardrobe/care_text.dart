/// Turning care values into sentences.
///
/// These read the core's model and phrase it; they never decide anything. A
/// temperature or a permission invented here would be laundry logic in the
/// presentation layer, which is exactly what the core exists to prevent.
///
/// Shared rather than private to one screen because the item detail and the
/// care-label review must describe the same instructions identically — two
/// wordings for one fact reads as two different facts.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

String washSummary(WashCare wash) {
  if (wash.method == WashMethod.doNotWash) return 'Do not wash';
  return [
    wash.method.label,
    if (wash.maxTempC case final int temp) 'up to $temp°C',
    if (wash.agitation != Agitation.normal) wash.agitation.label.toLowerCase(),
  ].join(', ');
}

String drySummary(DryCare dry) {
  // When a dryer is permitted, the natural method is an *alternative* and has
  // to read as one. Comma-joining them gave "Tumble dry low heat, Dry flat",
  // which reads as two instructions that contradict each other. When a dryer
  // is forbidden it genuinely is the instruction, so the comma is right there.
  final natural = dry.naturalDry?.label.toLowerCase();

  final drying = dry.tumbleDryAllowed
      ? [
          'Tumble dry ${dry.tumbleDryHeat.label.toLowerCase()}',
          if (natural != null) 'or $natural',
        ].join(', ')
      : ['Do not tumble dry', ?natural].join(', ');

  return [
    drying,
    if (dry.dryInShade) 'out of direct sun',
    if (dry.doNotWring) 'do not wring',
  ].join(', ');
}

String ironSummary(IronCare iron) {
  if (!iron.isIronable) return 'Do not iron';
  return iron.steamAllowed
      ? '${iron.temperature.label}, steam allowed'
      : '${iron.temperature.label}, no steam';
}

/// A user-facing name for one of the resolver's field identifiers.
///
/// The identifiers in [CareResolution.fieldsOverriddenByLabel] are dotted paths
/// meant for code — `dry.tumbleDryAllowed`. Showing those to a user would be
/// leaking the model's shape into the interface.
String careFieldLabel(String field) => switch (field) {
  'wash.method' => 'Wash method',
  'wash.maxTempC' => 'Temperature',
  'wash.agitation' => 'Cycle',
  'bleach' => 'Bleach',
  'dry.tumbleDryAllowed' => 'Tumble drying',
  'dry.tumbleDryHeat' => 'Dryer heat',
  'dry.naturalDry' => 'Air drying',
  'dry.dryInShade' => 'Sunlight',
  'dry.doNotWring' => 'Wringing',
  'iron.temperature' => 'Ironing',
  'iron.steamAllowed' => 'Steam',
  'professional.doNotDryClean' => 'Dry cleaning',
  _ => field,
};

/// The value of one field, phrased for a person.
///
/// Mirrors `CareResolver._valueOf`, which reads the same paths for comparison.
/// The pairing is deliberate: that method decides *whether* a field changed,
/// and this one says what it changed to, so they must agree on what each path
/// refers to.
String careFieldValue(CareInstructions instructions, String field) =>
    switch (field) {
      'wash.method' => instructions.wash.method.label,
      'wash.maxTempC' =>
        instructions.wash.maxTempC == null
            ? 'no limit'
            : '${instructions.wash.maxTempC}°C',
      'wash.agitation' => instructions.wash.agitation.label,
      'bleach' => instructions.bleach.label,
      'dry.tumbleDryAllowed' =>
        instructions.dry.tumbleDryAllowed ? 'allowed' : 'not allowed',
      'dry.tumbleDryHeat' => instructions.dry.tumbleDryHeat.label,
      'dry.naturalDry' => instructions.dry.naturalDry?.label ?? 'unspecified',
      'dry.dryInShade' =>
        instructions.dry.dryInShade ? 'keep out of sun' : 'sun is fine',
      'dry.doNotWring' =>
        instructions.dry.doNotWring ? 'do not wring' : 'wringing is fine',
      'iron.temperature' => instructions.iron.temperature.label,
      'iron.steamAllowed' =>
        instructions.iron.steamAllowed ? 'allowed' : 'not allowed',
      'professional.doNotDryClean' =>
        instructions.professional.doNotDryClean ? 'not allowed' : 'allowed',
      _ => '—',
    };
