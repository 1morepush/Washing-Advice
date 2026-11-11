/// Deciding what a restore will change, before it changes anything.
///
/// A pure function from "what is here" and "what the backup has" to "what to
/// write". Nothing in it touches storage, so the rules can be argued about and
/// tested with lists, and the app can show the answer — "adds 12 garments,
/// updates 3" — before anyone commits to it.
///
/// ## Merge
///
/// For a person who wants the backup's contents *and* to keep what they have:
///
/// * **Garments, outfits and listings** are matched by id. Missing here: added.
///   On both sides: the one with the later `updatedAt` wins, whole, and a tie
///   keeps what is here. Present only here: untouched.
/// * **History** is a union by event id. An event is a thing that happened;
///   two copies of the log have both seen real events, and the answer is all
///   of them.
/// * **Nothing is ever deleted.**
///
/// The one place this reads as "deleting" is a garment deleted on one side:
/// that is a *newer version of the garment* (its tombstone), and newest wins
/// like any other. Somebody who deleted a jumper after the backup and merges
/// the backup back in keeps the jumper deleted. To bring it back, replace.
///
/// Wholesale rather than field by field, unlike sync. Sync reconciles two
/// devices that were both being used and each know something the other does
/// not; a backup is an earlier copy of one of them, so "which is newer" is the
/// whole question and a mixture of two moments helps nobody.
///
/// ## Replace
///
/// The wardrobe becomes the backup. Everything here is removed first, then the
/// backup's records written. The plan says how many records that loses so the
/// person can be told before they agree.
///
/// ## Counters
///
/// A garment's usage figures are a projection of the event log. When a merge
/// adds events for a garment, the figures are recomputed from the union —
/// the same rebuild sync does after a pull — so "worn 12 times" stays equal to
/// twelve wears in the history.
library;

import '../events/projections.dart';
import '../events/wardrobe_event.dart';
import '../outfits/model/outfit.dart';
import '../selling/listing.dart';
import '../shared/ids.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'backup_snapshot.dart';

enum RestoreMode {
  /// Add what is missing, keep the newer of two copies, delete nothing.
  merge,

  /// Make the wardrobe exactly the backup.
  replace,
}

/// What a restore does to one kind of record.
final class RestoreCounts {
  const RestoreCounts({
    this.added = 0,
    this.updated = 0,
    this.kept = 0,
    this.removed = 0,
  });

  /// Not here before.
  final int added;

  /// Here already, and the backup's copy replaces it.
  final int updated;

  /// Here already, and what is here stays: the same, or newer.
  final int kept;

  /// Here and not in the backup, removed by a replace. Always zero for merge.
  final int removed;

  /// Whether anything of this kind is written.
  bool get changesAnything => added > 0 || updated > 0 || removed > 0;

  @override
  bool operator ==(Object other) =>
      other is RestoreCounts &&
      other.added == added &&
      other.updated == updated &&
      other.kept == kept &&
      other.removed == removed;

  @override
  int get hashCode => Object.hash(added, updated, kept, removed);

  @override
  String toString() => 'RestoreCounts(+$added ~$updated =$kept -$removed)';
}

/// What a restore will write, and what it will do to what is here.
final class RestorePlan {
  const RestorePlan({
    required this.mode,
    required this.items,
    required this.events,
    required this.outfits,
    required this.listings,
    required this.settings,
    required this.itemCounts,
    required this.eventCounts,
    required this.outfitCounts,
    required this.listingCounts,
  });

  final RestoreMode mode;

  /// Records to write. In a merge only those that win; in a replace, all.
  final List<WardrobeItem> items;
  final List<WardrobeEvent> events;
  final List<Outfit> outfits;
  final List<Listing> listings;

  /// The backup's preferences, to be applied by the app: filling gaps in a
  /// merge, overwriting in a replace.
  final Map<String, Object?> settings;

  final RestoreCounts itemCounts;
  final RestoreCounts eventCounts;
  final RestoreCounts outfitCounts;
  final RestoreCounts listingCounts;

  /// Whether the existing records are cleared before these are written.
  bool get replacesEverything => mode == RestoreMode.replace;

  /// Whether there is nothing to write: a backup this wardrobe already has.
  bool get isEmpty =>
      items.isEmpty &&
      events.isEmpty &&
      outfits.isEmpty &&
      listings.isEmpty &&
      !replacesEverything;

  /// The images the records to be written point at.
  ///
  /// Only these need writing. In a merge, a garment this wardrobe keeps keeps
  /// its own pictures, and writing the backup's over them would put an older
  /// cutout back under a newer record.
  Set<String> get imageUris => BackupSnapshot(
        items: items,
        listings: listings,
      ).imageUris;

  /// The same plan with its records pointing at images where they now are.
  RestorePlan withImageUris(Map<String, String> moved) => RestorePlan(
        mode: mode,
        items: [for (final item in items) item.withImageUris(moved)],
        events: events,
        outfits: outfits,
        listings: [
          for (final listing in listings) listing.withImageUris(moved)
        ],
        settings: settings,
        itemCounts: itemCounts,
        eventCounts: eventCounts,
        outfitCounts: outfitCounts,
        listingCounts: listingCounts,
      );
}

