import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 5);
  final clock = FixedClock(now);

  WardrobeItem item(
    String id, {
    required ItemType type,
    String hex = '#3C3F44',
    UsageStats usage = const UsageStats(timesWorn: 5),
    Set<Season> seasons = const {},
    Set<String> tags = const {},
    bool favorite = false,
    LifecycleState lifecycle = LifecycleState.active,
  }) =>
      WardrobeItem(
        id: ItemId(id),
        name: id,
        type: Confident(type, confidence: 0.9, source: Provenance.aiInference),
        composition: Confident(
          FabricComposition(const {Fiber.cotton: 100}),
          confidence: 0.9,
          source: Provenance.tagScan,
        ),
        colors: Confident(
          ColorPalette([ItemColor.fromHex(hex)]),
          confidence: 0.9,
          source: Provenance.aiInference,
        ),
        care: const CareProfile.unknown(),
        usage: usage,
        seasons: seasons,
        tags: tags,
        isFavorite: favorite,
        lifecycle: lifecycle,
        addedAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  final builder = OutfitBuilder(clock: clock);

  const noShoes = OutfitRequest(includeFootwear: false);

  group('what gets into a suggestion', () {
    test('an outfit needs both halves, or a one-piece', () {
      final tops = [item('tee', type: ItemType.tShirt)];
      expect(builder.suggest(tops, noShoes), isEmpty);

      final dressed = builder.suggest([
        item('dress', type: ItemType.dress),
      ], noShoes);
      expect(dressed.single.items.single.id.value, 'dress');
    });

    test('a dress is a complete base on its own', () {
      // Not a top with a missing bottom, which is why OutfitSlot has a
      // one-piece value at all.
      final suggestions = builder.suggest([
        item('dress', type: ItemType.dress),
        item('tee', type: ItemType.tShirt),
        item('jeans', type: ItemType.jeans),
      ], noShoes);

      final sizes = suggestions.map((s) => s.items.length).toSet();
      expect(sizes, containsAll([1, 2]));
    });

    test('an item in the wash is not offered', () {
      // A hard filter, not a penalty: it is not available at any score.
      final suggestions = builder.suggest([
        item('tee', type: ItemType.tShirt, lifecycle: LifecycleState.inLaundry),
        item('jeans', type: ItemType.jeans),
      ], noShoes);

      expect(suggestions, isEmpty);
    });

    test('the wrong season is filtered out, not merely down-ranked', () {
      final suggestions = builder.suggest([
        item('shorts', type: ItemType.shorts, seasons: {Season.summer}),
        item('tee', type: ItemType.tShirt),
      ], const OutfitRequest(season: Season.winter, includeFootwear: false));

      expect(suggestions, isEmpty);
    });

    test('an item with no stated season suits every season', () {
      // Absent is not the same as "never" — the same distinction the care
      // model draws about unstated instructions.
      final suggestions = builder.suggest([
        item('tee', type: ItemType.tShirt),
        item('jeans', type: ItemType.jeans),
      ], const OutfitRequest(season: Season.winter, includeFootwear: false));

      expect(suggestions, isNotEmpty);
    });

    test('excluded items are left out', () {
      final suggestions = builder.suggest(
          [
            item('tee', type: ItemType.tShirt),
            item('jeans', type: ItemType.jeans),
          ],
          OutfitRequest(
            includeFootwear: false,
            exclude: {const ItemId('jeans')},
          ));

      expect(suggestions, isEmpty);
    });
  });

  group('occasion', () {
    test('a hoodie is not offered for a formal occasion', () {
      final suggestions = builder.suggest(
          [
            item('hoodie', type: ItemType.hoodie),
            item('trousers', type: ItemType.trousers),
          ],
          const OutfitRequest(
            occasion: Occasion.formal,
            includeFootwear: false,
          ));

      expect(suggestions, isEmpty);
    });

    test('a tag overrides the default, because workplaces differ', () {
      // The escape hatch: occasion fit is taste, not a fact about the garment.
      final suggestions = builder.suggest([
        item('hoodie', type: ItemType.hoodie, tags: {'work'}),
        item('trousers', type: ItemType.trousers),
      ], const OutfitRequest(occasion: Occasion.work, includeFootwear: false));

      expect(suggestions, isNotEmpty);
    });
  });

  group('ranking', () {
    test('surfaces clothes that have been forgotten', () {
      // The reason the feature exists. Someone who wanted their three
      // most-worn items would not need an app to find them.
      final suggestions = builder.suggest([
        item(
          'worn-yesterday',
          type: ItemType.tShirt,
          usage: UsageStats(
            timesWorn: 40,
            lastWornAt: now.subtract(const Duration(days: 1)),
          ),
        ),
        item(
          'forgotten',
          type: ItemType.tShirt,
          usage: UsageStats(
            timesWorn: 2,
            lastWornAt: now.subtract(const Duration(days: 300)),
          ),
        ),
        item('jeans', type: ItemType.jeans),
      ], noShoes);

      expect(
          suggestions.first.itemIds.map((i) => i.value), contains('forgotten'));
    });

    test('colour harmony outweighs individual desirability', () {
      // A clashing pair of favourites should still lose to a pair that works.
      final suggestions = builder.suggest([
        item('red-tee', type: ItemType.tShirt, hex: '#C62828', favorite: true),
        item('cream-tee', type: ItemType.tShirt, hex: '#F2E8D5'),
        item('green-trousers', type: ItemType.trousers, hex: '#2E7D32'),
      ], noShoes);

      expect(
          suggestions.first.itemIds.map((i) => i.value), contains('cream-tee'));
    });

    test('recorded links nudge, but do not dictate', () {
      final graph = RelationshipGraph([
        const ItemRelationship(
          from: ItemId('tee-a'),
          to: ItemId('jeans'),
          kind: RelationKind.pairsWith,
        ),
      ]);
      final linked = OutfitBuilder(clock: clock, relationships: graph);

      final wardrobe = [
        item('tee-a', type: ItemType.tShirt),
        item('tee-b', type: ItemType.tShirt),
        item('jeans', type: ItemType.jeans),
      ];

      final withGraph = linked.suggest(wardrobe, noShoes);
      final withoutGraph = builder.suggest(wardrobe, noShoes);

      expect(withGraph.first.itemIds.map((i) => i.value), contains('tee-a'));
      // Both alternatives are still offered — the builder proposes outfits,
      // it does not just replay the ones already recorded.
      expect(withGraph, hasLength(withoutGraph.length));
    });
  });

  group('anchoring on one item', () {
    test('every suggestion contains it', () {
      final suggestions = builder.suggest(
          [
            item('skirt', type: ItemType.skirt),
            item('jeans', type: ItemType.jeans),
            item('tee', type: ItemType.tShirt),
            item('blouse', type: ItemType.blouse),
          ],
          const OutfitRequest(
            mustInclude: ItemId('skirt'),
            includeFootwear: false,
          ));

      expect(suggestions, isNotEmpty);
      for (final suggestion in suggestions) {
        expect(suggestion.itemIds.map((i) => i.value), contains('skirt'));
      }
    });

    test('an item that plays no part in an outfit anchors nothing', () {
      final suggestions = builder.suggest(
          [
            item('socks', type: ItemType.socks),
            item('tee', type: ItemType.tShirt),
            item('jeans', type: ItemType.jeans),
          ],
          const OutfitRequest(
            mustInclude: ItemId('socks'),
            includeFootwear: false,
          ));

      expect(suggestions, isEmpty);
    });
  });

  group('layers and shoes', () {
    test('are added only when asked for', () {
      final wardrobe = [
        item('tee', type: ItemType.tShirt),
        item('jeans', type: ItemType.jeans),
        item('jacket', type: ItemType.jacket),
        item('sneakers', type: ItemType.sneakers),
      ];

      expect(builder.suggest(wardrobe, noShoes).first.items, hasLength(2));
      expect(
        builder.suggest(wardrobe, const OutfitRequest()).first.items,
        hasLength(3),
      );
      expect(
        builder
            .suggest(wardrobe, const OutfitRequest(includeOuterwear: true))
            .first
            .items,
        hasLength(4),
      );
    });

    test('a request for a layer with none available still suggests', () {
      // Returning nothing because the user owns no jacket would be worse than
      // returning the outfit without one.
      final suggestions = builder.suggest([
        item('tee', type: ItemType.tShirt),
        item('jeans', type: ItemType.jeans),
      ], const OutfitRequest(includeOuterwear: true, includeFootwear: false));

      expect(suggestions.first.items, hasLength(2));
    });
  });

  group('output', () {
    test('never repeats the same combination', () {
      final suggestions = builder.suggest([
        item('tee', type: ItemType.tShirt),
        item('shirt', type: ItemType.dressShirt),
        item('jeans', type: ItemType.jeans),
        item('chinos', type: ItemType.chinos),
      ], noShoes);

      final signatures = suggestions.map((s) => s.signature).toSet();
      expect(signatures, hasLength(suggestions.length));
    });

    test('honours the requested count', () {
      final wardrobe = [
        for (var i = 0; i < 6; i++) item('top-$i', type: ItemType.tShirt),
        for (var i = 0; i < 6; i++) item('bottom-$i', type: ItemType.jeans),
      ];

      expect(
        builder.suggest(
          wardrobe,
          const OutfitRequest(count: 3, includeFootwear: false),
        ),
        hasLength(3),
      );
    });

    test('stays bounded however large the wardrobe is', () {
      // The shortlist is what makes this tractable: 200 items must not become
      // a combinatorial explosion.
      final wardrobe = [
        for (var i = 0; i < 100; i++) item('top-$i', type: ItemType.tShirt),
        for (var i = 0; i < 100; i++) item('bottom-$i', type: ItemType.jeans),
      ];

      final suggestions = builder.suggest(
        wardrobe,
        const OutfitRequest(count: 50, includeFootwear: false),
      );
      // Four shortlisted tops against four bottoms, and no more.
      expect(suggestions, hasLength(16));
    });

    test('explains itself', () {
      final suggestions = builder.suggest([
        item('tee', type: ItemType.tShirt, usage: const UsageStats.none()),
        item('jeans', type: ItemType.jeans),
      ], noShoes);

      expect(suggestions.first.reasons, contains(contains('never been worn')));
    });
  });
}
