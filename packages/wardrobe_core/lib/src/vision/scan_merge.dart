/// Folding a fresh scan into a garment the wardrobe already knows.
///
/// Scanning is not only how items are *added*. A photograph can be retaken —
/// because the first one cut out badly, because the light was wrong, because
/// the model called a cardigan a jumper — and the answer that comes back has to
/// be reconciled with what is already recorded rather than replacing it.
///
/// Replacing would be much simpler and would be wrong in a specific way: it
/// would throw away corrections. Someone who fixed the brand by hand, retook
/// the photograph a week later for a better cutout, and got their correction
/// silently reverted has been punished for using the feature.
///
/// This lives in the vision layer rather than on [WardrobeItem] because the
/// dependency only runs one way — `vision` already knows about the wardrobe
/// model, and the wardrobe model should not have to know that cameras exist.
library;

import '../shared/confidence.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'vision_port.dart';

/// Reconciling a new [GarmentScanResult] with an item already in the wardrobe.
extension MergeGarmentScan on WardrobeItem {
  /// Returns this item with [scan] folded in, as of [at].
  ///
  /// Every believed field goes through [Confident.resolve], so the rules are
  /// the same ones the rest of the app already follows: stronger provenance
  /// wins outright, and within a provenance the more confident belief wins.
  /// In practice that means a hand-corrected value survives a re-scan, and a
  /// hesitant new guess does not displace a confident old one.
  ///
  /// **A user's correction is therefore never overwritten here, even when the
  /// re-scan is right.** That is deliberate — the app must not quietly undo an
  /// edit — and it is why the retake flow ends on a review screen: what this
  /// cannot decide, a person can, and their answer arrives as `userEdited`
  /// again.
  ///
  /// Fields the camera reports but the item stores plainly — sleeve length,
  /// fit, cut, seasons, the text on the garment — are *filled* when missing and
  /// left alone otherwise. They carry no confidence to compare, so there is
  /// nothing to arbitrate with, and overwriting on a coin toss is worse than
  /// keeping what is there.
  ///
  /// [name] is untouched. It is the one field the user is guaranteed to have
  /// looked at, and a garment renamed "Dad's old cricket jumper" must not
  /// become "Cream cable-knit sweater" because the photograph was retaken.
  ///
  /// Care is **not** re-derived here. It depends on the rule table, and the
  /// caller re-resolves through `CareResolver.forItem` — which is also what
  /// carries the scanned care label through. Doing it here without the label
  /// would downgrade a manufacturer's instruction to a generic rule.
  WardrobeItem mergeScan(GarmentScanResult scan, {required DateTime at}) {
    Confident<T>? better<T extends Object>(
      Confident<T>? existing,
      Confident<T>? found,
    ) {
      if (existing == null) return found;
      if (found == null) return existing;
      return Confident.resolve(existing, found);
    }

    return copyWith(
      type: Confident.resolve(type, scan.type),
      colors: Confident.resolve(colors, scan.colors),
      composition: better(composition, scan.composition),
      brand: better(brand, scan.brand),
      pattern: better(pattern, scan.pattern),
      sleeveLength: sleeveLength ?? scan.sleeveLength?.value,
      fit: fit ?? scan.fit?.value,
      styleCut: styleCut ?? scan.styleCut?.value,
      seasons: seasons.isEmpty ? scan.seasons : seasons,
      distinguishingText: distinguishingText ?? scan.distinguishingText,
      updatedAt: at,
    );
  }
}
