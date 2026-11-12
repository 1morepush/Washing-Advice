/// The outfit calendar's projection: which garments fell on which day.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

void main() {
  var counter = 0;
  ItemWorn worn(String item, DateTime at) => ItemWorn(
        id: EventId('e${counter++}'),
        itemId: ItemId(item),
        occurredAt: at,
      );

  /// California in winter: the evening is already tomorrow in UTC.
  DateTime pacific(DateTime instant) =>
      instant.toUtc().subtract(const Duration(hours: 8));

  final tee = buildItem(id: 'tee', name: 'Tee');
  final jeans = buildItem(id: 'jeans', name: 'Jeans', type: ItemType.jeans);

  group('grouping by day', () {
    test('an empty log is an empty calendar', () {
      final calendar = WearCalendar.fromEvents(const []);
      expect(calendar.isEmpty, isTrue);
      expect(calendar.firstDay, isNull);
      expect(calendar.inMonth(2026, 3), isEmpty);
    });

    test('wears the same local day are one day, in the order logged', () {
      final calendar = WearCalendar.fromEvents(
        [
          worn('jeans', DateTime.utc(2026, 3, 4, 12, 5)),
          worn('tee', DateTime.utc(2026, 3, 4, 12, 0)),
        ],
        items: [tee, jeans],
        toLocal: (t) => t.toUtc(),
      );

      final day = calendar.on(const CalendarDate(2026, 3, 4))!;
      expect([for (final p in day.pieces) p.itemId.value], ['tee', 'jeans']);
    });

    test('the day is the local one, across midnight UTC', () {
      // 23:30 on the 4th in California is 07:30 on the 5th in UTC.
      final evening = DateTime.utc(2026, 3, 5, 7, 30);
      final byUtc = WearCalendar.fromEvents(
        [worn('tee', evening)],
        items: [tee],
        toLocal: (t) => t.toUtc(),
      );
      final byPacific = WearCalendar.fromEvents(
        [worn('tee', evening)],
        items: [tee],
        toLocal: pacific,
      );

      expect(byUtc.on(const CalendarDate(2026, 3, 5)), isNotNull);
      expect(byPacific.on(const CalendarDate(2026, 3, 5)), isNull);
      expect(byPacific.on(const CalendarDate(2026, 3, 4)), isNotNull);
    });

    test('a zone ahead of UTC moves a morning wear back a day the other way',
        () {
      final tokyo = DateTime.utc(2026, 3, 4, 20); // 05:00 on the 5th in JST
      final calendar = WearCalendar.fromEvents(
        [worn('tee', tokyo)],
        items: [tee],
        toLocal: (t) => t.toUtc().add(const Duration(hours: 9)),
      );
      expect(calendar.on(const CalendarDate(2026, 3, 5)), isNotNull);
      expect(calendar.on(const CalendarDate(2026, 3, 4)), isNull);
    });

    test('the same garment twice in a day is one piece, worn twice', () {
      final calendar = WearCalendar.fromEvents(
        [
          worn('tee', DateTime.utc(2026, 3, 4, 8)),
          worn('tee', DateTime.utc(2026, 3, 4, 18)),
        ],
        items: [tee],
        toLocal: (t) => t.toUtc(),
      );
      final pieces = calendar.on(const CalendarDate(2026, 3, 4))!.pieces;
      expect(pieces, hasLength(1));
      expect(pieces.single.times, 2);
    });

    test('events that are not wears are ignored', () {
      final calendar = WearCalendar.fromEvents(
        [
          ItemWashed(
            id: const EventId('w'),
            itemId: const ItemId('tee'),
            occurredAt: DateTime.utc(2026, 3, 4),
            record: LaundryRecord(washedAt: DateTime.utc(2026, 3, 4)),
          ),
        ],
        items: [tee],
      );
      expect(calendar.isEmpty, isTrue);
    });

    test('input order does not matter', () {
      final calendar = WearCalendar.fromEvents(
        [
          worn('jeans', DateTime.utc(2026, 3, 4, 19)),
          worn('tee', DateTime.utc(2026, 3, 4, 7)),
        ],
        items: [tee, jeans],
        toLocal: (t) => t.toUtc(),
      );
      final pieces = calendar.on(const CalendarDate(2026, 3, 4))!.pieces;
      expect(pieces.first.itemId.value, 'tee');
    });
  });

  group('garments since deleted', () {
    test('an id the wardrobe does not hold keeps the day, marked missing', () {
      final calendar = WearCalendar.fromEvents(
        [
          worn('tee', DateTime.utc(2026, 3, 4, 8)),
          worn('gone', DateTime.utc(2026, 3, 4, 9)),
        ],
        items: [tee],
        toLocal: (t) => t.toUtc(),
      );
      final day = calendar.on(const CalendarDate(2026, 3, 4))!;
      expect(day.pieces, hasLength(2));
      expect(day.missingCount, 1);
      expect(day.present.single.itemId.value, 'tee');
      expect(day.pieces.last.isMissing, isTrue);
    });

    test('a tombstoned garment is missing too', () {
      final removed = buildItem(
        id: 'tee',
        lifecycle: LifecycleState.removed,
      );
      final calendar = WearCalendar.fromEvents(
        [worn('tee', DateTime.utc(2026, 3, 4))],
        items: [removed],
        toLocal: (t) => t.toUtc(),
      );
      expect(calendar.on(const CalendarDate(2026, 3, 4))!.missingCount, 1);
    });

    test('a sold garment is still on the day it was worn', () {
      final sold = buildItem(id: 'tee', lifecycle: LifecycleState.sold);
      final calendar = WearCalendar.fromEvents(
        [worn('tee', DateTime.utc(2026, 3, 4))],
        items: [sold],
        toLocal: (t) => t.toUtc(),
      );
      expect(calendar.on(const CalendarDate(2026, 3, 4))!.missingCount, 0);
    });
  });

  group('months', () {
    final events = [
      worn('tee', DateTime.utc(2026, 2, 28, 12)),
      worn('tee', DateTime.utc(2026, 3, 1, 12)),
      worn('jeans', DateTime.utc(2026, 3, 1, 12)),
      worn('tee', DateTime.utc(2026, 3, 31, 12)),
      worn('tee', DateTime.utc(2026, 4, 1, 12)),
    ];
    final calendar = WearCalendar.fromEvents(
      events,
      items: [tee, jeans],
      toLocal: (t) => t.toUtc(),
    );

    test('month boundaries are respected, in date order', () {
      expect(
        [for (final d in calendar.inMonth(2026, 3)) d.date.toString()],
        ['2026-03-01', '2026-03-31'],
      );
      expect(calendar.inMonth(2026, 2), hasLength(1));
      expect(calendar.firstDay, const CalendarDate(2026, 2, 28));
    });

    test('the same month in another year is another month', () {
      expect(calendar.inMonth(2025, 3), isEmpty);
    });

    test('the summary counts days and names the piece worn on most', () {
      final summary = calendar.summaryFor(2026, 3);
      expect(summary.daysLogged, 2);
      expect(summary.mostWorn?.id.value, 'tee');
      expect(summary.mostWornDays, 2);
    });

    test('no favourite when everything was worn once', () {
      final summary = calendar.summaryFor(2026, 2);
      expect(summary.daysLogged, 1);
      expect(summary.mostWorn, isNull);
    });

    test('a deleted garment is never the named favourite', () {
      final c = WearCalendar.fromEvents(
        [
          worn('gone', DateTime.utc(2026, 3, 1)),
          worn('gone', DateTime.utc(2026, 3, 2)),
          worn('gone', DateTime.utc(2026, 3, 3)),
          worn('tee', DateTime.utc(2026, 3, 1)),
          worn('tee', DateTime.utc(2026, 3, 2)),
        ],
        items: [tee],
        toLocal: (t) => t.toUtc(),
      );
      expect(c.summaryFor(2026, 3).mostWorn?.id.value, 'tee');
    });

    test('a tie is settled the same way whatever order days arrive in', () {
      final a = WearCalendar.fromEvents(
        [
          worn('tee', DateTime.utc(2026, 3, 1)),
          worn('jeans', DateTime.utc(2026, 3, 1)),
          worn('tee', DateTime.utc(2026, 3, 2)),
          worn('jeans', DateTime.utc(2026, 3, 2)),
        ],
        items: [tee, jeans],
        toLocal: (t) => t.toUtc(),
      );
      expect(a.summaryFor(2026, 3).mostWorn?.id.value, 'jeans');
    });
  });

  group('CalendarDate', () {
    test('next crosses month and year ends, and leap days', () {
      expect(
          const CalendarDate(2026, 1, 31).next, const CalendarDate(2026, 2, 1));
      expect(const CalendarDate(2026, 12, 31).next,
          const CalendarDate(2027, 1, 1));
      expect(const CalendarDate(2028, 2, 28).next,
          const CalendarDate(2028, 2, 29));
    });

    test('daysIn and weekday', () {
      expect(CalendarDate.daysIn(2028, 2), 29);
      expect(CalendarDate.daysIn(2026, 2), 28);
      expect(CalendarDate.daysIn(2026, 12), 31);
      // 4 March 2026 was a Wednesday.
      expect(const CalendarDate(2026, 3, 4).weekday, DateTime.wednesday);
    });

    test('compares and prints as ISO', () {
      expect(const CalendarDate(2026, 3, 4).toString(), '2026-03-04');
      expect(
        const CalendarDate(2026, 3, 4).isBefore(const CalendarDate(2026, 3, 5)),
        isTrue,
      );
    });
  });
}
