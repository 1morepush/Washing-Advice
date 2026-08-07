import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

void main() {
  final hoodie = ItemId('hoodie');
  final jeans = ItemId('jeans');

  DateTime day(int n) => DateTime.utc(2026, 1, n);

  group('UsageProjection', () {
    test('counts wears and washes', () {
      final events = [
        wornEvent('hoodie', day(1)),
        wornEvent('hoodie', day(2)),
        washedEvent('hoodie', day(3)),
        wornEvent('hoodie', day(4)),
      ];
      final stats = UsageProjection.forItem(hoodie, events);
      expect(stats.timesWorn, 3);
      expect(stats.timesWashed, 1);
      expect(stats.lastWornAt, day(4));
      expect(stats.lastWashedAt, day(3));
      expect(stats.firstWornAt, day(1));
    });

    test('a wash resets the wears-since-wash counter', () {
      final events = [
        wornEvent('hoodie', day(1)),
        wornEvent('hoodie', day(2)),
        washedEvent('hoodie', day(3)),
        wornEvent('hoodie', day(4)),
      ];
      expect(UsageProjection.forItem(hoodie, events).wearsSinceWash, 1);
    });

    test('ignores events belonging to other items', () {
      final events = [
        wornEvent('hoodie', day(1)),
        wornEvent('jeans', day(2)),
        wornEvent('jeans', day(3)),
      ];
      expect(UsageProjection.forItem(hoodie, events).timesWorn, 1);
      expect(UsageProjection.forItem(jeans, events).timesWorn, 2);
    });

    test('folds by when things happened, not the order they were recorded', () {
      // Someone logs yesterday's wash this morning, after logging today's wear.
      // The wash still has to land first, or wearsSinceWash is wrong.
      final asRecorded = [
        wornEvent('hoodie', day(5), id: 'w2'),
        washedEvent('hoodie', day(4), id: 'x1'),
        wornEvent('hoodie', day(3), id: 'w1'),
      ];
      final stats = UsageProjection.forItem(hoodie, asRecorded);
      expect(stats.wearsSinceWash, 1);
      expect(stats.timesWorn, 2);
    });

    test('an item with no events has empty stats', () {
      expect(
          UsageProjection.forItem(hoodie, const []), const UsageStats.none());
    });

    test('projects every item in one pass', () {
      final events = [
        wornEvent('hoodie', day(1)),
        wornEvent('jeans', day(2)),
      ];
      final all = UsageProjection.forAll(events);
      expect(all.keys.map((k) => k.value).toSet(), {'hoodie', 'jeans'});
    });
  });

  group('replay reproduces cached counters', () {
    // The integrity guarantee that makes it safe to cache counters on the item:
    // the log is the source of truth, and the cache must always be derivable
    // from it. If this ever fails, the cache is repairable by replaying.
    test('an item built from replay matches its stored stats', () {
      final events = <WardrobeEvent>[
        ItemAdded(
          id: const EventId('add'),
          itemId: hoodie,
          occurredAt: day(1),
        ),
        wornEvent('hoodie', day(2)),
        wornEvent('hoodie', day(3)),
        washedEvent('hoodie', day(4)),
        wornEvent('hoodie', day(5)),
        wornEvent('hoodie', day(6)),
      ];

      final replayed = UsageProjection.forItem(hoodie, events);
      final item = buildItem(id: 'hoodie', usage: replayed);

      expect(item.usage, replayed);
      expect(item.usage.timesWorn, 4);
      expect(item.usage.timesWashed, 1);
      expect(item.usage.wearsSinceWash, 2);
    });

    test('replaying twice gives the same answer', () {
      final events = [
        wornEvent('hoodie', day(1)),
        washedEvent('hoodie', day(2)),
        wornEvent('hoodie', day(3)),
      ];
      expect(
        UsageProjection.forItem(hoodie, events),
        UsageProjection.forItem(hoodie, events),
      );
    });

    test('replaying a shuffled log gives the same answer', () {
      final events = [
        wornEvent('hoodie', day(1), id: 'a'),
        washedEvent('hoodie', day(2), id: 'b'),
        wornEvent('hoodie', day(3), id: 'c'),
        wornEvent('hoodie', day(4), id: 'd'),
      ];
      expect(
        UsageProjection.forItem(hoodie, events.reversed),
        UsageProjection.forItem(hoodie, events),
      );
    });
  });

  group('LifecycleProjection', () {
    test('tracks state through the item\'s life', () {
      final events = <WardrobeEvent>[
        ItemAdded(id: const EventId('a'), itemId: hoodie, occurredAt: day(1)),
        LifecycleChanged(
          id: const EventId('b'),
          itemId: hoodie,
          occurredAt: day(2),
          to: LifecycleState.stored,
        ),
        LifecycleChanged(
          id: const EventId('c'),
          itemId: hoodie,
          occurredAt: day(3),
          to: LifecycleState.donated,
        ),
      ];
      expect(
          LifecycleProjection.forItem(hoodie, events), LifecycleState.donated);
    });

    test('returns null for an item with no history', () {
      expect(LifecycleProjection.forItem(hoodie, const []), isNull);
    });
  });

  group('LaundryHistoryProjection', () {
    test('returns washes oldest first', () {
      final events = [
        washedEvent('hoodie', day(5), id: 'b', temperatureC: 40),
        washedEvent('hoodie', day(1), id: 'a', temperatureC: 30),
      ];
      final history = LaundryHistoryProjection.forItem(hoodie, events);
      expect(history.map((r) => r.temperatureC), [30, 40]);
    });

    test('computes the average interval between washes', () {
      final events = [
        washedEvent('hoodie', day(1), id: 'a'),
        washedEvent('hoodie', day(11), id: 'b'),
        washedEvent('hoodie', day(21), id: 'c'),
      ];
      expect(
        LaundryHistoryProjection.averageIntervalFor(hoodie, events),
        const Duration(days: 10),
      );
    });

    test('cannot compute an interval from a single wash', () {
      expect(
        LaundryHistoryProjection.averageIntervalFor(
          hoodie,
          [washedEvent('hoodie', day(1))],
        ),
        isNull,
      );
    });

    test('counts washes hotter than the item should have had', () {
      // The evidence behind "this shrank because it was washed too hot".
      final events = [
        washedEvent('hoodie', day(1), id: 'a', temperatureC: 30),
        washedEvent('hoodie', day(2), id: 'b', temperatureC: 60),
        washedEvent('hoodie', day(3), id: 'c', temperatureC: 40),
      ];
      expect(
        LaundryHistoryProjection.washesAbove(hoodie, events, maxTempC: 30),
        2,
      );
    });
  });

  group('WardrobeAnalytics', () {
    final events = <WardrobeEvent>[
      ItemPurchased(
        id: const EventId('p1'),
        itemId: hoodie,
        occurredAt: day(1),
        purchase: const PurchaseInfo(
          priceMinorUnits: 8000,
          currencyCode: 'USD',
        ),
      ),
      for (var i = 2; i <= 11; i++) wornEvent('hoodie', day(i), id: 'w$i'),
      wornEvent('jeans', day(2), id: 'j1'),
    ];

    test('ranks the most worn items', () {
      final ranked = WardrobeAnalytics.mostWorn(events);
      expect(ranked.first.itemId, hoodie);
      expect(ranked.first.timesWorn, 10);
    });

    test('computes cost per wear', () {
      expect(WardrobeAnalytics.costPerWear(hoodie, events), closeTo(8.0, 1e-9));
    });

    test('cost per wear is null without a recorded price', () {
      expect(WardrobeAnalytics.costPerWear(jeans, events), isNull);
    });

    test('finds items owned but never worn', () {
      final never = WardrobeAnalytics.neverWorn(
        [hoodie, jeans, const ItemId('unworn')],
        events,
      );
      expect(never.map((i) => i.value), ['unworn']);
    });

    test('totals spend per currency without inventing an exchange rate', () {
      final mixed = <WardrobeEvent>[
        ...events,
        ItemPurchased(
          id: const EventId('p2'),
          itemId: jeans,
          occurredAt: day(1),
          purchase: const PurchaseInfo(
            priceMinorUnits: 5000,
            currencyCode: 'EUR',
          ),
        ),
      ];
      expect(WardrobeAnalytics.totalSpend(mixed), {'USD': 8000, 'EUR': 5000});
    });
  });

  group('InMemoryEventLog', () {
    test('keeps events ordered by when they occurred', () async {
      final log = InMemoryEventLog();
      await log.append(wornEvent('hoodie', day(5), id: 'b'));
      await log.append(wornEvent('hoodie', day(1), id: 'a'));

      final all = await log.all();
      expect(all.map((e) => e.id.value), ['a', 'b']);
    });

    test('filters by item', () async {
      final log = InMemoryEventLog([
        wornEvent('hoodie', day(1)),
        wornEvent('jeans', day(2)),
      ]);
      expect(await log.forItem(jeans), hasLength(1));
    });

    test('filters by date range', () async {
      final log = InMemoryEventLog([
        wornEvent('hoodie', day(1), id: 'a'),
        wornEvent('hoodie', day(10), id: 'b'),
        wornEvent('hoodie', day(20), id: 'c'),
      ]);
      final window = await log.all(since: day(5), until: day(15));
      expect(window.map((e) => e.id.value), ['b']);
    });
  });

  group('event serialisation', () {
    test('every event type survives a round trip', () {
      final events = <WardrobeEvent>[
        ItemPurchased(
          id: const EventId('p'),
          itemId: hoodie,
          occurredAt: day(1),
          purchase: const PurchaseInfo(
            priceMinorUnits: 4999,
            currencyCode: 'GBP',
            retailer: 'Shop',
          ),
        ),
        ItemAdded(id: const EventId('a'), itemId: hoodie, occurredAt: day(2)),
        ItemWorn(
          id: const EventId('w'),
          itemId: hoodie,
          occurredAt: day(3),
          occasion: 'work',
        ),
        washedEvent('hoodie', day(4), id: 'x', temperatureC: 30),
        ItemRepaired(
          id: const EventId('r'),
          itemId: hoodie,
          occurredAt: day(5),
          description: 'new zip',
        ),
        ConditionObserved(
          id: const EventId('c'),
          itemId: hoodie,
          occurredAt: day(6),
          observation: WearObservation(
            type: WearType.pilling,
            severity: WearSeverity.moderate,
            observedAt: day(6),
          ),
        ),
        LifecycleChanged(
          id: const EventId('l'),
          itemId: hoodie,
          occurredAt: day(7),
          to: LifecycleState.stored,
        ),
      ];

      for (final event in events) {
        final restored = WardrobeEvent.fromJson(event.toJson());
        expect(restored, event, reason: event.typeName);
        expect(restored.runtimeType, event.runtimeType);
        expect(restored.toJson(), event.toJson());
      }
    });

    test('rejects an unrecognised event type', () {
      expect(
        () => WardrobeEvent.fromJson({
          'type': 'teleported',
          'id': 'x',
          'itemId': 'y',
          'occurredAt': day(1).toIso8601String(),
        }),
        throwsFormatException,
      );
    });
  });
}
