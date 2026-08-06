/// Learning what goes with what from wear history.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final monday = DateTime.utc(2026, 8, 3, 9);

  var counter = 0;
  ItemWorn worn(String item, DateTime at) => ItemWorn(
      id: EventId('e${counter++}'), itemId: ItemId(item), occurredAt: at);

  /// [items] worn together on [day] days, each a week apart.
  List<ItemWorn> together(List<String> items, {required int days}) => [
        for (var week = 0; week < days; week++)
          for (final item in items)
            worn(item, monday.add(Duration(days: 7 * week))),
      ];

  double? strengthBetween(RelationshipGraph graph, String x, String y) {
    for (final edge in graph.edges) {
      if (edge.involves(ItemId(x)) && edge.involves(ItemId(y))) {
        return edge.strength;
      }
    }
    return null;
  }

  test('an empty log yields an empty graph', () {
    expect(CoWearProjection.graphFrom(const []).isEmpty, isTrue);
  });

  test('one coincidence is not a pattern', () {
    // The asymmetry that sets the threshold: a missing edge slightly weakens a
    // suggestion, a spurious one actively promotes a bad pairing.
    final graph = CoWearProjection.graphFrom(
      together(['shirt', 'trousers'], days: 1),
    );
    expect(graph.isEmpty, isTrue);
  });

  test('a repeated pairing becomes an edge', () {
    final graph = CoWearProjection.graphFrom(
      together(['shirt', 'trousers'], days: 3),
    );

    expect(graph.neighbours(const ItemId('shirt')), {
      const ItemId('trousers'),
    });
    expect(graph.edges.single.kind, RelationKind.wornWith);
    // Strong, but short of certain: three observations is a habit, not a law.
    expect(graph.edges.single.strength, closeTo(0.75, 0.001));
  });

  test('more evidence for the same rate is believed more', () {
    // A bare hit rate cannot tell two observations from twenty — both are
    // 100%. Only one of them is a habit.
    final twice = CoWearProjection.graphFrom(
      together(['shirt', 'trousers'], days: 2),
    ).edges.single.strength;
    final twenty = CoWearProjection.graphFrom(
      together(['shirt', 'trousers'], days: 20),
    ).edges.single.strength;

    expect(twice, lessThan(twenty));
    expect(twenty, lessThan(1.0));
  });

  test('strength is conditional on the rarer garment', () {
    // A garment worn every day would otherwise look strongly linked to
    // everything simply by being present. The interesting signal is "these two
    // go together", not "this one is worn a lot".
    final events = [
      ...together(['jeans', 'blazer'], days: 2),
      // The jeans go out four more times without the blazer.
      for (var i = 1; i <= 4; i++)
        worn('jeans', monday.add(Duration(days: 100 + i))),
    ];

    // The claim is that the jeans' own frequency does not dilute the edge, so
    // it is tested directly: the same pairing, with and without the solo
    // wears, must score the same.
    final withSoloWears = CoWearProjection.graphFrom(events);
    final withoutSoloWears = CoWearProjection.graphFrom(
      together(['jeans', 'blazer'], days: 2),
    );

    expect(
      strengthBetween(withSoloWears, 'jeans', 'blazer'),
      strengthBetween(withoutSoloWears, 'jeans', 'blazer'),
    );
  });

  test('a weaker habit scores lower than a stronger one', () {
    final events = [
      ...together(['shirt', 'chinos'], days: 4),
      // The shirt goes out with jeans occasionally too.
      ...together(['shirt', 'jeans'], days: 2)
          .map((e) =>
              worn(e.itemId.value, e.occurredAt.add(const Duration(days: 60))))
          .toList(),
    ];

    final graph = CoWearProjection.graphFrom(events);

    final chinos = strengthBetween(graph, 'shirt', 'chinos')!;
    final jeans = strengthBetween(graph, 'shirt', 'jeans')!;
    expect(chinos, greaterThan(jeans));
  });

  group('what counts as one occasion', () {
    test('wears logged in a batch are one outfit', () {
      // Someone opens the app in the evening and taps four things.
      final events = [
        for (var week = 0; week < 2; week++) ...[
          worn('shirt', monday.add(Duration(days: 7 * week))),
          worn(
            'trousers',
            monday.add(Duration(days: 7 * week, minutes: 3)),
          ),
        ],
      ];

      expect(CoWearProjection.graphFrom(events).edges, hasLength(1));
    });

    test('wears days apart are not', () {
      final events = [
        for (var week = 0; week < 3; week++) ...[
          worn('shirt', monday.add(Duration(days: 7 * week))),
          worn('trousers', monday.add(Duration(days: 7 * week + 2))),
        ],
      ];

      expect(CoWearProjection.graphFrom(events).isEmpty, isTrue);
    });

    test('a chain of small gaps does not merge a fortnight into one outfit',
        () {
      // The window is measured from the start of a run, not between
      // consecutive events, precisely so this cannot happen.
      final events = [
        for (var i = 0; i < 20; i++)
          worn('item-$i', monday.add(Duration(hours: 11 * i))),
      ];

      final graph = CoWearProjection.graphFrom(events);
      // Nothing recurs, so nothing is believed — and certainly not the twenty
      // items being one outfit.
      expect(graph.isEmpty, isTrue);
    });

    test('the same item twice in one run counts once', () {
      // A duplicate tap must not make a pair look twice as strong.
      final events = [
        for (var week = 0; week < 2; week++) ...[
          worn('shirt', monday.add(Duration(days: 7 * week))),
          worn('shirt', monday.add(Duration(days: 7 * week, minutes: 1))),
          worn('trousers', monday.add(Duration(days: 7 * week, minutes: 2))),
        ],
      ];

      // Asserted against the same history without the duplicate rather than
      // against a number, which is the claim being made.
      final deduplicated = CoWearProjection.graphFrom(
        together(['shirt', 'trousers'], days: 2),
      );
      expect(
        CoWearProjection.graphFrom(events).edges.single.strength,
        deduplicated.edges.single.strength,
      );
    });
  });

  test('a retrospectively logged wear still lands in its own occasion', () {
    // Events arrive in the order they were entered; what matters is when they
    // happened.
    final events = [
      worn('shirt', monday),
      worn('trousers', monday.add(const Duration(days: 7))),
      worn('trousers', monday.add(const Duration(minutes: 5))),
      worn('shirt', monday.add(const Duration(days: 7, minutes: 5))),
    ];

    expect(CoWearProjection.graphFrom(events).edges, hasLength(1));
  });

  test('the same history always produces the same graph', () {
    // Otherwise suggestions reshuffle between launches on identical data,
    // which looks broken.
    final events = [
      ...together(['a', 'b', 'c'], days: 3),
      ...together(['d', 'e'], days: 4),
    ];

    final first = CoWearProjection.graphFrom(events);
    final second = CoWearProjection.graphFrom(events.reversed.toList());

    expect(
      [for (final e in first.edges) e.toJson()],
      [for (final e in second.edges) e.toJson()],
    );
  });

  test('the graph feeds the builder that had nothing to learn from', () {
    // The point of the whole projection: what the app recorded now changes
    // what it suggests.
    final events = together(['tee-b', 'jeans'], days: 3);
    final graph = CoWearProjection.graphFrom(events);

    final wardrobe = [
      _item('tee-a', ItemType.tShirt),
      _item('tee-b', ItemType.tShirt),
      _item('jeans', ItemType.jeans),
    ];

    final learned = OutfitBuilder(
      relationships: graph,
      clock: FixedClock(DateTime.utc(2026, 9, 1)),
    ).suggest(wardrobe, const OutfitRequest(includeFootwear: false));

    expect(learned.first.itemIds.map((i) => i.value), contains('tee-b'));
    expect(learned.first.reasons, contains(contains('worn these together')));
  });
}

WardrobeItem _item(String id, ItemType type) => WardrobeItem(
      id: ItemId(id),
      name: id,
      type: Confident(type, confidence: 0.9, source: Provenance.aiInference),
      composition: Confident(
        FabricComposition(const {Fiber.cotton: 100}),
        confidence: 0.9,
        source: Provenance.tagScan,
      ),
      colors: Confident(
        ColorPalette([ItemColor.fromHex('#3C3F44')]),
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      care: const CareProfile.unknown(),
      usage: const UsageStats(timesWorn: 5),
      addedAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
