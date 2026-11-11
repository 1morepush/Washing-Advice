/// Which garments have gone a year without being worn.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 11, 11, 12);
  final aYearAgo = DateTime.utc(2025, 11, 11, 12);

  WardrobeItem item(
    String id, {
    DateTime? added,
    DateTime? lastWorn,
    ItemType type = ItemType.tShirt,
    LifecycleState lifecycle = LifecycleState.active,
  }) {
    final base = buildItem(
      id: id,
      name: id,
      type: type,
      lifecycle: lifecycle,
      usage: UsageStats(
        timesWorn: lastWorn == null ? 0 : 3,
        lastWornAt: lastWorn,
      ),
    );
    // `copyWith` cannot move `addedAt`, which is deliberate for the app and
    // inconvenient here, so it is changed on the way through JSON.
    return WardrobeItem.fromJson({
      ...base.toJson(),
      'addedAt': (added ?? DateTime.utc(2023)).toIso8601String(),
    });
  }

  List<String> ids(
    Iterable<WardrobeItem> items, {
    Map<ItemId, DateTime> kept = const {},
  }) =>
      [
        for (final c in letGoCandidates(items, now: now, keptOn: kept))
          c.item.id.value,
      ];

  group('the twelve-month edge', () {
    test('worn a day over a year ago is a candidate', () {
      expect(
        ids([item('a', lastWorn: aYearAgo.subtract(const Duration(days: 1)))]),
        ['a'],
      );
    });

    test('worn exactly a year ago is still inside the year', () {
      expect(ids([item('a', lastWorn: aYearAgo)]), isEmpty);
    });

    test('worn eleven months ago is not', () {
      expect(ids([item('a', lastWorn: DateTime.utc(2025, 12, 11))]), isEmpty);
    });

    test('added exactly a year ago, never worn, is not yet', () {
      expect(ids([item('a', added: aYearAgo)]), isEmpty);
    });

    test('added a day over a year ago and never worn is', () {
      expect(
          ids([item('a', added: aYearAgo.subtract(const Duration(days: 1)))]), [
        'a',
      ]);
    });

    test('a date missing from the earlier month lands on its last day', () {
      expect(
        monthsBefore(DateTime.utc(2028, 2, 29), 12),
        DateTime.utc(2027, 2, 28),
      );
      expect(
        monthsBefore(DateTime.utc(2026, 8, 31), 6),
        DateTime.utc(2026, 2, 28),
      );
      expect(
        monthsBefore(DateTime.utc(2026, 3, 15), 12),
        DateTime.utc(2025, 3, 15),
      );
    });
  });

  group('never worn', () {
    test('is measured from when it was added', () {
      final result = letGoCandidates([
        item('a', added: DateTime.utc(2024, 6, 1)),
      ], now: now);
      expect(result.single.neverWorn, isTrue);
      expect(result.single.since, DateTime.utc(2024, 6, 1));
    });

    test('a garment bought recently is left alone', () {
      expect(ids([item('a', added: DateTime.utc(2026, 5, 1))]), isEmpty);
    });

    test('an old garment worn last week is not a candidate', () {
      expect(ids([item('a', lastWorn: DateTime.utc(2026, 11, 4))]), isEmpty);
    });

    test('a wear dated before it was added does not age it', () {
      // Added six months ago, with a wear dated long before (an import).
      expect(
        ids([
          item(
            'a',
            added: DateTime.utc(2026, 5, 1),
            lastWorn: DateTime.utc(2024, 1, 1),
          ),
        ]),
        isEmpty,
      );
    });
  });

  group('exclusions', () {
    final old = DateTime.utc(2024, 1, 1);

    test('occasion pieces are left out', () {
      for (final type in occasionTypes) {
        expect(
          ids([item('x', lastWorn: old, type: type)]),
          isEmpty,
          reason: type.label,
        );
      }
    });

    test('a coat is not an occasion piece', () {
      expect(ids([item('c', lastWorn: old, type: ItemType.coat)]), ['c']);
    });

    test('underwear, socks and linen are left out', () {
      for (final type in [
        ItemType.underwear,
        ItemType.bra,
        ItemType.socks,
        ItemType.tights,
        ItemType.bathTowel,
        ItemType.bedSheet,
      ]) {
        expect(
          ids([item('x', lastWorn: old, type: type)]),
          isEmpty,
          reason: type.label,
        );
      }
    });
  });

  group('lifecycle', () {
    final old = DateTime.utc(2024, 1, 1);

    test('active and stored qualify', () {
      expect(
        ids([
          item('a', lastWorn: old),
          item('s', lastWorn: old, lifecycle: LifecycleState.stored),
        ]),
        unorderedEquals(['a', 's']),
      );
    });

    test('everything else does not', () {
      for (final state in LifecycleState.values) {
        if (state == LifecycleState.active || state == LifecycleState.stored) {
          continue;
        }
        expect(
          ids([item('x', lastWorn: old, lifecycle: state)]),
          isEmpty,
          reason: state.name,
        );
      }
    });
  });

  group('ordering', () {
    test('longest unworn first, never worn measured from added', () {
      expect(
        ids([
          item('mid', lastWorn: DateTime.utc(2024, 6, 1)),
          item('never-old', added: DateTime.utc(2022, 1, 1)),
          item('recent', lastWorn: DateTime.utc(2025, 6, 1)),
        ]),
        ['never-old', 'mid', 'recent'],
      );
    });

    test('equal dates fall back to the name', () {
      final day = DateTime.utc(2024, 1, 1);
      expect(ids([item('b', lastWorn: day), item('a', lastWorn: day)]), [
        'a',
        'b',
      ]);
    });

    test('idle is how long since', () {
      final c = letGoCandidates([
        item('a', lastWorn: DateTime.utc(2025, 1, 1, 12)),
      ], now: now)
          .single;
      expect(c.idle.inDays, 679);
    });
  });

  group('Keep', () {
    final old = DateTime.utc(2024, 1, 1);

    test('hides a garment for six months', () {
      final a = item('a', lastWorn: old);
      expect(ids([a], kept: {a.id: DateTime.utc(2026, 8, 1)}), isEmpty);
    });

    test('and brings it back once they have passed', () {
      final a = item('a', lastWorn: old);
      expect(ids([a], kept: {a.id: DateTime.utc(2026, 5, 11, 12)}), ['a']);
      expect(ids([a], kept: {a.id: DateTime.utc(2026, 5, 12)}), isEmpty);
    });

    test('only hides the garment that was kept', () {
      final a = item('a', lastWorn: old);
      final b = item('b', lastWorn: old);
      expect(ids([a, b], kept: {a.id: DateTime.utc(2026, 10, 1)}), ['b']);
    });
  });
}
