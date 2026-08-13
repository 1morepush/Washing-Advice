/// Vetting a proposed stain treatment.
///
/// This is the file where a bug ruins clothes. A model asked "how do I get red
/// wine out of this?" will happily suggest a hot soak and a splash of bleach,
/// because that is genuinely the answer for a cotton tea towel — and following
/// it on a wool jumper destroys the jumper. So almost everything below is a
/// *refusal*, and the assertions are about what does not survive.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

const _safety = StainSafety();

/// A step with only the attribute under test set.
TreatmentStep _step({
  String instruction = 'Do the thing.',
  int? temperatureC,
  BleachUse? bleach,
  bool isMachineWash = false,
  bool abrades = false,
}) =>
    TreatmentStep(
      instruction: instruction,
      temperatureC: temperatureC,
      bleach: bleach,
      isMachineWash: isMachineWash,
      abrades: abrades,
    );

void main() {
  _treatedGarments();
  group('bleach', () {
    test('chlorine is refused on wool whatever the label says', () {
      // Physics before paperwork. Chlorine hydrolyses protein fibres — it does
      // not fade wool, it dissolves it — so a label claiming any bleach is
      // fine is a label that is wrong.
      final jumper = buildItem(
        composition: const {Fiber.wool: 100},
        careInstructions: const CareInstructions(
          wash: WashCare(method: WashMethod.hand, maxTempC: 30),
          bleach: BleachAllowance.any,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
      );

      final plan = _safety.vet([
        _step(bleach: BleachUse.chlorine),
      ], item: jumper);

      expect(plan.steps, isEmpty);
      expect(plan.refused.single.reason, contains('dissolves wool and silk'));
    });

    test('chlorine is refused on silk too', () {
      final blouse = buildItem(composition: const {Fiber.silk: 100});

      final plan = _safety.vet([
        _step(bleach: BleachUse.chlorine),
      ], item: blouse);

      expect(plan.steps, isEmpty);
    });

    test('any bleach is refused when the label forbids bleaching', () {
      final tee = buildItem(
        composition: const {Fiber.cotton: 100},
        careInstructions: const CareInstructions(
          wash: WashCare(method: WashMethod.machine, maxTempC: 40),
          bleach: BleachAllowance.none,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
      );

      final plan = _safety.vet([
        _step(bleach: BleachUse.oxygen),
      ], item: tee);

      expect(plan.refused.single.reason, contains('do not bleach'));
    });

    test('oxygen bleach survives a non-chlorine-only label', () {
      // The most common bleach symbol on clothing. Treating it as "no bleach"
      // would throw away most of what actually shifts a stain.
      final tee = buildItem(
        composition: const {Fiber.cotton: 100},
        careInstructions: const CareInstructions(
          wash: WashCare(method: WashMethod.machine, maxTempC: 40),
          bleach: BleachAllowance.nonChlorineOnly,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
      );

      final plan = _safety.vet([
        _step(bleach: BleachUse.oxygen),
      ], item: tee);

      expect(plan.steps, hasLength(1));
      expect(plan.refused, isEmpty);
    });

    test('chlorine does not survive a non-chlorine-only label', () {
      final tee = buildItem(
        composition: const {Fiber.cotton: 100},
        careInstructions: const CareInstructions(
          wash: WashCare(method: WashMethod.machine, maxTempC: 40),
          bleach: BleachAllowance.nonChlorineOnly,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
      );

      final plan = _safety.vet([
        _step(bleach: BleachUse.chlorine),
      ], item: tee);

      expect(plan.refused.single.reason, contains('non-chlorine'));
    });
  });

  group('temperature', () {
    test('a soak hotter than the label allows is refused', () {
      final jumper = buildItem(
        composition: const {Fiber.wool: 100},
        careInstructions: const CareInstructions(
          wash: WashCare(method: WashMethod.hand, maxTempC: 30),
          bleach: BleachAllowance.none,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
      );

      final plan = _safety.vet([
        _step(instruction: 'Soak in hot water.', temperatureC: 60),
      ], item: jumper);

      expect(plan.refused.single.reason, contains('no more than 30°C'));
    });

    test('a soak within the limit is kept', () {
      final jumper = buildItem(
        composition: const {Fiber.wool: 100},
        careInstructions: const CareInstructions(
          wash: WashCare(method: WashMethod.hand, maxTempC: 30),
          bleach: BleachAllowance.none,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
      );

      final plan = _safety.vet([
        _step(instruction: 'Rinse under a cold tap.', temperatureC: 20),
      ], item: jumper);

      expect(plan.steps, hasLength(1));
    });
  });

  group('washing', () {
    test('a machine step is refused on a hand-wash-only garment', () {
      final jumper = buildItem(
        careInstructions: const CareInstructions(
          wash: WashCare(method: WashMethod.hand, maxTempC: 30),
          bleach: BleachAllowance.none,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
      );

      final plan = _safety.vet([
        _step(instruction: 'Wash as normal.', isMachineWash: true),
      ], item: jumper);

      expect(plan.refused.single.reason, contains('hand wash only'));
    });

    test('a machine step is refused on a do-not-wash garment', () {
      final coat = buildItem(
        careInstructions: const CareInstructions(
          wash: WashCare(method: WashMethod.doNotWash),
          bleach: BleachAllowance.none,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
      );

      final plan = _safety.vet([
        _step(instruction: 'Wash as normal.', isMachineWash: true),
      ], item: coat);

      expect(plan.refused.single.reason, contains('do not wash'));
    });
  });

  group('what survives', () {
    test('an ordinary treatment on an ordinary cotton tee is untouched', () {
      // The other half of the job. A vetting layer that refused everything
      // would be safe and useless.
      final tee = buildItem(composition: const {Fiber.cotton: 100});

      final plan = _safety.vet([
        _step(instruction: 'Blot with a clean cloth.'),
        _step(instruction: 'Rinse from the back.', temperatureC: 20),
        _step(instruction: 'Wash as normal.', isMachineWash: true),
      ], item: tee);

      expect(plan.steps, hasLength(3));
      expect(plan.refused, isEmpty);
    });

    test('order is preserved, because the steps are a sequence', () {
      final tee = buildItem(composition: const {Fiber.cotton: 100});

      final plan = _safety.vet([
        _step(instruction: 'First.'),
        _step(instruction: 'Second.'),
        _step(instruction: 'Third.'),
      ], item: tee);

      expect(plan.steps.map((s) => s.instruction), [
        'First.',
        'Second.',
        'Third.',
      ]);
    });

    test('everything being refused is a real answer, not an error', () {
      // A dry-clean-only silk with nothing safe left to try. Inventing a
      // treatment to avoid an empty list would be far worse than saying so.
      final blouse = buildItem(
        composition: const {Fiber.silk: 100},
        careInstructions: const CareInstructions(
          wash: WashCare(method: WashMethod.doNotWash),
          bleach: BleachAllowance.none,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
      );

      final plan = _safety.vet([
        _step(bleach: BleachUse.chlorine),
        _step(instruction: 'Wash as normal.', isMachineWash: true),
      ], item: blouse);

      expect(plan.isEmpty, isTrue);
      expect(plan.refused, hasLength(2));
    });
  });

  group('cautions', () {
    test('rubbing a protein fibre earns a warning rather than a refusal', () {
      // Rubbing silk is not forbidden, it is just how silk gets abraded. A
      // refusal here would leave nothing to do at all.
      final blouse = buildItem(composition: const {Fiber.silk: 100});

      final plan = _safety.vet([
        _step(instruction: 'Work the stain gently.', abrades: true),
      ], item: blouse);

      expect(plan.steps, hasLength(1));
      expect(plan.cautions.single, contains('Blot rather than rub'));
    });

    test('a strong new colour is warned about before any bleach', () {
      final tee = buildItem(
        colors: [Colors.red],
        composition: const {Fiber.cotton: 100},
        usage: const UsageStats(timesWashed: 0, timesWorn: 1),
        careInstructions: const CareInstructions(
          wash: WashCare(method: WashMethod.machine, maxTempC: 40),
          bleach: BleachAllowance.nonChlorineOnly,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
      );

      final plan = _safety.vet([
        _step(bleach: BleachUse.oxygen),
      ], item: tee);

      expect(plan.cautions.join(), contains('inside seam'));
    });

    test('a caution is not raised for a step that was thrown out', () {
      // Warning about rubbing a garment you have just been told not to touch
      // reads as advice to do it.
      final blouse = buildItem(
        composition: const {Fiber.silk: 100},
        careInstructions: const CareInstructions(
          wash: WashCare(method: WashMethod.doNotWash),
          bleach: BleachAllowance.none,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
      );

      final plan = _safety.vet([
        _step(instruction: 'Wash it out.', isMachineWash: true, abrades: true),
      ], item: blouse);

      expect(plan.steps, isEmpty);
      expect(plan.cautions, isEmpty);
    });
  });
}

/// Whether a treated garment is flagged to the wash plan.
///
/// The last link in the chain, and the one most likely to be silently missing:
/// the advice can be perfect and the treatment recorded, and if the load card
/// says nothing then the garment goes in the dryer and whatever did not come
/// out is set for good.
void _treatedGarments() {
  WearObservation treatedAt(DateTime when) => WearObservation(
        type: WearType.stain,
        severity: WearSeverity.slight,
        observedAt: when,
        note: 'Treated: red wine',
      );

  group('a garment with a treated mark', () {
    test('is flagged when it has never been washed since', () {
      final item = buildItem(
        usage: const UsageStats(timesWashed: 0, timesWorn: 1),
      ).copyWith(condition: ConditionAssessment([treatedAt(testNow)]));

      expect(item.hasStainAwaitingAWash, isTrue);
    });

    test('stops being flagged once it has been through a wash', () {
      // Otherwise every garment ever treated carries the warning for life, and
      // a warning that is always on is a warning nobody reads.
      final item = buildItem(
        usage: UsageStats(
          timesWashed: 4,
          timesWorn: 9,
          lastWashedAt: testNow.add(const Duration(days: 1)),
        ),
      ).copyWith(condition: ConditionAssessment([treatedAt(testNow)]));

      expect(item.hasStainAwaitingAWash, isFalse);
    });

    test('is flagged again if it is stained after that wash', () {
      final item = buildItem(
        usage: UsageStats(timesWashed: 4, timesWorn: 9, lastWashedAt: testNow),
      ).copyWith(
        condition: ConditionAssessment([
          treatedAt(testNow.add(const Duration(days: 2))),
        ]),
      );

      expect(item.hasStainAwaitingAWash, isTrue);
    });

    test('a garment with no stain on record is not flagged', () {
      expect(buildItem().hasStainAwaitingAWash, isFalse);
    });

    test('the load it goes in says to check it before drying', () {
      final treated = buildItem(
        id: 'treated',
        name: 'White cotton tee',
        usage: const UsageStats(timesWashed: 0, timesWorn: 1),
      ).copyWith(condition: ConditionAssessment([treatedAt(testNow)]));

      final plan = const LaundrySorter().sort([treated]);

      expect(
        plan.loads.single
            .rationaleOf(RationaleKind.handling)
            .map((r) => r.reason)
            .join(' '),
        contains('before this load goes near heat'),
      );
    });

    test('an ordinary load says nothing about treated marks', () {
      final plan = const LaundrySorter().sort([buildItem(id: 'plain')]);

      expect(
        plan.loads.single
            .rationaleOf(RationaleKind.handling)
            .map((r) => r.reason)
            .join(' '),
        isNot(contains('near heat')),
      );
    });
  });
}
