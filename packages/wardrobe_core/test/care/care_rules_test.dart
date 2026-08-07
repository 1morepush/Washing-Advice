import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

void main() {
  const evaluator = CareRuleEvaluator();

  group('restrictive merge', () {
    test('takes the lower of two temperatures', () {
      const warm = WashCare(method: WashMethod.machine, maxTempC: 40);
      const cool = WashCare(method: WashMethod.machine, maxTempC: 30);
      expect(warm.restrictiveMerge(cool).maxTempC, 30);
      expect(cool.restrictiveMerge(warm).maxTempC, 30);
    });

    test('an unstated temperature does not constrain a stated one', () {
      const unstated = WashCare(method: WashMethod.machine);
      const stated = WashCare(method: WashMethod.machine, maxTempC: 30);
      expect(unstated.restrictiveMerge(stated).maxTempC, 30);
      expect(stated.restrictiveMerge(unstated).maxTempC, 30);
    });

    test('hand wash beats machine wash', () {
      const machine = WashCare(method: WashMethod.machine);
      const hand = WashCare(method: WashMethod.hand);
      expect(machine.restrictiveMerge(hand).method, WashMethod.hand);
    });

    test('do not wash beats everything', () {
      const hand = WashCare(method: WashMethod.hand);
      const never = WashCare(method: WashMethod.doNotWash);
      expect(hand.restrictiveMerge(never).method, WashMethod.doNotWash);
    });

    test('takes the gentler agitation', () {
      const normal = WashCare(method: WashMethod.machine);
      const gentle = WashCare(
        method: WashMethod.machine,
        agitation: Agitation.veryMild,
      );
      expect(normal.restrictiveMerge(gentle).agitation, Agitation.veryMild);
    });

    test('one item forbidding the dryer forbids it for the whole load', () {
      const allowed = DryCare(
        tumbleDryAllowed: true,
        tumbleDryHeat: TumbleDryHeat.high,
      );
      const forbidden = DryCare(tumbleDryAllowed: false);
      expect(allowed.restrictiveMerge(forbidden).tumbleDryAllowed, isFalse);
      expect(forbidden.restrictiveMerge(allowed).tumbleDryAllowed, isFalse);
    });

    test('takes the cooler dryer heat', () {
      const hot = DryCare(
        tumbleDryAllowed: true,
        tumbleDryHeat: TumbleDryHeat.high,
      );
      const low = DryCare(
        tumbleDryAllowed: true,
        tumbleDryHeat: TumbleDryHeat.low,
      );
      expect(hot.restrictiveMerge(low).tumbleDryHeat, TumbleDryHeat.low);
    });

    test('bleach prohibition wins over permission', () {
      expect(
        BleachAllowance.any.stricter(BleachAllowance.none),
        BleachAllowance.none,
      );
      expect(
        BleachAllowance.none.stricter(BleachAllowance.any),
        BleachAllowance.none,
      );
    });

    test('warnings accumulate across a merge', () {
      final a = cottonCare.withWarnings([CareWarning.washInsideOut]);
      final b = cottonCare.withWarnings([CareWarning.useMeshBag]);
      expect(
        a.restrictiveMerge(b).warnings,
        containsAll([CareWarning.washInsideOut, CareWarning.useMeshBag]),
      );
    });

    test('merging is commutative on a full instruction set', () {
      final forward = cottonCare.restrictiveMerge(delicateCare);
      final backward = delicateCare.restrictiveMerge(cottonCare);
      expect(forward, backward);
    });

    test('merging a set with itself changes nothing', () {
      expect(delicateCare.restrictiveMerge(delicateCare), delicateCare);
    });
  });

  group('rule table', () {
    // Rules are evaluated against a *permissive* base rather than the
    // conservative default. Starting from `CareInstructions.conservative()`
    // would make most of these assertions vacuous — that base already forbids
    // tumble drying, so a passing test would prove nothing about the rule.
    // Starting from ordinary cotton care (40°C, tumble dry medium) means only
    // the rule under test can produce the tightening being asserted.

    test('wool must not be tumble dried', () {
      final result = evaluator.evaluate(
        buildFacts(type: ItemType.sweater, composition: {Fiber.wool: 100}),
        base: cottonCare,
      );
      expect(result.instructions.dry.tumbleDryAllowed, isFalse);
      expect(result.instructions.wash.agitation, Agitation.veryMild);
      expect(result.instructions.wash.maxTempC, 30);
      expect(result.applied.map((r) => r.id), contains('protein.felting'));
    });

    test('a wool blend above the escalation threshold is treated as wool', () {
      final result = evaluator.evaluate(
        buildFacts(
          type: ItemType.sweater,
          composition: {Fiber.wool: 20, Fiber.acrylic: 80},
        ),
        base: cottonCare,
      );
      expect(result.instructions.dry.tumbleDryAllowed, isFalse);
    });

    test('a trace of wool below the threshold does not', () {
      final result = evaluator.evaluate(
        buildFacts(
          type: ItemType.sweater,
          composition: {Fiber.wool: 5, Fiber.acrylic: 95},
        ),
      );
      expect(
          result.applied.map((r) => r.id), isNot(contains('protein.felting')));
    });

    test('3% elastane is enough to cap the dryer heat', () {
      final result = evaluator.evaluate(
        buildFacts(
          type: ItemType.leggings,
          composition: {Fiber.cotton: 97, Fiber.elastane: 3},
        ),
        base:
            heavyCare, // permits high heat, so the cap has to come from the rule
      );
      expect(result.instructions.dry.tumbleDryHeat, TumbleDryHeat.low);
      expect(
          result.applied.map((r) => r.id), contains('elastane.heat_degrades'));
    });

    test('a rule can only tighten care, never loosen it', () {
      // Elastane asks for "low heat", but if the item is already no-heat the
      // rule must not raise it. This is the invariant the whole table relies on.
      final result = evaluator.evaluate(
        buildFacts(
          type: ItemType.leggings,
          composition: {Fiber.cotton: 97, Fiber.elastane: 3},
        ),
        base: delicateCare,
      );
      expect(result.instructions.dry.tumbleDryHeat, TumbleDryHeat.noHeat);
      expect(result.instructions.dry.tumbleDryAllowed, isFalse);
    });

    test('protein fibres forbid chlorine bleach', () {
      final result = evaluator.evaluate(
        buildFacts(type: ItemType.blouse, composition: {Fiber.silk: 100}),
        base: heavyCare, // heavyCare allows any bleach
      );
      expect(result.instructions.bleach, BleachAllowance.none);
    });

    test('viscose must not be wrung', () {
      final result = evaluator.evaluate(
        buildFacts(type: ItemType.dress, composition: {Fiber.viscose: 100}),
        base: cottonCare,
      );
      expect(result.instructions.dry.doNotWring, isTrue);
      expect(result.instructions.dry.naturalDry, NaturalDryMethod.flatDry);
    });

    test('leather must not be washed at all', () {
      final result = evaluator.evaluate(
        buildFacts(type: ItemType.jacket, composition: {Fiber.leather: 100}),
        base: cottonCare,
      );
      expect(result.instructions.wash.method, WashMethod.doNotWash);
    });

    test('a bra gets a mesh bag and closed fastenings', () {
      final result = evaluator.evaluate(
        buildFacts(
          type: ItemType.bra,
          composition: {Fiber.nylon: 85, Fiber.elastane: 15},
        ),
        base: cottonCare,
      );
      expect(
        result.instructions.warnings,
        containsAll([CareWarning.useMeshBag, CareWarning.closeFastenings]),
      );
      expect(result.instructions.wash.method, WashMethod.hand);
    });

    test('a new saturated item is flagged to wash separately', () {
      final result = evaluator.evaluate(
        buildFacts(colors: [Colors.red], timesWashed: 0),
        base: cottonCare,
      );
      expect(
        result.instructions.warnings,
        contains(CareWarning.washSeparately),
      );
    });

    test('the same item after several washes is not', () {
      final result = evaluator.evaluate(
        buildFacts(colors: [Colors.red], timesWashed: 10),
      );
      expect(
        result.applied.map((r) => r.id),
        isNot(contains('colour.new_bright_bleeds')),
      );
    });

    test('damaged items are handled more gently than their fibre implies', () {
      final result = evaluator.evaluate(
        buildFacts(
          type: ItemType.jeans,
          composition: {Fiber.cotton: 100},
          condition: ConditionGrade.damaged,
        ),
        base: heavyCare,
      );
      expect(result.instructions.wash.agitation, Agitation.veryMild);
      expect(result.instructions.dry.tumbleDryAllowed, isFalse);
    });

    test('every rule carries a real explanation', () {
      for (final rule in defaultCareRules) {
        expect(
          rule.rationale.length,
          greaterThan(40),
          reason: '${rule.id} needs an explanation a user would accept',
        );
        expect(rule.rationale.trim(), endsWith('.'));
      }
    });

    test('rule ids are unique', () {
      final ids = defaultCareRules.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('rule application is order-independent', () {
    // The property that makes the table safe to extend: because every
    // constraint can only tighten, no rule can undo another, so the outcome
    // does not depend on the order rules happen to be listed in.
    test('reversing the rule order gives an identical result', () {
      final facts = buildFacts(
        type: ItemType.sweater,
        composition: {Fiber.wool: 40, Fiber.polyester: 57, Fiber.elastane: 3},
        colors: [Colors.navy],
        timesWashed: 0,
      );

      final forward = const CareRuleEvaluator().evaluate(facts);
      final reversed = CareRuleEvaluator(
        StaticRuleSource(defaultCareRules.reversed.toList()),
      ).evaluate(facts);

      expect(reversed.instructions, forward.instructions);
    });

    test('and so does an arbitrary shuffle', () {
      final facts = buildFacts(
        type: ItemType.activewearTop,
        composition: {Fiber.polyester: 88, Fiber.elastane: 12},
        colors: [Colors.black],
      );

      final baseline = const CareRuleEvaluator().evaluate(facts).instructions;

      // A deterministic reordering — no RNG, so a failure is reproducible.
      for (var offset = 1; offset < defaultCareRules.length; offset += 3) {
        final rotated = [
          ...defaultCareRules.skip(offset),
          ...defaultCareRules.take(offset),
        ];
        final result =
            CareRuleEvaluator(StaticRuleSource(rotated)).evaluate(facts);
        expect(result.instructions, baseline, reason: 'offset $offset');
      }
    });

    test('priority affects explanation order but not the outcome', () {
      final facts = buildFacts(
        type: ItemType.sweater,
        composition: {Fiber.wool: 100},
      );
      final result = evaluator.evaluate(facts);
      final priorities = <int>[for (final r in result.applied) r.rule.priority];
      final descending = <int>[...priorities]..sort((a, b) => b.compareTo(a));
      expect(priorities, orderedEquals(descending));
    });
  });
}
