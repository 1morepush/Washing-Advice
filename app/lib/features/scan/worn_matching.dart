/// Asking "do I already own this?" of what a photo found.
///
/// The lay-flat scan, the add-from-a-photo-of-me scan and Worn today all put
/// the same question to the same matcher, and all three need the same two
/// rules around it, so they live once, here.
///
/// **A wardrobe item answers at most one detection per photo.** Two identical
/// socks in one frame must not both resolve to the same row, which would
/// record one and skip the other.
///
/// **Only a confident match counts as "the same".** The ambiguous middle (three
/// identical black t-shirts) is reported as such and left to the caller:
/// adding a duplicate costs a tap to delete, and silently skipping a real
/// garment costs a garment.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

/// What the matcher compares: the facts a scan reads off a garment.
GarmentFingerprint fingerprintOf(GarmentScanResult scan) => GarmentFingerprint(
  type: scan.type.value,
  colors: scan.colors.value,
  composition: scan.composition?.value ?? FabricComposition.unknown(),
  brand: scan.brand?.value,
  pattern: scan.pattern?.value,
  distinguishingText: scan.distinguishingText,
);

/// One decision per entry of [scans], in order, against [pool].
List<MatchDecision> resolveAgainst({
  required List<GarmentScanResult> scans,
  required List<WardrobeItem> pool,
  required ItemMatcher matcher,
  required MatchResolver resolver,
}) {
  final claimed = <ItemId>{};
  final decisions = <MatchDecision>[];

  for (final scan in scans) {
    final available = [
      for (final item in pool)
        if (!claimed.contains(item.id)) item,
    ];
    final decision = resolver.resolve(
      matcher.rank(fingerprintOf(scan), available),
    );
    if (decision case RecognizedItem(:final itemId)) claimed.add(itemId);
    decisions.add(decision);
  }
  return decisions;
}
