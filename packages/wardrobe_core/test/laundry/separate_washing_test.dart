/// Washing colours apart, when the sorter would have combined them.
///
/// The sorter's default is to fill a drum: colour classes that do not conflict
/// — lights with brights — go in together, because four half loads cost four
/// times the water and wear the clothes four times over.
///
/// That is a judgement about *risk*, and some people have been burnt and no
/// longer want it made on their behalf. `mergeAcrossColorClasses` is how they
/// say so. It has been in the core since the sorter was written and was never
/// reachable from the app, which is the only reason it arrives with tests this
/// late.
///
/// The direction matters more than the feature. This can only ever split loads
/// the sorter would have combined. It cannot combine loads the sorter split,
/// because those were split to stop a white shirt coming out pink, and a
/// preference is not evidence about dye.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 27);

  /// A garment whose colour is stated in Lab directly.
  ///
  /// Hex would be the readable choice and the wrong one: the classes are
  /// thresholds on lightness and chroma, so a test written in hex would be
  /// asserting on a conversion it does not control, and a colour sitting a
  /// point the wrong side of a boundary would look like a sorting bug.
  WardrobeItem item(
    String id, {
    required double lightness,
    required double a,
    required double b,
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
        ColorPalette([ItemColor(lightness: lightness, a: a, b: b)]),
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      careLabel: Confident(
        const CareConstraint(
          method: WashMethod.machine,
          maxTempC: 30,
          tumbleDryAllowed: true,
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

  // Pale and unsaturated: lights.
  WardrobeItem light(String id) => item(id, lightness: 70, a: 6, b: -10);

  // Saturated but pale enough not to be judged a bleed risk, which is checked
  // before the colour classes and would separate these on its own.
  WardrobeItem bright(String id) => item(id, lightness: 78, a: -50, b: 30);

  WardrobeItem white(String id) => item(id, lightness: 95, a: 0, b: 1);

  WardrobeItem dark(String id) => item(id, lightness: 20, a: 2, b: -6);

  LaundryPlan sort(List<WardrobeItem> items, {required bool separate}) =>
      LaundrySorter(
        preferences: SortingPreferences(mergeAcrossColorClasses: !separate),
      ).sort(items);

  test('the colours are the ones this test believes they are', () {
    // Every assertion below is about which class an item lands in. If the
    // thresholds move, these fixtures should fail here and loudly, rather than
    // quietly turning the real tests into assertions about nothing.
    expect(light('a').colorClass, ColorClass.lights);
    expect(bright('a').colorClass, ColorClass.brights);
    expect(white('a').colorClass, ColorClass.whites);
    expect(dark('a').colorClass, ColorClass.darks);
    expect(bright('a').isLikelyToBleed, isFalse);
  });

  group('combining, which is the default', () {
    test('lights and brights share a drum', () {
      final plan = sort([
        light('a'),
        light('b'),
        bright('c'),
      ], separate: false);

      expect(plan.loads, hasLength(1));
      expect(plan.loads.single.items, hasLength(3));
    });
  });

  group('washing each colour separately', () {
    test('splits what would have been combined', () {
      final plan = sort([
        light('a'),
        light('b'),
        bright('c'),
      ], separate: true);

      expect(plan.loads, hasLength(2));
      expect(
        plan.loads.map((load) => load.items.length).toList()..sort(),
        [1, 2],
      );
    });

    test('and every garment still goes somewhere', () {
      // The failure this guards is a garment dropped on the floor by a merge
      // that declined to place it, which the load count alone would not catch.
      final items = [light('a'), light('b'), bright('c'), dark('d')];
      final plan = sort(items, separate: true);

      expect(
        plan.loads.expand((load) => load.items).map((i) => i.id).toSet(),
        items.map((i) => i.id).toSet(),
      );
      expect(plan.unassigned, isEmpty);
    });

    test('items of one colour are not split further', () {
      // Separating by colour is the whole instruction. Turning it on must not
      // also mean four loads of one garment each.
      final plan = sort([
        light('a'),
        light('b'),
        light('c'),
      ], separate: true);

      expect(plan.loads, hasLength(1));
      expect(plan.loads.single.items, hasLength(3));
    });
  });

  group('it only ever separates', () {
    test('whites still do not join darks when combining is allowed', () {
      final plan = sort([white('a'), dark('b')], separate: false);

      expect(plan.loads, hasLength(2));
    });

    test('so turning it on cannot make a load larger', () {
      final items = [light('a'), bright('b'), white('c'), dark('d')];

      final combined = sort(items, separate: false);
      final apart = sort(items, separate: true);

      expect(
        apart.loads.length,
        greaterThanOrEqualTo(combined.loads.length),
        reason: 'separating colours can only ever add loads',
      );
      for (final load in apart.loads) {
        expect(
          load.items.map((i) => i.colorClass).toSet(),
          hasLength(1),
          reason: 'a load must not mix colour classes once separated',
        );
      }
    });
  });
}
