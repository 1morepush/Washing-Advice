/// Reconciling two versions of the same item.
///
/// ## Why not last-writer-wins
///
/// The usual answer to "the same row changed on two devices" is to keep
/// whichever has the later timestamp. That is wrong here, and wrong in a way
/// that destroys the most valuable data in the system.
///
/// Consider: on Monday you scan a jumper's care label on your phone, learning
/// it is superwash and may be machine washed at 40°. On Tuesday your tablet —
/// which never saw that scan — re-identifies the same jumper from a photograph
/// and guesses "100% wool". Last-writer-wins takes Tuesday's guess, silently
/// discards a manufacturer's instruction, and starts telling you to hand wash
/// a machine-washable garment. The clocks are working perfectly; the answer is
/// still wrong.
///
/// The system already knows how to settle this. [Provenance] orders evidence
/// by how much it deserves to be believed — a user edit beats a care label,
/// which beats a rule, which beats a photograph — and [Confident.resolve]
/// applies that ordering. Merging two devices is the same question as merging
/// a label with a photo, so it gets the same answer.
///
/// ## Where time still decides
///
/// Provenance cannot settle everything. Two user edits are both
/// [Provenance.userEdited], and plain fields — a name, a size, a note — carry
/// no provenance at all. For those the later `updatedAt` wins, which is the
/// right rule for a field whose only authority is that a person typed it.
///
/// Counters are different again: they are a projection of the event log, and
/// the log merges by union rather than by choosing. Taking the *larger* of two
/// wear counts is a stopgap that holds until the events themselves are synced,
/// at which point replay produces the true figure. That is stated here rather
/// than hidden, because a counter that is merely plausible should not be
/// mistaken for one that is derived.
library;

import '../care/model/care_instructions.dart';
import '../shared/confidence.dart';
import '../wardrobe/model/ownership.dart';
import '../wardrobe/model/photo.dart';
import '../wardrobe/model/wardrobe_item.dart';

/// How a merge was decided, per field, for logging and for tests.
enum MergeOutcome {
  /// The two versions were already the same.
  identical,

  /// One side had stronger provenance.
  byProvenance,

  /// Same provenance; the more recent edit won.
  byRecency,

  /// Both sides contributed — sets, photos, counters.
  combined,
}

/// The result of reconciling two versions of one item.
final class MergeResult {
  const MergeResult({required this.item, required this.decisions});

  final WardrobeItem item;

  /// Which rule settled each field that differed, keyed by field name.
  ///
  /// Kept because a sync that cannot explain itself is one nobody will trust
  /// with the only copy of their data.
  final Map<String, MergeOutcome> decisions;

  bool get hadConflict => decisions.values.any(
        (outcome) => outcome != MergeOutcome.identical,
      );

  @override
  String toString() =>
      'MergeResult(${item.id.value}, ${decisions.length} fields)';
}

