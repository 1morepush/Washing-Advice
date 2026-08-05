/// Storage for the wardrobe.
///
/// The core defines what storage must do; it has no opinion on how. The app
/// implements this over Drift and SQLite, a test implements it over a list, and
/// a future sync layer wraps it — none of which the domain needs to know.
///
/// Also included is an in-memory implementation. It is not only a test double:
/// it holds the *semantics* of every filter in one readable place, so the Drift
/// implementation has something to be checked against. A query that behaves
/// differently in SQL than it does here is a bug in the SQL, and the shared
/// test suite in `test/wardrobe/repository_test.dart` runs against both.
library;

import '../events/event_log.dart';
import '../events/projections.dart';
import '../events/wardrobe_event.dart';
import '../shared/ids.dart';
import 'model/wardrobe_item.dart';
import 'query.dart';

/// Reads and writes wardrobe items.
abstract interface class WardrobeRepository {
  /// One item, or null when nothing has that id.
  Future<WardrobeItem?> byId(ItemId id);

  /// Every item matching [query], ordered and paged as it asks.
  Future<List<WardrobeItem>> query(WardrobeQuery query);

  /// How many items match, ignoring [WardrobeQuery.limit] and
  /// [WardrobeQuery.offset] — for "42 items" above a paged list.
  Future<int> count(WardrobeQuery query);

  /// Inserts or replaces.
  Future<void> save(WardrobeItem item);

  /// Inserts or replaces several at once.
  ///
  /// Separate from [save] because a pile scan produces a dozen items in one
  /// go, and a storage layer can make that one transaction.
  Future<void> saveAll(Iterable<WardrobeItem> items);

  /// Removes an item entirely.
  ///
  /// Rarely the right operation — an item the user no longer owns should move
  /// to a terminal [LifecycleState] instead, which keeps it out of the wardrobe
  /// while preserving its history for cost-per-wear and statistics. This exists
  /// for genuine mistakes, like an item scanned twice.
  Future<void> delete(ItemId id);

  /// Results for [query], re-emitted whenever they change.
  ///
  /// The wardrobe screen watches rather than polls, so saving an item after a
  /// scan makes it appear without anyone having to remember to refresh.
  Stream<List<WardrobeItem>> watch(WardrobeQuery query);

  /// Every brand present in the wardrobe, for building a filter list.
  Future<List<String>> knownBrands();
}

/// Keeps cached usage counters in step with the event log.
///
/// `WardrobeItem.usage` is a projection of events, so appending an event and
/// leaving the item alone would make the cache stale. This pairs the two.
///
/// Deliberately a separate interface rather than methods on the repository:
/// wardrobe storage and event history are different concerns with different
/// implementations, and only the code recording an event needs both.
final class WardrobeRecorder {
  const WardrobeRecorder({required this.items, required this.events});

  final WardrobeRepository items;
  final EventLog events;

  /// Appends [event] and refreshes the affected item's cached counters.
  ///
  /// Returns the updated item, or null if the event refers to one that is not
  /// in the wardrobe — which is not an error, since events outlive items.
  Future<WardrobeItem?> record(WardrobeEvent event) async {
    await events.append(event);

    final item = await items.byId(event.itemId);
    if (item == null) return null;

    final refreshed = item.copyWith(
      usage: UsageProjection.forItem(
        event.itemId,
        await events.forItem(event.itemId),
      ),
      updatedAt: event.occurredAt,
    );
    await items.save(refreshed);
    return refreshed;
  }
}
