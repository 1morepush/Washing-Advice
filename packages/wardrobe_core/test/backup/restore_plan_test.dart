/// What a restore will do: the merge rules, the replace rules, the reminder.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';
import '../support/selling_fixtures.dart';

DateTime day(int d) => DateTime.utc(2026, 6, d);

WardrobeItem item(
  String id, {
  required DateTime at,
  String? name,
  LifecycleState lifecycle = LifecycleState.active,
  UsageStats? usage,
}) =>
    buildItem(
      id: id,
      lifecycle: lifecycle,
      usage: usage ?? const UsageStats(),
    ).copyWith(name: name ?? 'Item $id', updatedAt: at);

Outfit outfit(String id, DateTime at, {String name = 'Outfit'}) => Outfit(
      id: OutfitId(id),
      name: name,
      itemIds: const [ItemId('a'), ItemId('b')],
      occasion: Occasion.everyday,
      createdAt: day(1),
      updatedAt: at,
    );

RestorePlan merge(BackupSnapshot here, BackupSnapshot backup) =>
    planRestore(current: here, incoming: backup, mode: RestoreMode.merge);

void main() {
  group('merge', () {
    test('adds what is missing and touches nothing else', () {
      final here = BackupSnapshot(items: [item('a', at: day(5))]);
      final backup = BackupSnapshot(
        items: [item('b', at: day(1)), item('c', at: day(2))],
      );

      final plan = merge(here, backup);

      expect([for (final i in plan.items) i.id.value], ['b', 'c']);
      expect(plan.itemCounts, const RestoreCounts(added: 2));
      expect(plan.replacesEverything, isFalse);
    });

    test('keeps the newer of two versions of a garment, whichever side', () {
      final here = BackupSnapshot(
        items: [
          item('newer-here', at: day(9), name: 'here'),
          item('newer-there', at: day(2), name: 'here'),
        ],
      );
      final backup = BackupSnapshot(
        items: [
          item('newer-here', at: day(3), name: 'there'),
          item('newer-there', at: day(7), name: 'there'),
        ],
      );

      final plan = merge(here, backup);

      expect([for (final i in plan.items) i.id.value], ['newer-there']);
      expect(plan.items.single.name, 'there');
      expect(
        plan.itemCounts,
        const RestoreCounts(updated: 1, kept: 1),
      );
    });

    test('a tie keeps what is here', () {
      final here = BackupSnapshot(items: [item('a', at: day(4), name: 'here')]);
      final backup = BackupSnapshot(
        items: [item('a', at: day(4), name: 'there')],
      );

      final plan = merge(here, backup);

      expect(plan.items, isEmpty);
      expect(plan.itemCounts.kept, 1);
    });

    test('never deletes: what only exists here is not in the plan', () {
      final here = BackupSnapshot(
        items: [item('only-here', at: day(1))],
        events: [wornEvent('only-here', day(1), id: 'e-here')],
        outfits: [outfit('o-here', day(1))],
        listings: [draftListing(id: 'l-here')],
      );

      final plan = merge(here, const BackupSnapshot());

      expect(plan.items, isEmpty);
      expect(plan.events, isEmpty);
      expect(plan.outfits, isEmpty);
      expect(plan.listings, isEmpty);
      expect(plan.isEmpty, isTrue);
      expect(plan.itemCounts.removed, 0);
      expect(plan.replacesEverything, isFalse);
    });

    test('a deletion made since the backup stays deleted', () {
      final here = BackupSnapshot(
        items: [
          item('a', at: day(9), lifecycle: LifecycleState.removed),
        ],
      );
      final backup = BackupSnapshot(items: [item('a', at: day(2))]);

      expect(merge(here, backup).items, isEmpty);
    });

    test('a deletion in the backup applies when it is newer', () {
      final here = BackupSnapshot(items: [item('a', at: day(2))]);
      final backup = BackupSnapshot(
        items: [item('a', at: day(9), lifecycle: LifecycleState.removed)],
      );

      expect(
          merge(here, backup).items.single.lifecycle, LifecycleState.removed);
    });

    test('unions the history by event id', () {
      final shared = wornEvent('a', day(1), id: 'shared');
      final here = BackupSnapshot(
        items: [item('a', at: day(5))],
        events: [shared, wornEvent('a', day(2), id: 'mine')],
      );
      final backup = BackupSnapshot(
        events: [shared, wornEvent('a', day(3), id: 'theirs')],
      );

      final plan = merge(here, backup);

      expect([for (final e in plan.events) e.id.value], ['theirs']);
      expect(plan.eventCounts, const RestoreCounts(added: 1, kept: 1));
    });

    test('is idempotent: merging the same backup twice adds nothing new', () {
      final backup = BackupSnapshot(
        items: [item('a', at: day(3))],
        events: [wornEvent('a', day(1), id: 'e1')],
        outfits: [outfit('o', day(2))],
        listings: [draftListing(id: 'l', updatedAt: day(2))],
      );
      final first = merge(const BackupSnapshot(), backup);

      final afterFirst = BackupSnapshot(
        items: first.items,
        events: first.events,
        outfits: first.outfits,
        listings: first.listings,
      );
      final second = merge(afterFirst, backup);

      expect(second.isEmpty, isTrue);
    });

    test('rebuilds a garment counters from the union of the history', () {
      final here = BackupSnapshot(
        items: [
          item('a', at: day(8), usage: const UsageStats(timesWorn: 1)),
        ],
        events: [wornEvent('a', day(1), id: 'e1')],
      );
      final backup = BackupSnapshot(
        events: [
          wornEvent('a', day(2), id: 'e2'),
          wornEvent('a', day(3), id: 'e3'),
        ],
      );

      final plan = merge(here, backup);

      final rebuilt = plan.items.single;
      expect(rebuilt.usage.timesWorn, 3);
      // Counters catching up are not an edit, and must not make this copy
      // look newer than it is.
      expect(rebuilt.updatedAt, day(8));
      expect(plan.itemCounts.kept, 0);
    });

    test('leaves counters alone when no events were added', () {
      final here = BackupSnapshot(
        items: [
          item('a', at: day(8), usage: const UsageStats(timesWorn: 5)),
        ],
      );
      expect(merge(here, const BackupSnapshot()).items, isEmpty);
    });

    test('outfits and listings follow the same newer-wins rule', () {
      final here = BackupSnapshot(
        outfits: [
          outfit('keep', day(9), name: 'here'),
          outfit('take', day(1), name: 'here'),
        ],
        listings: [
          draftListing(id: 'keep', title: 'here', updatedAt: day(9)),
          draftListing(id: 'take', title: 'here', updatedAt: day(1)),
        ],
      );
      final backup = BackupSnapshot(
        outfits: [
          outfit('keep', day(2), name: 'there'),
          outfit('take', day(7), name: 'there'),
          outfit('new', day(1)),
        ],
        listings: [
          draftListing(id: 'keep', title: 'there', updatedAt: day(2)),
          draftListing(id: 'take', title: 'there', updatedAt: day(7)),
          draftListing(id: 'new'),
        ],
      );

      final plan = merge(here, backup);

      expect([for (final o in plan.outfits) o.id.value], ['take', 'new']);
      expect(plan.outfitCounts,
          const RestoreCounts(added: 1, updated: 1, kept: 1));
      expect([for (final l in plan.listings) l.id.value], ['take', 'new']);
      expect(plan.listingCounts,
          const RestoreCounts(added: 1, updated: 1, kept: 1));
    });

    test('names only the images of records it will write', () {
      ItemPhoto photo(String uri) => ItemPhoto(
            uri: uri,
            role: PhotoRole.front,
            capturedAt: day(1),
          );
      WardrobeItem withPhoto(String id, String uri, DateTime at) =>
          item(id, at: at).copyWith(photos: PhotoSet([photo(uri)]));

      final here = BackupSnapshot(items: [withPhoto('a', 'here:a', day(9))]);
      final backup = BackupSnapshot(
        items: [
          withPhoto('a', 'there:a', day(2)),
          withPhoto('b', 'there:b', day(2)),
        ],
      );

      expect(merge(here, backup).imageUris, {'there:b'});
    });
  });

  group('replace', () {
    test('writes everything in the backup and says what it clears', () {
      final here = BackupSnapshot(
        items: [item('a', at: day(5)), item('only-here', at: day(5))],
        events: [wornEvent('a', day(1), id: 'e-here')],
        outfits: [outfit('o', day(1))],
        listings: [draftListing(id: 'l-here')],
      );
      final backup = BackupSnapshot(
        items: [item('a', at: day(1)), item('b', at: day(1))],
        events: [
          wornEvent('a', day(1), id: 'e-there'),
          wornEvent('a', day(2), id: 'e-there-2'),
        ],
      );

      final plan = planRestore(
        current: here,
        incoming: backup,
        mode: RestoreMode.replace,
      );

      expect(plan.replacesEverything, isTrue);
      expect(plan.isEmpty, isFalse);
      expect(plan.items, backup.items);
      // The older copy of `a` in the backup wins in a replace: that is the
      // whole difference from a merge.
      expect(plan.items.first.updatedAt, day(1));
      expect(
        plan.itemCounts,
        const RestoreCounts(added: 1, updated: 1, removed: 1),
      );
      expect(plan.eventCounts, const RestoreCounts(added: 2, removed: 1));
      expect(plan.outfitCounts, const RestoreCounts(removed: 1));
      expect(plan.listingCounts, const RestoreCounts(removed: 1));
    });

    test('an empty backup still replaces, and clears', () {
      final plan = planRestore(
        current: BackupSnapshot(items: [item('a', at: day(1))]),
        incoming: const BackupSnapshot(),
        mode: RestoreMode.replace,
      );

      expect(plan.itemCounts.removed, 1);
      expect(plan.isEmpty, isFalse);
    });
  });

  group('re-pointing a plan at stored images', () {
    test('rewrites the records and leaves the counts', () {
      final plan = merge(
        const BackupSnapshot(),
        BackupSnapshot(
          items: [
            item('a', at: day(1)).copyWith(
              photos: PhotoSet([
                ItemPhoto(
                  uri: 'old',
                  role: PhotoRole.front,
                  capturedAt: day(1),
                ),
              ]),
            ),
          ],
        ),
      );

      final moved = plan.withImageUris({'old': 'new'});

      expect(moved.items.single.photos.photos.single.uri, 'new');
      expect(moved.itemCounts, plan.itemCounts);
      expect(moved.mode, plan.mode);
    });
  });

  group('the backup reminder', () {
    final now = DateTime.utc(2026, 11, 11);

    BackupNudge nudge({
      DateTime? last,
      int? atLast,
      int now_ = 10,
    }) =>
        backupNudge(
          lastBackupAt: last,
          garmentsAtLastBackup: atLast,
          garmentsNow: now_,
          now: now,
        );

    test('mentions a wardrobe that has never been backed up', () {
      expect(nudge(), BackupNudge.neverBackedUp);
    });

    test('has nothing to say about an empty wardrobe', () {
      expect(nudge(now_: 0), BackupNudge.none);
    });

    test('stays quiet about a recent backup, even of a wardrobe that grew', () {
      expect(
        nudge(last: now.subtract(const Duration(days: 29)), atLast: 5),
        BackupNudge.none,
      );
    });

    test('mentions an old backup once the wardrobe has grown', () {
      expect(
        nudge(last: now.subtract(const Duration(days: 31)), atLast: 5),
        BackupNudge.outOfDate,
      );
    });

    test('stays quiet about an old backup of a wardrobe that has not grown',
        () {
      final last = now.subtract(const Duration(days: 90));
      expect(nudge(last: last, atLast: 10), BackupNudge.none);
      expect(nudge(last: last, atLast: 12), BackupNudge.none);
    });
  });
}
