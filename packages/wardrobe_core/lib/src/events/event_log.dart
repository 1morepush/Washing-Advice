/// Storage for the event history.
library;

import '../shared/ids.dart';
import 'wardrobe_event.dart';

/// An append-only log of wardrobe events.
///
/// Append-only on purpose: correcting history by rewriting it destroys the
/// audit trail that makes the log worth keeping. A mistaken wear is corrected
/// by recording a compensating event, not by deleting the original.
/// Appending is **idempotent by [WardrobeEvent.id]**. Recording an event the
/// log already holds does nothing, and every implementation must honour that.
/// Sync depends on it: a run that fails after pulling re-pulls the same events
/// next time, and a log that counted them twice would inflate a garment's wear
/// history a little more with every dropped connection.
abstract interface class EventLog {
  /// Records an event, unless one with the same id is already held.
  Future<void> append(WardrobeEvent event);

  /// Records several events atomically, skipping any already held.
  Future<void> appendAll(Iterable<WardrobeEvent> events);

  /// Every event for one item, oldest first.
  Future<List<WardrobeEvent>> forItem(ItemId itemId);

  /// Events, optionally windowed, oldest first.
  ///
  /// [since] and [until] filter on `occurredAt` — when things happened —
  /// which is what a history view wants. [recordedSince] filters on
  /// `recordedAt` instead, which is what *sync* wants: a wear logged today for
  /// yesterday must be sent even though it happened before the last sync.
  /// Using `occurredAt` for that silently strands retrospective entries on the
  /// device that made them.
  ///
  /// [types] keeps only events whose `typeName` is listed, so a reader that
  /// folds one kind of event (the co-wear graph wants wears and nothing else)
  /// does not pull every wash and condition report through the store to
  /// throw them away.
  Future<List<WardrobeEvent>> all({
    DateTime? since,
    DateTime? until,
    DateTime? recordedSince,
    Set<String>? types,
  });
}

/// An in-memory log, for tests and for the offline-first path before a database
/// is wired up.
final class InMemoryEventLog implements EventLog {
  InMemoryEventLog([Iterable<WardrobeEvent> initial = const []])
      : _events = [...initial] {
    _ids.addAll(_events.map((event) => event.id));
    _sort();
  }

  final List<WardrobeEvent> _events;

  /// Ids already held, so appending is idempotent without a linear scan.
  final Set<EventId> _ids = {};

  int get length => _events.length;

  @override
  Future<void> append(WardrobeEvent event) async {
    if (!_ids.add(event.id)) return;
    _events.add(event);
    _sort();
  }

  @override
  Future<void> appendAll(Iterable<WardrobeEvent> events) async {
    var added = false;
    for (final event in events) {
      if (!_ids.add(event.id)) continue;
      _events.add(event);
      added = true;
    }
    if (added) _sort();
  }

  @override
  Future<List<WardrobeEvent>> forItem(ItemId itemId) async => [
        for (final event in _events)
          if (event.itemId == itemId) event
      ];

  @override
  Future<List<WardrobeEvent>> all({
    DateTime? since,
    DateTime? until,
    DateTime? recordedSince,
    Set<String>? types,
  }) async =>
      [
        for (final event in _events)
          if ((types == null || types.contains(event.typeName)) &&
              (since == null || !event.occurredAt.isBefore(since)) &&
              (until == null || !event.occurredAt.isAfter(until)) &&
              (recordedSince == null ||
                  !event.recordedAt.isBefore(recordedSince)))
            event,
      ];

  /// Sorted by when things happened, not when they were recorded, so a wash
  /// logged the morning after still folds in before today's wear.
  void _sort() => _events.sort((x, y) => x.occurredAt.compareTo(y.occurredAt));
}
