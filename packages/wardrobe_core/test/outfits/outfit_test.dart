import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 5);

  Outfit outfit({
    Iterable<ItemId> items = const [ItemId('tee'), ItemId('jeans')],
    Set<Season> seasons = const {},
  }) =>
      Outfit(
        id: const OutfitId('o1'),
        name: 'Saturday',
        itemIds: items,
        seasons: seasons,
        createdAt: now,
        updatedAt: now,
      );

  group('slots', () {
    test('activewear resolves by type, because it spans both halves', () {
      // The reason the lookup is not simply a map over ItemCategory.
      expect(OutfitSlot.ofType(ItemType.activewearTop), OutfitSlot.top);
      expect(OutfitSlot.ofType(ItemType.activewearBottom), OutfitSlot.bottom);
    });

    test('things that are worn but not styled fill no slot', () {
      for (final type in [
        ItemType.underwear,
        ItemType.socks,
        ItemType.bathTowel,
        ItemType.swimwear,
      ]) {
        expect(OutfitSlot.ofType(type), isNull, reason: '$type');
      }
    });
  });

  group('seasons', () {
    test('an unstated season means any, not none', () {
      // Absent is not a negative answer — the same distinction the care model
      // draws about instructions a label leaves out.
      final any = outfit();
      for (final season in Season.values) {
        expect(any.suitsSeason(season), isTrue);
      }
    });

    test('a stated season excludes the others', () {
      final summer = outfit(seasons: {Season.summer});
      expect(summer.suitsSeason(Season.summer), isTrue);
      expect(summer.suitsSeason(Season.winter), isFalse);
    });
  });

  test('removing an item leaves the rest of the outfit intact', () {
    // What happens when a garment is deleted: the outfit narrows rather than
    // disappearing or holding a dangling reference.
    final reduced = outfit().without(const ItemId('tee'));
    expect(reduced.itemIds, [const ItemId('jeans')]);
    expect(reduced.id, const OutfitId('o1'));
  });

  group('serialisation', () {
    test('round-trips', () {
      final original = outfit(seasons: {Season.summer, Season.spring}).copyWith(
        isFavorite: true,
        notes: 'the good jeans',
        usage: const UsageStats(timesWorn: 3),
      );

      final restored = Outfit.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      expect(restored.itemIds, original.itemIds);
      expect(restored.usage.timesWorn, 3);
      expect(restored.notes, 'the good jeans');
    });

    test('seasons encode in a stable order', () {
      // An unordered set written in iteration order makes sync see changes
      // that never happened.
      final a = outfit(seasons: {Season.winter, Season.autumn});
      final b = outfit(seasons: {Season.autumn, Season.winter});
      expect(a.toJson()['seasons'], b.toJson()['seasons']);
    });
  });
}