extension MergeItems on WardrobeItem {
  /// Reconciles this version with [other], which describes the same item.
  ///
  /// Symmetric: merging A into B gives the same result as merging B into A,
  /// which matters because two devices reconciling with each other must not
  /// end up in different states and then keep trying to correct one another.
  MergeResult mergedWith(WardrobeItem other) {
    assert(id == other.id, 'cannot merge different items');

    final decisions = <String, MergeOutcome>{};

    final newer = other.updatedAt.isAfter(updatedAt) ? other : this;

    /// Whether this side's value wins, for fields provenance cannot settle.
    ///
    /// Recency decides when the timestamps differ. When they do **not**, the
    /// tie is broken on the values themselves rather than on which object
    /// happens to be the receiver — because the receiver differs between the
    /// two devices, and a rule that depends on it does not converge: each
    /// device keeps its own value and they correct each other forever. Two
    /// clocks agreeing to the millisecond is rare but a merge that never
    /// settles is not a failure mode worth leaving in.
    ///
    /// The chosen value is arbitrary. It is *agreed*, which is the only
    /// property available once the timestamps have stopped distinguishing
    /// them.
    bool mineWins(Object? mine, Object? theirs) {
      final byTime = updatedAt.compareTo(other.updatedAt);
      if (byTime != 0) return byTime > 0;
      return '$mine'.compareTo('$theirs') >= 0;
    }

    T plain<T>(String field, T mine, T theirs) {
      if (mine == theirs) {
        decisions[field] = MergeOutcome.identical;
        return mine;
      }
      decisions[field] = MergeOutcome.byRecency;
      return mineWins(mine, theirs) ? mine : theirs;
    }

    Confident<T> believed<T extends Object>(
      String field,
      Confident<T> mine,
      Confident<T> theirs,
    ) {
      if (mine.value == theirs.value && mine.source == theirs.source) {
        decisions[field] = MergeOutcome.identical;
        return mine;
      }
      // Same provenance means provenance cannot decide, so recency does —
      // otherwise two user edits would be settled by whose confidence value
      // happened to be higher, which is not a fact about either edit.
      if (mine.source == theirs.source) {
        decisions[field] = MergeOutcome.byRecency;
        return mineWins(mine.value, theirs.value) ? mine : theirs;
      }
      decisions[field] = MergeOutcome.byProvenance;
      return Confident.resolve(mine, theirs);
    }

    Confident<T>? optional<T extends Object>(
      String field,
      Confident<T>? mine,
      Confident<T>? theirs,
    ) {
      if (mine == null && theirs == null) return null;
      // One side knowing something the other does not is not a conflict. It is
      // the ordinary case for a device that has scanned a label the other has
      // never seen, and dropping it would make sync lose information.
      if (mine == null || theirs == null) {
        decisions[field] = MergeOutcome.combined;
        return mine ?? theirs;
      }
      return believed(field, mine, theirs);
    }

    final merged = WardrobeItem(
      id: id,
      name: plain('name', name, other.name),
      type: believed('type', type, other.type),
      composition: believed('composition', composition, other.composition),
      colors: believed('colors', colors, other.colors),
      brand: optional('brand', brand, other.brand),
      pattern: optional('pattern', pattern, other.pattern),
      careLabel: optional('careLabel', careLabel, other.careLabel),
      // The care profile follows its own provenance, exactly as it does when a
      // label meets a rule. A `tagScan` profile from one device beats a
      // `careRule` profile from another without consulting a clock.
      care: _mergeCare(
        decisions,
        care,
        other.care,
        preferMine: mineWins(care.source.name, other.care.source.name),
      ),
      photos: _mergePhotos(decisions, photos, other.photos),
      lifecycle: plain('lifecycle', lifecycle, other.lifecycle),
      condition: plain('condition', condition, other.condition),
      usage: _mergeUsage(decisions, usage, other.usage),
      purchase: _mergePurchase(
        decisions,
        purchase,
        other.purchase,
        preferMine: mineWins(purchase, other.purchase),
      ),
      sizeLabel: plain('sizeLabel', sizeLabel, other.sizeLabel),
      sleeveLength: plain('sleeveLength', sleeveLength, other.sleeveLength),
      fit: plain('fit', fit, other.fit),
      // Sets union rather than choose. A tag added on one device and another
      // added on the second are both things the user did, and picking a winner
      // would throw one of them away for no reason.
      seasons: _union(decisions, 'seasons', seasons, other.seasons),
      styleCut: plain('styleCut', styleCut, other.styleCut),
      isFavorite: plain('isFavorite', isFavorite, other.isFavorite),
      tags: _union(decisions, 'tags', tags, other.tags),
      notes: plain('notes', notes, other.notes),
      distinguishingText: plain(
          'distinguishingText', distinguishingText, other.distinguishingText),
      // The earlier of the two: an item is as old as its first sighting, and
      // taking the later date would make a garment appear to have been bought
      // when it was merely synced.
      addedAt: addedAt.isBefore(other.addedAt) ? addedAt : other.addedAt,
      updatedAt: newer.updatedAt,
    );

    // Fields that ended up identical are not conflicts worth reporting.
    decisions.removeWhere((_, outcome) => outcome == MergeOutcome.identical);
    return MergeResult(item: merged, decisions: decisions);
  }
}

