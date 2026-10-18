/// The order garments are offered for sale in: the ones worn least first.
///
/// Those are what people sell. A coat worn forty times is one they like; a coat
/// bought, tried once and left on a hanger is the one that is worth more to
/// somebody else than to them. So the wardrobe's picker leads with what has been
/// worn least, and among garments worn the same number of times, the one that
/// has gone longest without being worn.
///
/// A date nobody recorded is not a very old one, so a garment worn before dates
/// were kept comes after those with a known one, by the rule the wardrobe's own
/// sorts follow. Never-worn garments have no date and all tie on it, and fall to
/// their names — a stable order, so the list does not shuffle between visits.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

/// [items] with the least worn first.
List<WardrobeItem> leastWornFirst(Iterable<WardrobeItem> items) =>
    items.toList()..sort(_compare);

int _compare(WardrobeItem a, WardrobeItem b) {
  final worn = a.usage.timesWorn.compareTo(b.usage.timesWorn);
  if (worn != 0) return worn;

  final longest = _longestUnworn(a.usage.lastWornAt, b.usage.lastWornAt);
  if (longest != 0) return longest;

  final named = a.displayName.toLowerCase().compareTo(
    b.displayName.toLowerCase(),
  );
  return named != 0 ? named : a.id.value.compareTo(b.id.value);
}

/// The earlier date first, which is the longer since it was worn; no date last.
int _longestUnworn(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}
