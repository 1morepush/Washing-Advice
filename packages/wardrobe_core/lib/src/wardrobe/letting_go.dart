/// Garments that have gone a year without being worn: things worth offering to
/// let go of.
///
/// This is a *suggestion*, and everything about it is built to stay one. It
/// says what is true ("not worn in over a year"), never what to do, and it
/// is conservative in the places where a year of silence is not evidence of
/// anything: the pieces people keep for an occasion, and the things nobody
/// logs wearing at all.
///
/// A pure function of the garments and "now" — the cached usage counters on
/// each item, which the event log is the authority for. Nothing is stored.
library;

import '../shared/ids.dart';
import 'model/item_attributes.dart';
import 'model/lifecycle.dart';
import 'model/wardrobe_item.dart';

/// How many months of not being worn make a garment a candidate.
const int letGoAfterMonths = 12;

/// How many months a "Keep" answer quiets the suggestion for.
const int keepForMonths = 6;

/// Item types a long gap says nothing about.
///
/// A blazer, a dress, dress shoes and a tie are bought for the wedding, the
/// interview and the funeral, and a year between those is the ordinary case
/// rather than a sign they were a mistake. Swimwear waits for a holiday, and a
/// year without one is not unusual.
///
/// Deliberately short. The model has no "occasion piece" attribute, only
/// types, so this is the types that are occasion pieces *nearly every time*;
/// a coat is not here because twelve months always contains a whole winter,
/// and the same goes for every other seasonal garment — the window is long
/// enough that "it was out of season" cannot explain it. Leaving one wrong
/// type out costs a suggestion the person can wave away with Keep; putting a
/// wrong one in would tell somebody to sell their only suit jacket.
const Set<ItemType> occasionTypes = {
  ItemType.blazer,
  ItemType.dress,
  ItemType.dressShoes,
  ItemType.tie,
  ItemType.swimwear,
};

/// Things that are not sold on after a year or are not "worn" in the sense a
/// wear log records: underwear and socks (nobody logs them, and nobody buys
/// them second-hand), and household linen.
bool _isNotWornInTheSenseOfTheLog(ItemType type) =>
    type.kind == ItemKind.linen ||
    type.category == ItemCategory.underwear ||
    type.category == ItemCategory.legwear;

/// One garment worth offering to let go of, and why.
final class LetGoCandidate {
  const LetGoCandidate({
    required this.item,
    required this.since,
    required this.neverWorn,
    required this.idle,
  });

  final WardrobeItem item;

  /// When it was last worn, or when it was added if it never has been.
  final DateTime since;

  /// Whether it has no wear on record at all, so [since] is the day it came
  /// into the wardrobe and the screen can say "never worn" instead of
  /// inventing a last-worn date.
  final bool neverWorn;

  /// How long since [since], as of the moment asked about.
  final Duration idle;
}

/// The garments in [items] that have not been worn for [letGoAfterMonths].
///
/// A garment qualifies when all of these hold:
///
/// * it is owned and either active or stored. One in the wash, being repaired
///   or still on order is not idle, it is somewhere; and one already sold,
///   donated, discarded, lost or removed has been let go of;
/// * it was added more than [letGoAfterMonths] months before [now], so
///   something bought last spring is never called neglected;
/// * its last wear — or, if it has never been worn, the day it was added — is
///   more than [letGoAfterMonths] months before [now]. A wear exactly twelve
///   months ago counts as inside the year;
/// * its type is not one of [occasionTypes] and not something nobody logs.
///
/// [keptOn] holds the day a person answered "Keep" for a garment. That answer
/// holds for [keepForMonths] and then the suggestion may return, because a
/// year of silence after a decision to keep is a fresh piece of information.
///
/// Longest-unworn first; equal dates fall back to the name so the order is
/// stable between runs.
List<LetGoCandidate> letGoCandidates(
  Iterable<WardrobeItem> items, {
  required DateTime now,
  Map<ItemId, DateTime> keptOn = const {},
}) {
  final cutoff = monthsBefore(now, letGoAfterMonths);
  final out = <LetGoCandidate>[];

  for (final item in items) {
    if (item.lifecycle != LifecycleState.active &&
        item.lifecycle != LifecycleState.stored) {
      continue;
    }
    final type = item.type.value;
    if (occasionTypes.contains(type) || _isNotWornInTheSenseOfTheLog(type)) {
      continue;
    }
    if (!item.addedAt.isBefore(cutoff)) continue;

    final lastWorn = item.usage.lastWornAt;
    final since = lastWorn ?? item.addedAt;
    if (!since.isBefore(cutoff)) continue;

    final kept = keptOn[item.id];
    if (kept != null && monthsBefore(now, keepForMonths).isBefore(kept)) {
      // Kept within the last six months, counted exactly as the year is: an
      // answer given precisely six months ago has lapsed.
      continue;
    }

    out.add(
      LetGoCandidate(
        item: item,
        since: since,
        neverWorn: lastWorn == null,
        idle: now.difference(since),
      ),
    );
  }

  out.sort((a, b) {
    final byAge = a.since.compareTo(b.since);
    return byAge != 0
        ? byAge
        : a.item.displayName.compareTo(b.item.displayName);
  });
  return out;
}

/// [instant] moved back by [months] calendar months, in UTC.
///
/// Calendar months and not 30-day blocks: "a year ago" is the same date last
/// year, and thirty-day arithmetic drifts five days off by the end of one. A
/// date that does not exist the earlier month (the 31st; the 29th of February)
/// lands on the last day that does.
DateTime monthsBefore(DateTime instant, int months) {
  final utc = instant.toUtc();
  final total = utc.year * 12 + (utc.month - 1) - months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(
    year,
    month,
    utc.day > lastDay ? lastDay : utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
    utc.microsecond,
  );
}
