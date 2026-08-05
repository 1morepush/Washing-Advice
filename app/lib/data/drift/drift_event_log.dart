/// [EventLog] over Drift.
///
/// The events table is append-only and has no update or delete path, which is
/// the point: the log is the source of truth and `WardrobeItem.usage` is a
/// cache of it. If a counter is ever wrong it is repaired by replaying these
/// rows, so a row that could be edited would destroy the only thing that makes
/// that repair possible.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'database.dart';

class DriftEventLog implements EventLog {
  DriftEventLog(this._db);

  final AppDatabase _db;

  @override
  Future<void> append(WardrobeEvent event) => _db
      .into(_db.events)
      .insert(_rowFor(event), mode: InsertMode.insertOrIgnore);

  @override
  Future<void> appendAll(Iterable<WardrobeEvent> events) => _db.batch((batch) {
    batch.insertAll(
      _db.events,
      [for (final event in events) _rowFor(event)],
      // An event id is deterministic for a given happening, so a retry
      // after a dropped connection must not double-count a wash.
      mode: InsertMode.insertOrIgnore,
    );
  });

  @override
  Future<List<WardrobeEvent>> forItem(ItemId itemId) async {
    final rows =
        await (_db.select(_db.events)
              ..where((t) => t.itemId.equals(itemId.value))
              ..orderBy([(t) => OrderingTerm(expression: t.occurredAt)]))
            .get();
    return [for (final row in rows) _eventFrom(row)];
  }

  @override
  Future<List<WardrobeEvent>> all({DateTime? since, DateTime? until}) async {
    final select = _db.select(_db.events)
      ..orderBy([(t) => OrderingTerm(expression: t.occurredAt)]);

    if (since != null) {
      select.where((t) => t.occurredAt.isBiggerOrEqualValue(since));
    }
    if (until != null) {
      select.where((t) => t.occurredAt.isSmallerThanValue(until));
    }

    final rows = await select.get();
    return [for (final row in rows) _eventFrom(row)];
  }

  EventsCompanion _rowFor(WardrobeEvent event) => EventsCompanion.insert(
    id: event.id.value,
    itemId: event.itemId.value,
    occurredAt: event.occurredAt,
    payload: jsonEncode(event.toJson()),
  );

  WardrobeEvent _eventFrom(Event row) =>
      WardrobeEvent.fromJson(jsonDecode(row.payload) as Map<String, Object?>);
}
