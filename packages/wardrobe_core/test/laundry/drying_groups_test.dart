/// Washing together and drying apart.
///
/// A load is grouped for *washing*: its members share a drum because their
/// wash requirements are compatible. Drying is a different question and the
/// answers disagree more often than they agree — a cotton tee and a technical
/// short wash together happily, and one of them must not go near a dryer.
///
/// Held as one, the load takes the most restrictive answer any member demands,
/// so a single air-dry-only garment sends the whole drum to the airer. That is
/// safe and wasteful, which is why the finer answer is offered rather than
/// imposed.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 21);

  WardrobeItem item(
    String id, {
    required bool tumbleDry,
    ItemType type = ItemType.tShirt,
  }) {
    final built = WardrobeItem(
      id: ItemId(id),
      name: id,
      type: Confident(type, confidence: 0.95, source: Provenance.aiInference),
      composition: Confident(
        FabricComposition(const {Fiber.cotton: 100}),
        confidence: 0.95,
        source: Provenance.tagScan,
      ),
      colors: Confident(
        ColorPalette([ItemColor.fromHex('#1F2A44', name: 'navy')]),
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      careLabel: Confident(
        CareConstraint(
          method: WashMethod.machine,
          maxTempC: 30,
          tumbleDryAllowed: tumbleDry,
        ),
        confidence: 0.95,
        source: Provenance.tagScan,
      ),
      lifecycle: LifecycleState.inLaundry,
      care: const CareProfile.unknown(),
      addedAt: now,
      updatedAt: now,
    );
    return built.copyWith(care: const CareResolver().forItem(built).profile);
  }

  LaundryLoad sortOne(List<WardrobeItem> items, {required bool split}) =>
      LaundrySorter(
        preferences: SortingPreferences(splitDrying: split),
      ).sort(items).loads.single;

  group('drying the load as one, which is the default', () {
    test('a load has exactly one drying group', () {
      final load = sortOne([
        item('a', tumbleDry: true),
        item('b', tumbleDry: false),
      ], split: false);

      expect(load.dryingGroups, hasLength(1));
      expect(load.driesInParts, isFalse);
    });

    test('and one garment that cannot be tumbled holds back the rest', () {
      // Not a bug — it is the safe answer, and it is the behaviour every
      // earlier version had. It is also the waste the split exists to fix.
      final load = sortOne([
        item('a', tumbleDry: true),
        item('b', tumbleDry: false),
      ], split: false);

      expect(load.drySpec.tumbleDryAllowed, isFalse);
      expect(load.dryingGroups.single.items, hasLength(2));
    });
  });

  group('drying it in parts', () {
    test('the tumble-dryable half is no longer held back', () {
      // The whole point. One garment stops costing the other three a dryer
      // cycle they could perfectly well have had.
      final load = sortOne([
        item('a', tumbleDry: true),
        item('b', tumbleDry: true),
        item('c', tumbleDry: false),
      ], split: true);

      expect(load.driesInParts, isTrue);
      final tumbled = load.dryingGroups.firstWhere((g) => g.isTumbleDried);
      expect(tumbled.items.map((i) => i.id.value), ['a', 'b']);
    });

    test('the rest is still kept off the heat', () {
      final load = sortOne([
        item('a', tumbleDry: true),
        item('c', tumbleDry: false),
      ], split: true);

      final hung = load.dryingGroups.firstWhere((g) => !g.isTumbleDried);
      expect(hung.items.map((i) => i.id.value), ['c']);
      expect(hung.spec.tumbleDryAllowed, isFalse);
    });

    test('the wash is untouched: they still share a drum', () {
      // Splitting the drying must not split the washing. That would turn one
      // load into two and undo the sorting the screen exists to do.
      final load = sortOne([
        item('a', tumbleDry: true),
        item('c', tumbleDry: false),
      ], split: true);

      expect(load.items, hasLength(2));
      expect(load.washSpec.maxTempC, 30);
    });

    test('every garment lands in exactly one group', () {
      // A garment in neither is one nobody dries; a garment in both is one
      // somebody dries twice.
      final items = [
        item('a', tumbleDry: true),
        item('b', tumbleDry: false),
        item('c', tumbleDry: true),
      ];

      final load = sortOne(items, split: true);
      final grouped = [
        for (final group in load.dryingGroups)
          for (final member in group.items) member.id.value,
      ];

      expect(grouped, unorderedEquals(['a', 'b', 'c']));
      expect(grouped.toSet(), hasLength(3));
    });

    test('a load that agrees with itself is not split for the sake of it', () {
      // A lone group has to look exactly like an unsplit one, or the screen
      // announces a division that does not exist.
      final load = sortOne([
        item('a', tumbleDry: true),
        item('b', tumbleDry: true),
      ], split: true);

      expect(load.dryingGroups, hasLength(1));
      expect(load.driesInParts, isFalse);
    });

    test('the load-level answer stays the conservative one', () {
      // Anything reading `drySpec` without knowing about groups — an older
      // screen, a saved record — must still get the answer that cannot ruin
      // anything.
      final load = sortOne([
        item('a', tumbleDry: true),
        item('b', tumbleDry: false),
      ], split: true);

      expect(load.drySpec.tumbleDryAllowed, isFalse);
    });
  });
}
