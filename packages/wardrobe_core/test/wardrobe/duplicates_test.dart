/// Collapsing the copies of one garment into a single tile.
///
/// The two halves worth pinning pull against each other. Six identical socks
/// must become one tile, or the feature does nothing. And two garments that
/// merely have little known about them must *not* — the items with the least
/// established facts are exactly the ones most likely to be different, so
/// grouping on a shared absence would collapse half a new wardrobe.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 5);

  /// A garment with everything a signature needs, unless a field is cleared.
  WardrobeItem item({
    required String id,
    ItemType type = ItemType.socks,
    String? brand = 'Uniqlo',
    String? size = 'M',
    Map<Fiber, int> composition = const {Fiber.cotton: 100},
    List<String> hexes = const ['#1A1A1E'],
  }) {
    final built = WardrobeItem(
      id: ItemId(id),
      name: id,
      type: Confident(type, confidence: 0.95, source: Provenance.aiInference),
      brand: brand == null ? null : Confident.fromUser(brand),
      sizeLabel: size,
      composition: Confident(
        FabricComposition(composition),
        confidence: 0.95,
        source: Provenance.tagScan,
      ),
      colors: Confident(
        ColorPalette([for (final hex in hexes) ItemColor.fromHex(hex)]),
        confidence: 0.95,
        source: Provenance.aiInference,
      ),
      care: const CareProfile.unknown(),
      addedAt: now,
      updatedAt: now,
    );
    return built.copyWith(care: const CareResolver().forItem(built).profile);
  }

  test('identical copies become one group', () {
    // The whole point. Six tiles saying the same thing crowd out the garment
    // somebody was actually looking for.
    final groups = groupDuplicates([
      for (var i = 0; i < 6; i++) item(id: 'sock-$i'),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.count, 6);
    expect(groups.single.isMultiple, isTrue);
  });

  test('a lone garment is a group of one', () {
    // So the caller renders one kind of thing rather than two.
    final groups = groupDuplicates([item(id: 'only')]);

    expect(groups.single.count, 1);
    expect(groups.single.isMultiple, isFalse);
    expect(groups.single.representative.id, const ItemId('only'));
  });

  test('nothing is lost', () {
    final items = [
      item(id: 'a'),
      item(id: 'b', brand: 'Muji'),
      item(id: 'c'),
      item(id: 'd', size: 'L'),
    ];

    final grouped = [
      for (final group in groupDuplicates(items)) ...group.ids,
    ];

    expect(grouped.toSet(), {for (final i in items) i.id});
    expect(grouped, hasLength(items.length));
  });

  test('the wardrobe order survives', () {
    // Sort order is a user-visible decision — recently added, cost per wear —
    // and a grouping that reordered the list would overrule it. A group sits
    // where its first member sat.
    final groups = groupDuplicates([
      item(id: 'jeans', type: ItemType.jeans),
      item(id: 'sock-1'),
      item(id: 'tee', type: ItemType.tShirt),
      item(id: 'sock-2'),
    ]);

    expect([
      for (final g in groups) g.representative.id.value
    ], [
      'jeans',
      'sock-1',
      'tee',
    ]);
    expect(groups[1].count, 2);
  });

  group('what counts as the same garment', () {
    test('a different brand is a different garment', () {
      final groups = groupDuplicates([
        item(id: 'a'),
        item(id: 'b', brand: 'Muji'),
      ]);

      expect(groups, hasLength(2));
    });

    test('and so is a different size', () {
      final groups = groupDuplicates([
        item(id: 'a'),
        item(id: 'b', size: 'L'),
      ]);

      expect(groups, hasLength(2));
    });

    test('and a different composition', () {
      final groups = groupDuplicates([
        item(id: 'a'),
        item(id: 'b', composition: const {Fiber.wool: 100}),
      ]);

      expect(groups, hasLength(2));
    });

    test('and a different type', () {
      final groups = groupDuplicates([
        item(id: 'a'),
        item(id: 'b', type: ItemType.tShirt),
      ]);

      expect(groups, hasLength(2));
    });

    test('a print is not a plain tee', () {
      // Compared as the whole palette rather than the dominant colour: the
      // print is most of what tells the two apart, and it is the second entry
      // rather than the first.
      final groups = groupDuplicates([
        item(id: 'plain', hexes: const ['#FFFFFF']),
        item(id: 'printed', hexes: const ['#FFFFFF', '#1F2A44']),
      ]);

      expect(groups, hasLength(2));
    });

    test('brand case and spacing do not make a new garment', () {
      final groups = groupDuplicates([
        item(id: 'a', brand: 'Uniqlo'),
        item(id: 'b', brand: '  uniqlo '),
      ]);

      expect(groups, hasLength(1));
    });
  });

  group('silence is not sameness', () {
    test('two unbranded garments are not the same garment', () {
      // The dangerous case. Grouping on a shared absence would collapse a
      // half-built wardrobe into one tile.
      final groups = groupDuplicates([
        item(id: 'a', brand: null),
        item(id: 'b', brand: null),
      ]);

      expect(groups, hasLength(2));
    });

    test('nor two with no size recorded', () {
      final groups = groupDuplicates([
        item(id: 'a', size: null),
        item(id: 'b', size: null),
      ]);

      expect(groups, hasLength(2));
    });

    test('nor two with no composition', () {
      final groups = groupDuplicates([
        item(id: 'a', composition: const {}),
        item(id: 'b', composition: const {}),
      ]);

      expect(groups, hasLength(2));
    });

    test('nor two with no color', () {
      final groups = groupDuplicates([
        item(id: 'a', hexes: const []),
        item(id: 'b', hexes: const []),
      ]);

      expect(groups, hasLength(2));
    });

    test('an ungroupable garment does not swallow a real group', () {
      final groups = groupDuplicates([
        item(id: 'unknown', brand: null),
        item(id: 'sock-1'),
        item(id: 'sock-2'),
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.count, 1);
      expect(groups.last.count, 2);
    });
  });
}
