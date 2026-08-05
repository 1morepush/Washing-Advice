/// The contract every `EventLog` must satisfy.
///
/// Written against the interface so the app's Drift implementation can be
/// dropped into `runEventLogContractTests` and held to the same behaviour.
/// That matters more here than almost anywhere else: the in-memory log was
/// *not* idempotent while the Drift one was, and nothing caught it until the
/// sync engine counted a re-delivered wear twice. Two implementations of one
/// interface quietly disagreeing is precisely what a shared suite prevents.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

/// Builds a fresh, empty log.
typedef EventLogFactory = Future<EventLog> Function();

void main() {
  runEventLogContractTests(
    'InMemoryEventLog',
    () async => InMemoryEventLog(),
  );
}

void runEventLogContractTests(String name, EventLogFactory create) {
  final monday = DateTime.utc(2026, 8, 3);
  final tuesday = DateTime.utc(2026, 8, 4);
  final wednesday = DateTime.utc(2026, 8, 5);

  ItemWorn worn(String id, DateTime at, {String item = 'a'}) =>
      ItemWorn(id: EventId(id), itemId: ItemId(item), occurredAt: at);

  group('$name: appending', () {
    late EventLog log;

    setUp(() async => log = await create());

    test('an event can be read back', () async {
      await log.append(worn('e1', monday));
      expect(await log.all(), hasLength(1));
    });

    test('several at once', () async {
      await log.appendAll([worn('e1', monday), worn('e2', tuesday)]);
      expect(await log.all(), hasLength(2));
    });

    test('the same event twice is recorded once', () async {
      // The property sync rests on. A run that fails after pulling re-pulls
      // the same events next time, and a log that counted them twice would
      // inflate a garment's wear history with every dropped connection.
      await log.append(worn('e1', monday));
      await log.append(worn('e1', monday));

      expect(await log.all(), hasLength(1));
    });

    test('a batch containing one already held adds only the new', () async {
      await log.append(worn('e1', monday));
      await log.appendAll([worn('e1', monday), worn('e2', tuesday)]);

      expect(await log.all(), hasLength(2));
    });

    test('an empty batch is not an error', () async {
      await log.appendAll(const []);
      expect(await log.all(), isEmpty);
    });
  });

  group('$name: reading', () {
    late EventLog log;

    setUp(() async {
      log = await create();
      await log.appendAll([
        worn('c', wednesday),
        worn('a', monday),
        worn('b', tuesday),
        worn('other', tuesday, item: 'b'),
      ]);
    });

    test('everything comes back oldest first', () async {
      // Ordered by when things happened, not by when they were recorded —
      // people log yesterday's wash this morning.
      //
      // Asserted as "non-decreasing" rather than as a fixed id sequence,
      // because two of these events share a timestamp and nothing promises an
      // order between them. Pinning one would be testing an implementation
      // detail that either log is free to change.
      final times = [for (final event in await log.all()) event.occurredAt];
      for (var i = 1; i < times.length; i++) {
        expect(times[i].isBefore(times[i - 1]), isFalse);
      }
      expect(times.first, monday);
      expect(times.last, wednesday);
    });

    test('one item at a time', () async {
      final forB = await log.forItem(const ItemId('b'));
      expect(forB, hasLength(1));
      expect(forB.single.id.value, 'other');
    });

    test('an item with no history is empty rather than an error', () async {
      expect(await log.forItem(const ItemId('nope')), isEmpty);
    });

    test('a window, for syncing', () async {
      final since = await log.all(since: tuesday);
      expect([for (final e in since) e.id.value], isNot(contains('a')));

      final until = await log.all(until: tuesday);
      expect([for (final e in until) e.id.value], isNot(contains('c')));
    });
  });

  group('$name: replay', () {
    test('reproduces the counters the app caches', () async {
      // The guarantee that makes the log worth keeping: the counters on an
      // item are a cache, and a cache that cannot be regenerated is just data
      // waiting to go wrong.
      final log = await create();
      await log.appendAll([
        worn('w1', monday),
        worn('w2', tuesday),
        ItemWashed(
          id: const EventId('wash'),
          itemId: const ItemId('a'),
          occurredAt: wednesday,
          record: LaundryRecord(washedAt: wednesday),
        ),
      ]);

      final usage = UsageProjection.forItem(
        const ItemId('a'),
        await log.forItem(const ItemId('a')),
      );

      expect(usage.timesWorn, 2);
      expect(usage.timesWashed, 1);
      expect(usage.wearsSinceWash, 0);
    });
  });
}
