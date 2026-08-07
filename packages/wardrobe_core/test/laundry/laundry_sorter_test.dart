import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

void main() {
  final sorter = LaundrySorter(clock: FixedClock(testNow));
  final washer = seededWashers['LG']!;
  final dryer = seededDryers['LG']!;

  WardrobeItem tee(String id, ItemColor colour) =>
      buildItem(id: id, colors: [colour]);

  group('partitioning', () {
    test('leaves out things that are not laundry', () {
      final plan = sorter.sort([
        buildItem(id: 'shoes', type: ItemType.sneakers),
        tee('tee', Colors.grey),
      ]);
      expect(plan.unassigned.map((u) => u.item.id.value), ['shoes']);
      expect(plan.unassigned.first.reason, contains('washing machine'));
      expect(plan.itemsSorted, 1);
    });

    test('leaves out items the label forbids washing', () {
      final plan = sorter.sort([
        buildItem(
          id: 'leather-jacket',
          type: ItemType.jacket,
          composition: {Fiber.leather: 100},
          careInstructions: const CareInstructions(
            wash: WashCare(method: WashMethod.doNotWash),
            bleach: BleachAllowance.none,
            dry: DryCare(tumbleDryAllowed: false),
            iron: IronCare(temperature: IronTemperature.none),
            professional: ProfessionalCare(
              solvent: CleaningSolvent.hydrocarbon,
            ),
          ),
        ),
      ]);
      expect(plan.loads, isEmpty);
      expect(plan.unassigned.single.reason, contains('professional'));
    });

    test('asks for a tag scan when care is only a weak guess', () {
      final plan = sorter.sort([
        buildItem(
          id: 'mystery',
          careSource: Provenance.aiInference,
          careConfidence: 0.2,
        ),
      ]);
      expect(plan.actionable, hasLength(1));
      expect(plan.actionable.single.reason, contains('care label'));
    });

    test('leaves out items that are stored or already donated', () {
      final plan = sorter.sort([
        buildItem(id: 'donated', lifecycle: LifecycleState.donated),
      ]);
      expect(plan.loads, isEmpty);
      expect(plan.unassigned.single.reason, contains('donated'));
    });
  });

  group('grouping', () {
    test('keeps whites away from darks', () {
      final plan = sorter.sort([
        tee('white-1', Colors.white),
        tee('white-2', Colors.offWhite),
        tee('dark-1', Colors.black),
        tee('dark-2', Colors.navy),
      ], washer: washer);

      expect(plan.loadCount, 2);
      for (final load in plan.loads) {
        final classes = load.items.map((i) => i.colorClass).toSet();
        expect(
          classes.contains(ColorClass.whites) &&
              classes.contains(ColorClass.darks),
          isFalse,
          reason: 'a load mixed whites with darks',
        );
      }
    });

    test('isolates a new bleeding item in its own load', () {
      final plan = sorter.sort([
        tee('grey', Colors.grey),
        tee('navy', Colors.navy),
        buildItem(
          id: 'new-red',
          colors: [Colors.red],
          usage: const UsageStats(timesWashed: 0, timesWorn: 1),
        ),
      ], washer: washer);

      final redLoad = plan.loads.firstWhere(
        (load) => load.items.any((i) => i.id.value == 'new-red'),
      );
      expect(redLoad.itemCount, 1);
      expect(
        redLoad.rationaleOf(RationaleKind.separation).single.reason,
        contains('dye'),
      );
    });

    test('keeps delicates out of a load with jeans', () {
      final plan = sorter.sort([
        buildItem(
          id: 'jeans',
          type: ItemType.jeans,
          colors: [Colors.navy],
          careInstructions: heavyCare,
        ),
        buildItem(
          id: 'silk',
          type: ItemType.blouse,
          composition: {Fiber.silk: 100},
          colors: [Colors.navy],
          careInstructions: delicateCare,
        ),
      ], washer: washer);

      expect(plan.loadCount, 2);
    });

    test('merges compatible groups to reduce the number of loads', () {
      // Two temperature bands that do not conflict should end up together,
      // running at the lower of the two, rather than as two separate washes.
      final plan = sorter.sort([
        buildItem(
          id: 'warm-tee',
          colors: [Colors.navy],
          careInstructions: cottonCare,
        ),
        buildItem(
          id: 'cool-tee',
          colors: [Colors.navy],
          careInstructions: const CareInstructions(
            wash: WashCare(method: WashMethod.machine, maxTempC: 30),
            bleach: BleachAllowance.none,
            dry: DryCare(
              tumbleDryAllowed: true,
              tumbleDryHeat: TumbleDryHeat.low,
            ),
            iron: IronCare(temperature: IronTemperature.medium),
            professional: ProfessionalCare.unspecified(),
          ),
        ),
      ], washer: washer);

      expect(plan.loadCount, 1);
      expect(plan.loads.single.washSpec.maxTempC, 30);
    });

    test('splits a group that exceeds the drum capacity', () {
      // Six duvet covers at 1.5kg each with a 2.2 bulk factor is far beyond a
      // 9kg drum, so it has to become several loads.
      final plan = sorter.sort([
        for (var i = 0; i < 6; i++)
          buildItem(
            id: 'duvet-$i',
            type: ItemType.duvetCover,
            colors: [Colors.white],
            careInstructions: heavyCare,
          ),
      ], washer: washer);

      expect(plan.loadCount, greaterThan(1));
      for (final load in plan.loads) {
        expect(
          load.totalWeightKg,
          lessThanOrEqualTo(washer.capacityKg * 0.8 + 0.001),
        );
      }
      expect(plan.itemsSorted, 6);
    });

    test('every item is either sorted or explained', () {
      final wardrobe = [
        tee('a', Colors.white),
        tee('b', Colors.navy),
        buildItem(id: 'c', type: ItemType.sneakers),
        buildItem(id: 'd', type: ItemType.jeans, careInstructions: heavyCare),
        buildItem(
          id: 'e',
          type: ItemType.blouse,
          composition: {Fiber.silk: 100},
          careInstructions: delicateCare,
        ),
        buildItem(id: 'f', type: ItemType.bathTowel, colors: [Colors.white]),
      ];
      final plan = sorter.sort(wardrobe, washer: washer);
      expect(plan.itemsSorted + plan.unassigned.length, wardrobe.length);
    });
  });

  group('load settings', () {
    test('a load runs at the temperature its most delicate item allows', () {
      final plan = sorter.sort([
        buildItem(
          id: 'hot-ok',
          colors: [Colors.navy],
          careInstructions: heavyCare,
          type: ItemType.jeans,
        ),
        buildItem(
          id: 'cool-only',
          colors: [Colors.navy],
          type: ItemType.jeans,
          careInstructions: const CareInstructions(
            wash: WashCare(method: WashMethod.machine, maxTempC: 30),
            bleach: BleachAllowance.none,
            dry: DryCare(tumbleDryAllowed: true),
            iron: IronCare(temperature: IronTemperature.medium),
            professional: ProfessionalCare.unspecified(),
          ),
        ),
      ], washer: washer);

      final load = plan.loads.single;
      expect(load.effectiveCare.wash.maxTempC, 30);
      expect(load.washerSetting!.temperatureC, lessThanOrEqualTo(30));
    });

    test('one item forbidding the dryer stops the whole load', () {
      final plan = sorter.sort([
        buildItem(id: 'tumbleable', colors: [Colors.navy]),
        buildItem(
          id: 'no-tumble',
          colors: [Colors.navy],
          careInstructions: cottonCare.copyWith(
            dry: const DryCare(tumbleDryAllowed: false),
          ),
        ),
      ], washer: washer, dryer: dryer);

      final load = plan.loads.single;
      expect(load.drySpec.tumbleDryAllowed, isFalse);
      expect(load.dryerSetting!.isAirDry, isTrue);
    });

    test('names a real programme on the configured machine', () {
      final plan = sorter.sort(
        [tee('t', Colors.navy)],
        washer: washer,
      );
      final programNames = washer.programs.map((p) => p.displayName).toSet();
      expect(
          programNames, contains(plan.loads.single.washerSetting!.programName));
    });

    test('works without any machine configured', () {
      final plan = sorter.sort([tee('t', Colors.navy)]);
      expect(plan.loadCount, 1);
      expect(plan.loads.single.washerSetting, isNull);
      expect(plan.loads.single.washSpec.maxTempC, isNotNull);
    });
  });

  group('explanations', () {
    test('names the item responsible for the temperature', () {
      final plan = sorter.sort([
        buildItem(
          id: 'jeans',
          name: 'Blue jeans',
          type: ItemType.jeans,
          colors: [Colors.navy],
          careInstructions: heavyCare,
        ),
        buildItem(
          id: 'delicate-jeans',
          name: 'Fragile jeans',
          type: ItemType.jeans,
          colors: [Colors.navy],
          careInstructions: cottonCare.copyWith(
            wash: const WashCare(method: WashMethod.machine, maxTempC: 30),
          ),
        ),
      ], washer: washer);

      final reason =
          plan.loads.single.rationaleOf(RationaleKind.temperature).single;
      expect(reason.reason, contains('Fragile jeans'));
      expect(reason.causedBy?.value, 'delicate-jeans');
    });

    test('does not blame one item when several share responsibility', () {
      final plan = sorter.sort([
        buildItem(id: 'a', colors: [Colors.navy], careInstructions: cottonCare),
        buildItem(id: 'b', colors: [Colors.navy], careInstructions: cottonCare),
      ], washer: washer);

      final reason =
          plan.loads.single.rationaleOf(RationaleKind.temperature).single;
      expect(reason.causedBy, isNull);
      expect(reason.reason, contains('every item'));
    });

    test('every load carries at least one explanation', () {
      final plan = sorter.sort([
        tee('a', Colors.white),
        tee('b', Colors.navy),
        buildItem(
          id: 'c',
          type: ItemType.blouse,
          composition: {Fiber.silk: 100},
          careInstructions: delicateCare,
        ),
      ], washer: washer, dryer: dryer);

      for (final load in plan.loads) {
        expect(load.rationale, isNotEmpty, reason: load.label);
      }
    });
  });

  group('relationships', () {
    test('keeps a suit together even across grouping', () {
      final jacket = buildItem(
        id: 'suit-jacket',
        type: ItemType.blazer,
        colors: [Colors.charcoal],
      );
      final trousers = buildItem(
        id: 'suit-trousers',
        type: ItemType.trousers,
        colors: [Colors.charcoal],
      );
      final graph = RelationshipGraph([
        ItemRelationship(
          from: jacket.id,
          to: trousers.id,
          kind: RelationKind.suitSet,
        ),
      ]);

      final plan = sorter.sort(
        [
          jacket,
          trousers,
          buildItem(id: 'other', colors: [Colors.charcoal])
        ],
        washer: washer,
        relationships: graph,
      );

      final jacketLoad = plan.loads.firstWhere(
        (l) => l.items.any((i) => i.id == jacket.id),
      );
      expect(
        jacketLoad.items.map((i) => i.id.value),
        contains('suit-trousers'),
      );
    });
  });

  group('determinism', () {
    test('the same pile always produces the same plan', () {
      final wardrobe = [
        tee('a', Colors.white),
        tee('b', Colors.navy),
        buildItem(id: 'c', type: ItemType.jeans, careInstructions: heavyCare),
        buildItem(id: 'd', type: ItemType.bathTowel, colors: [Colors.white]),
      ];

      final first = sorter.sort(wardrobe, washer: washer, dryer: dryer);
      final second = sorter.sort(wardrobe, washer: washer, dryer: dryer);

      expect(first.loadCount, second.loadCount);
      for (var i = 0; i < first.loadCount; i++) {
        expect(
          first.loads[i].items.map((x) => x.id.value),
          second.loads[i].items.map((x) => x.id.value),
        );
        expect(
          first.loads[i].washerSetting?.programName,
          second.loads[i].washerSetting?.programName,
        );
      }
    });

    test('an empty pile produces an empty plan rather than failing', () {
      final plan = sorter.sort([], washer: washer);
      expect(plan.isEmpty, isTrue);
      expect(plan.generatedAt, testNow);
    });
  });
}
