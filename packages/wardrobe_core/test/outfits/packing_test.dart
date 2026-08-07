import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  const planner = PackingPlanner();

  WardrobeItem item(
    String id, {
    required ItemType type,
    String hex = '#3C3F44',
    Set<Season> seasons = const {},
    Set<String> tags = const {},
    CareProfile? care,
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
        care: care ??
            const CareProfile(
              instructions: CareInstructions.conservative(),
              source: Provenance.tagScan,
              confidence: 0.95,
            ),
        seasons: seasons,
        tags: tags,
        lifecycle: lifecycle,
        addedAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  /// A wardrobe with plenty of everything, so quota arithmetic is what is
  /// being measured rather than scarcity.
  List<WardrobeItem> stocked() => [
        for (var i = 0; i < 20; i++) item('top-$i', type: ItemType.tShirt),
        for (var i = 0; i < 8; i++) item('jeans-$i', type: ItemType.jeans),
        for (var i = 0; i < 20; i++) item('pants-$i', type: ItemType.underwear),
        for (var i = 0; i < 20; i++) item('socks-$i', type: ItemType.socks),
        item('pyjamas', type: ItemType.pajamas),
        item('jacket', type: ItemType.jacket),
        item('sneakers', type: ItemType.sneakers),
      ];

  int countOf(PackingList list, ItemCategory category) =>
      list.items.where((p) => p.category == category).length;

  group('quantities', () {
    test('a top for every day when there is no laundry', () {
      final list = planner.plan(stocked(), const TripSpec(days: 5));
      expect(countOf(list, ItemCategory.top), 5);
    });

    test('underwear is a day each plus a spare', () {
      final list = planner.plan(stocked(), const TripSpec(days: 5));
      expect(countOf(list, ItemCategory.underwear), 6);
      expect(countOf(list, ItemCategory.legwear), 6);
    });

    test('bottoms are worn more than once between washes', () {
      // The reason a week away does not need seven pairs of trousers.
      final list = planner.plan(stocked(), const TripSpec(days: 6));
      expect(countOf(list, ItemCategory.bottom), 2);
    });

    test('laundry mid-trip caps every quota at the wash interval', () {
      // The whole point of doing a wash on a trip, and the difference between
      // a carry-on and a hold bag.
      final long = planner.plan(stocked(), const TripSpec(days: 14));
      final washing = planner.plan(
        stocked(),
        const TripSpec(days: 14, laundryAvailable: true, washEveryDays: 4),
      );

      expect(countOf(long, ItemCategory.top), 14);
      expect(countOf(washing, ItemCategory.top), 5);
      expect(washing.count, lessThan(long.count));
    });

    test('laundry cannot make a short trip need more than it does', () {
      final list = planner.plan(
        stocked(),
        const TripSpec(days: 2, laundryAvailable: true, washEveryDays: 7),
      );
      expect(countOf(list, ItemCategory.top), 2);
    });

    test('a second kind of day earns a second pair of shoes', () {
      // Shoes are the heaviest thing in any bag, so the bar for a second pair
      // is that the trip genuinely has two kinds of day in it.
      final oneKind = planner.plan(stocked(), const TripSpec(days: 4));
      expect(countOf(oneKind, ItemCategory.footwear), 1);

      final wardrobe = [
        ...stocked(),
        item('brogues', type: ItemType.dressShoes),
        item('shirt', type: ItemType.dressShirt),
      ];
      final twoKinds = planner.plan(
        wardrobe,
        const TripSpec(
            days: 4, occasions: {Occasion.everyday, Occasion.formal}),
      );
      expect(countOf(twoKinds, ItemCategory.footwear), 2);
    });

    test('shoes that suit no part of the trip are a gap, not a filler', () {
      // Trainers on a work-and-black-tie trip are not a second pair of shoes,
      // they are the wrong shoes. Saying so beats packing them.
      final list = planner.plan(
        [...stocked(), item('shirt', type: ItemType.dressShirt)],
        const TripSpec(days: 4, occasions: {Occasion.work, Occasion.formal}),
      );

      expect(countOf(list, ItemCategory.footwear), 0);
      expect(
        list.gaps.map((g) => g.category),
        contains(ItemCategory.footwear),
      );
    });

    test('sleepwear only once the trip is worth packing it for', () {
      expect(
        countOf(
          planner.plan(stocked(), const TripSpec(days: 1)),
          ItemCategory.sleepwear,
        ),
        0,
      );
      expect(
        countOf(
          planner.plan(stocked(), const TripSpec(days: 4)),
          ItemCategory.sleepwear,
        ),
        1,
      );
    });
  });

  group('choosing between candidates', () {
    test('neutrals are preferred, because they go with more of the bag', () {
      final wardrobe = [
        item('loud', type: ItemType.tShirt, hex: '#E8710A'),
        item('navy', type: ItemType.tShirt, hex: '#1F2A44'),
        item('jeans', type: ItemType.jeans),
        item('pants', type: ItemType.underwear),
        item('socks', type: ItemType.socks),
      ];

      final list = planner.plan(wardrobe, const TripSpec(days: 1));
      final tops = list.items.where((p) => p.category == ItemCategory.top);
      expect(tops.single.item.id.value, 'navy');
    });

    test('hand-wash-only loses out when laundry is in the plan', () {
      // The one place the care model changes what goes in the bag.
      final handWash = item(
        'silk',
        type: ItemType.blouse,
        hex: '#1F2A44',
        care: CareProfile(
          instructions: const CareInstructions.conservative().copyWith(
            wash: const WashCare(method: WashMethod.hand, maxTempC: 30),
          ),
          source: Provenance.tagScan,
          confidence: 0.95,
        ),
      );
      final wardrobe = [
        handWash,
        item('cotton', type: ItemType.blouse, hex: '#1F2A44'),
        item('jeans', type: ItemType.jeans),
      ];

      final list = planner.plan(
        wardrobe,
        const TripSpec(days: 1, laundryAvailable: true),
      );
      final tops = list.items.where((p) => p.category == ItemCategory.top);
      expect(tops.single.item.id.value, 'cotton');
    });

    test('nothing is packed twice', () {
      final list = planner.plan(stocked(), const TripSpec(days: 7));
      final ids = list.items.map((p) => p.item.id.value).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('items in the wash stay at home', () {
      final wardrobe = [
        for (var i = 0; i < 3; i++)
          item(
            'top-$i',
            type: ItemType.tShirt,
            lifecycle: LifecycleState.inLaundry,
          ),
        item('jeans', type: ItemType.jeans),
      ];

      final list = planner.plan(wardrobe, const TripSpec(days: 2));
      expect(countOf(list, ItemCategory.top), 0);
    });
  });

  group('filtering', () {
    test('the wrong season is left behind', () {
      final wardrobe = [
        item('shorts', type: ItemType.shorts, seasons: {Season.summer}),
        item('trousers', type: ItemType.trousers, seasons: {Season.winter}),
      ];

      final list = planner.plan(
        wardrobe,
        const TripSpec(days: 2, season: Season.winter),
      );
      final bottoms = list.items.where(
        (p) => p.category == ItemCategory.bottom,
      );
      expect(bottoms.single.item.id.value, 'trousers');
    });

    test('underwear needs no occasion, because every trip needs it', () {
      // It would otherwise have to be tagged for every occasion in the list,
      // which is bookkeeping for no benefit.
      final wardrobe = [
        item('pants', type: ItemType.underwear),
        item('socks', type: ItemType.socks),
      ];

      final list = planner.plan(
        wardrobe,
        const TripSpec(days: 2, occasions: {Occasion.formal}),
      );
      expect(countOf(list, ItemCategory.underwear), 1);
    });
  });

  group('gaps', () {
    test('a shortfall is reported, not silently padded over', () {
      // A short packing list that looks complete is how people arrive
      // somewhere without socks.
      final wardrobe = [
        item('top', type: ItemType.tShirt),
        item('jeans', type: ItemType.jeans),
      ];

      final list = planner.plan(wardrobe, const TripSpec(days: 4));

      expect(list.isComplete, isFalse);
      final tops = list.gaps.firstWhere(
        (g) => g.category == ItemCategory.top,
      );
      expect(tops.wanted, 4);
      expect(tops.found, 1);
      expect(tops.missing, 3);

      final socks = list.gaps.firstWhere(
        (g) => g.category == ItemCategory.legwear,
      );
      expect(socks.found, 0);
      expect(socks.message, contains('Nothing in the wardrobe'));
    });

    test('a fully stocked wardrobe reports none', () {
      final list = planner.plan(stocked(), const TripSpec(days: 3));
      expect(list.gaps, isEmpty);
      expect(list.isComplete, isTrue);
    });
  });

  group('what happens to the clothes while you are away', () {
    test('hand-wash items are called out when laundry is planned', () {
      final wardrobe = [
        item('jeans', type: ItemType.jeans),
        item(
          'silk',
          type: ItemType.blouse,
          care: CareProfile(
            instructions: const CareInstructions.conservative().copyWith(
              wash: const WashCare(method: WashMethod.hand, maxTempC: 30),
            ),
            source: Provenance.tagScan,
            confidence: 0.95,
          ),
        ),
      ];

      final list = planner.plan(
        wardrobe,
        const TripSpec(days: 14, laundryAvailable: true),
      );

      expect(list.notes, contains(contains('hand washing')));
    });

    test('a bag spanning several colour piles needs several washes', () {
      final wardrobe = [
        item('white-tee', type: ItemType.tShirt, hex: '#F7F6F2'),
        item('black-tee', type: ItemType.tShirt, hex: '#111114'),
        item('red-tee', type: ItemType.tShirt, hex: '#C62828'),
        item('jeans', type: ItemType.jeans, hex: '#1F2A44'),
        for (var i = 0; i < 6; i++) item('pants-$i', type: ItemType.underwear),
        for (var i = 0; i < 6; i++) item('socks-$i', type: ItemType.socks),
      ];

      final list = planner.plan(
        wardrobe,
        const TripSpec(days: 3, laundryAvailable: true),
      );

      expect(list.notes, contains(contains('separate loads')));
    });

    test('a long trip with no laundry says so plainly', () {
      final list = planner.plan(stocked(), const TripSpec(days: 10));
      expect(list.notes, contains(contains('No laundry planned')));
    });

    test('unconfirmed care labels are flagged as guesses', () {
      // Packing advice built on an inferred label is worth having and worth
      // labelling as inferred.
      final wardrobe = [
        item('mystery',
            type: ItemType.tShirt, care: const CareProfile.unknown()),
        item('jeans', type: ItemType.jeans),
      ];

      final list = planner.plan(wardrobe, const TripSpec(days: 1));
      expect(list.notes, contains(contains('no confirmed care label')));
    });
  });

  test('weight is estimated for comparing two bags', () {
    final short = planner.plan(stocked(), const TripSpec(days: 2));
    final long = planner.plan(stocked(), const TripSpec(days: 10));

    expect(long.estimatedWeightGrams, greaterThan(short.estimatedWeightGrams));
    expect(short.estimatedWeightGrams, greaterThan(0));
  });
}
