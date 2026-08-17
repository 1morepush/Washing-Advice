/// Attaching a care label reading to an item.
///
/// Extracted because two flows now do it. The label scanner has always done it
/// for a garment already in the wardrobe; the scan flow does it for one being
/// added, when the same handful of photographs carried both the garment and its
/// tag. The rules are identical and they are the sort that must not drift:
/// which composition wins, what a merged label is worth, and what care comes
/// out the other side.
///
/// The one thing that genuinely differs is that a garment being added has no
/// earlier label to merge with, which falls out of the same code rather than
/// needing its own path.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

/// An item with a label reading applied, and what that did.
typedef LabelledItem = ({
  WardrobeItem item,
  CareResolution resolution,

  /// Fields the new reading did not state, kept from a label read earlier.
  ///
  /// Always empty for an item that had no label before. Non-empty is worth
  /// showing: a value carried over from a scan weeks ago, presented as though
  /// this photograph had just read it, is the app being quietly more certain
  /// than it is.
  Set<String> keptFromEarlier,
});

/// Lays [reading] over [item] and re-resolves its care.
///
/// With [replaceEarlier] the item's existing label is discarded rather than
/// merged. That is the escape hatch a merge needs: merging keeps a field the
/// earlier scan read *wrong* whenever the new photograph is silent about it,
/// and no amount of re-scanning shifts it while that symbol stays illegible.
LabelledItem withCareLabel(
  WardrobeItem item,
  CareTagScanResult reading, {
  required CareResolver resolver,
  bool replaceEarlier = false,
}) {
  // The composition printed on the label outranks whatever was guessed from a
  // photograph of the garment, so it is taken too when the label carries one.
  // `Confident.resolve` picks by provenance first, which is precisely the
  // ordering this needs — and it is why a garment scanned together with its
  // tag ends up with the fibre content the manufacturer states rather than the
  // one the pixels suggested.
  final composition = reading.composition == null
      ? item.composition
      : Confident.resolve(item.composition, reading.composition!);

  // Laid over whatever was scanned before rather than replacing it. A re-scan
  // used to wipe out every field the new photograph did not happen to show —
  // the commonest case being somebody scanning the back of a two-sided label
  // and losing the wash symbols already read off the front.
  final earlier = replaceEarlier ? null : item.careLabel;
  final instructions = earlier == null
      ? reading.instructions
      : reading.instructions.mergedWith(earlier.value);

  final withLabel = item.copyWith(
    composition: composition,
    careLabel: Confident(
      instructions,
      // An unreadable symbol lowers confidence in the whole reading, not just
      // in the field it belonged to: if part of the label defeated the OCR,
      // the rest of it deserves less trust as well.
      //
      // A merged label takes the lower of the two, because it is no more
      // trustworthy than the least trustworthy reading it draws on — and some
      // of its fields genuinely come from the older one.
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
