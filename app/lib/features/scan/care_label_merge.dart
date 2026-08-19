/// Attaching a care label reading to an item.
///
/// Shared by the label scanner and the scan flow, which now reads a label from
/// the same photographs that identified the garment. Which composition wins and
/// what a merged label is worth are rules that must not exist twice.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

/// An item with a label reading applied, and what that did.
typedef LabelledItem = ({
  WardrobeItem item,
  CareResolution resolution,

  /// Fields the new reading did not state, kept from a label read earlier.
  /// Always empty for an item that had no label before.
  Set<String> keptFromEarlier,
});

/// Lays [reading] over [item] and re-resolves its care.
///
/// With [replaceEarlier] the existing label is discarded rather than merged.
/// Merging keeps a field the earlier scan read *wrong* whenever the new
/// photograph is silent about it, and no amount of re-scanning shifts it while
/// that symbol stays illegible.
LabelledItem withCareLabel(
  WardrobeItem item,
  CareTagScanResult reading, {
  required CareResolver resolver,
  bool replaceEarlier = false,
}) {
  // A printed composition outranks one guessed from a photograph, and
  // `Confident.resolve` picks by provenance first.
  final composition = reading.composition == null
      ? item.composition
      : Confident.resolve(item.composition, reading.composition!);

  // Laid over the earlier label rather than replacing it: a re-scan used to
  // wipe every field the new photograph did not happen to show, most often
  // losing the wash symbols off the front when somebody scanned the back.
  final earlier = replaceEarlier ? null : item.careLabel;
  final instructions = earlier == null
      ? reading.instructions
      : reading.instructions.mergedWith(earlier.value);

  final withLabel = item.copyWith(
    composition: composition,
    careLabel: Confident(
      instructions,
      // An unreadable symbol lowers confidence in the whole reading: if part
      // of the label defeated the OCR, the rest deserves less trust too. A
      // merged label takes the lower of the two, since some of its fields
      // genuinely come from the older one.
      confidence: earlier == null
          ? reading.confidence
          : (reading.confidence < earlier.confidence
                ? reading.confidence
                : earlier.confidence),
      source: Provenance.tagScan,
    ),
    updatedAt: DateTime.now(),
  );

  final resolution = resolver.forItem(withLabel);

  return (
    item: withLabel.copyWith(care: resolution.profile),
    resolution: resolution,
    keptFromEarlier: earlier == null
        ? const {}
        : reading.instructions.fieldsKeptFrom(earlier.value),
  );
}