CareProfile _mergeCare(
  Map<String, MergeOutcome> decisions,
  CareProfile mine,
  CareProfile theirs, {
  required bool preferMine,
}) {
  if (mine.source == theirs.source && mine.confidence == theirs.confidence) {
    decisions['care'] = MergeOutcome.identical;
    return preferMine ? mine : theirs;
  }
  if (mine.source == theirs.source) {
    decisions['care'] = MergeOutcome.byRecency;
    return preferMine ? mine : theirs;
  }
  decisions['care'] = MergeOutcome.byProvenance;
  return mine.source.resolutionRank > theirs.source.resolutionRank
      ? mine
      : theirs;
}

/// Photos union by URI, keeping any cutout either side has made.
///
/// A photograph taken on one device and one taken on the other are both real,
/// and there is no sense in which either supersedes the other.
PhotoSet _mergePhotos(
  Map<String, MergeOutcome> decisions,
  PhotoSet mine,
  PhotoSet theirs,
) {
  final byUri = <String, ItemPhoto>{
    for (final photo in mine.photos) photo.uri: photo,
  };

  for (final photo in theirs.photos) {
    final existing = byUri[photo.uri];
    byUri[photo.uri] = existing == null
        ? photo
        // Same photo, and one side has since had a cutout made for it.
        : existing.copyWith(cutoutUri: existing.cutoutUri ?? photo.cutoutUri);
  }

  final merged = PhotoSet(byUri.values.toList());
  decisions['photos'] =
      merged.length == mine.length && merged.length == theirs.length
          ? MergeOutcome.identical
          : MergeOutcome.combined;
  return merged;
}

/// Counters, pending an event-log merge.
///
/// The honest answer is "replay the union of both logs", and that is what
/// happens once events sync. Until then the larger of each count is the best
/// available approximation and is never *smaller* than the truth on either
/// device — which matters, because a count that went down would make a garment
/// look newer than it is and re-enable the dye-bleed isolation it had earned
/// its way out of.
UsageStats _mergeUsage(
  Map<String, MergeOutcome> decisions,
  UsageStats mine,
  UsageStats theirs,
) {
  if (mine == theirs) {
    decisions['usage'] = MergeOutcome.identical;
    return mine;
  }
  decisions['usage'] = MergeOutcome.combined;

  DateTime? later(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  return UsageStats(
    timesWorn:
        mine.timesWorn > theirs.timesWorn ? mine.timesWorn : theirs.timesWorn,
    timesWashed: mine.timesWashed > theirs.timesWashed
        ? mine.timesWashed
        : theirs.timesWashed,
    wearsSinceWash: mine.wearsSinceWash > theirs.wearsSinceWash
        ? mine.wearsSinceWash
        : theirs.wearsSinceWash,
    lastWornAt: later(mine.lastWornAt, theirs.lastWornAt),
    lastWashedAt: later(mine.lastWashedAt, theirs.lastWashedAt),
    firstWornAt: _earlier(mine.firstWornAt, theirs.firstWornAt),
  );
}

DateTime? _earlier(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isBefore(b) ? a : b;
}

/// Purchase details, preferring whichever side has them.
PurchaseInfo? _mergePurchase(
  Map<String, MergeOutcome> decisions,
  PurchaseInfo? mine,
  PurchaseInfo? theirs, {
  required bool preferMine,
}) {
  if (mine == null && theirs == null) return null;
  if (mine == null || theirs == null) {
    decisions['purchase'] = MergeOutcome.combined;
    return mine ?? theirs;
  }
  if (mine == theirs) {
    decisions['purchase'] = MergeOutcome.identical;
    return mine;
  }
  decisions['purchase'] = MergeOutcome.byRecency;
  return preferMine ? mine : theirs;
}

Set<T> _union<T>(
  Map<String, MergeOutcome> decisions,
  String field,
  Set<T> mine,
  Set<T> theirs,
) {
  if (mine.length == theirs.length && mine.containsAll(theirs)) {
    decisions[field] = MergeOutcome.identical;
    return mine;
  }
  decisions[field] = MergeOutcome.combined;
  return {...mine, ...theirs};
}