/// Works out what restoring [incoming] onto [current] in [mode] would do.
RestorePlan planRestore({
  required BackupSnapshot current,
  required BackupSnapshot incoming,
  required RestoreMode mode,
}) =>
    switch (mode) {
      RestoreMode.merge => _merge(current, incoming),
      RestoreMode.replace => _replace(current, incoming),
    };

RestorePlan _replace(BackupSnapshot current, BackupSnapshot incoming) {
  RestoreCounts counts(Iterable<String> here, Iterable<String> there) {
    final held = here.toSet();
    final coming = there.toList();
    final shared = coming.where(held.contains).length;
    return RestoreCounts(
      added: coming.length - shared,
      updated: shared,
      removed: held.length - shared,
    );
  }

  return RestorePlan(
    mode: RestoreMode.replace,
    items: incoming.items,
    events: incoming.events,
    outfits: incoming.outfits,
    listings: incoming.listings,
    settings: incoming.settings,
    itemCounts: counts(
      current.items.map((i) => i.id.value),
      incoming.items.map((i) => i.id.value),
    ),
    eventCounts: counts(
      current.events.map((e) => e.id.value),
      incoming.events.map((e) => e.id.value),
    ),
    outfitCounts: counts(
      current.outfits.map((o) => o.id.value),
      incoming.outfits.map((o) => o.id.value),
    ),
    listingCounts: counts(
      current.listings.map((l) => l.id.value),
      incoming.listings.map((l) => l.id.value),
    ),
  );
}

RestorePlan _merge(BackupSnapshot current, BackupSnapshot incoming) {
  // Events first: the garments' counters are rebuilt from the union.
  final held = {for (final e in current.events) e.id};
  final newEvents = <WardrobeEvent>[];
  for (final event in incoming.events) {
    if (held.add(event.id)) newEvents.add(event);
  }

  final here = {for (final i in current.items) i.id: i};
  final winners = <ItemId, WardrobeItem>{};
  var itemsAdded = 0;
  var itemsUpdated = 0;
  var itemsKept = 0;
  for (final item in incoming.items) {
    final mine = here[item.id];
    if (mine == null) {
      winners[item.id] = item;
      itemsAdded++;
    } else if (item.updatedAt.isAfter(mine.updatedAt)) {
      winners[item.id] = item;
      itemsUpdated++;
    } else {
      itemsKept++;
    }
  }

  if (newEvents.isNotEmpty) {
    final byItem = <ItemId, List<WardrobeEvent>>{};
    for (final event in [...current.events, ...newEvents]) {
      byItem.putIfAbsent(event.itemId, () => []).add(event);
    }
    for (final id in {for (final e in newEvents) e.itemId}) {
      final base = winners[id] ?? here[id];
      if (base == null) continue;
      final rebuilt = UsageProjection.forItem(id, byItem[id]!);
      // Not a change the person made, so `updatedAt` is left alone: a counter
      // catching up with the history must not make this copy look newer than
      // another that is genuinely so.
      if (rebuilt != base.usage) winners[id] = base.copyWith(usage: rebuilt);
    }
  }

  final outfits = <Outfit>[];
  final outfitHere = {for (final o in current.outfits) o.id: o};
  var outfitsUpdated = 0;
  var outfitsKept = 0;
  for (final outfit in incoming.outfits) {
    final mine = outfitHere[outfit.id];
    if (mine == null) {
      outfits.add(outfit);
    } else if (outfit.updatedAt.isAfter(mine.updatedAt)) {
      outfits.add(outfit);
      outfitsUpdated++;
    } else {
      outfitsKept++;
    }
  }

  final listings = <Listing>[];
  final listingHere = {for (final l in current.listings) l.id: l};
  var listingsUpdated = 0;
  var listingsKept = 0;
  for (final listing in incoming.listings) {
    final mine = listingHere[listing.id];
    if (mine == null) {
      listings.add(listing);
    } else if (listing.updatedAt.isAfter(mine.updatedAt)) {
      listings.add(listing);
      listingsUpdated++;
    } else {
      listingsKept++;
    }
  }

  return RestorePlan(
    mode: RestoreMode.merge,
    items: winners.values.toList(),
    events: newEvents,
    outfits: outfits,
    listings: listings,
    settings: incoming.settings,
    itemCounts: RestoreCounts(
      added: itemsAdded,
      updated: itemsUpdated,
      kept: itemsKept,
    ),
    eventCounts: RestoreCounts(
      added: newEvents.length,
      kept: incoming.events.length - newEvents.length,
    ),
    outfitCounts: RestoreCounts(
      added: outfits.length - outfitsUpdated,
      updated: outfitsUpdated,
      kept: outfitsKept,
    ),
    listingCounts: RestoreCounts(
      added: listings.length - listingsUpdated,
      updated: listingsUpdated,
      kept: listingsKept,
    ),
  );
}
