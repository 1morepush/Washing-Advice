import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

void main() {
  const resolver = CareResolver();

  final woolFacts = buildFacts(
    type: ItemType.sweater,
    composition: {Fiber.wool: 100},
  );

  group('source precedence', () {
    test('with nothing to go on it falls back conservatively', () {
      final result = resolver.resolve(
        facts: buildFacts(composition: const {}),
      );
      expect(result.profile.source, Provenance.fallbackDefault);
      expect(result.profile.confidence, 0);
      expect(result.profile.shouldPromptForTagScan, isTrue);
    });

    test('fibre rules alone produce a rule-derived profile', () {
      final result = resolver.resolve(facts: woolFacts);
      expect(result.profile.source, Provenance.careRule);
      expect(result.instructions.dry.tumbleDryAllowed, isFalse);
    });

    test('a scanned label outranks a model guess', () {
      final result = resolver.resolve(
        facts: buildFacts(),
        fromLabel: const CareConstraint(maxTempC: 40),
        fromInference: const CareConstraint(maxTempC: 60),
      );
      expect(result.profile.source, Provenance.tagScan);
      expect(result.instructions.wash.maxTempC, 40);
    });

    test('a user correction outranks everything', () {
      final result = resolver.resolve(
        facts: woolFacts,
        fromLabel: const CareConstraint(maxTempC: 30),
        userOverride: heavyCare,
      );
      expect(result.profile.source, Provenance.userEdited);
      expect(result.profile.confidence, 1.0);
      expect(result.instructions, heavyCare);
    });
  });

  group('a label overrides a generic fibre rule', () {
    // The superwash wool case. Our wool rule says "never tumble dry", but a
    // manufacturer who prints "machine wash 40, tumble low" on a superwash
    // jumper knows something the rule does not. Forcing the rule over an
    // explicit instruction would be both wrong and infuriating.
    test('superwash wool stays machine washable when the label says so', () {
      final result = resolver.resolve(
        facts: woolFacts,
        fromLabel: const CareConstraint(
          method: WashMethod.machine,
          maxTempC: 40,
          tumbleDryAllowed: true,
          tumbleDryHeat: TumbleDryHeat.low,
        ),
      );

      expect(result.instructions.wash.method, WashMethod.machine);
      expect(result.instructions.wash.maxTempC, 40);
      expect(result.instructions.dry.tumbleDryAllowed, isTrue);
      expect(result.instructions.dry.tumbleDryHeat, TumbleDryHeat.low);
    });

    test('and the override is reported so the app can mention it', () {
      final result = resolver.resolve(
        facts: woolFacts,
        fromLabel: const CareConstraint(
          maxTempC: 40,
          tumbleDryAllowed: true,
        ),
      );
      expect(
        result.fieldsOverriddenByLabel,
        containsAll(['wash.maxTempC', 'dry.tumbleDryAllowed']),
      );
    });

    test('rules still fill fields the label left unstated', () {
      // A creased label whose drying symbol is illegible: the wool rule must
      // still supply the drying instruction rather than leaving it permissive.
      final result = resolver.resolve(
        facts: woolFacts,
        fromLabel:
            const CareConstraint(method: WashMethod.machine, maxTempC: 40),
      );
      expect(result.instructions.wash.maxTempC, 40);
      expect(result.instructions.dry.tumbleDryAllowed, isFalse);
    });

    test('a label that restates the rule is not reported as an override', () {
      final result = resolver.resolve(
        facts: woolFacts,
        fromLabel: const CareConstraint(tumbleDryAllowed: false),
      );
      expect(result.fieldsOverriddenByLabel, isEmpty);
    });
  });

  group('model inference', () {
    // Plain linen in a mid grey deliberately triggers no rule at all: it does
    // not felt, shed lint, hold odour or pill, and its colour is neither white
    // nor dark. That isolates inference as the only contributing source.
    final inertFacts = buildFacts(
      composition: {Fiber.linen: 100},
      colors: [Colors.grey],
    );

    test('the inert fixture really does trigger no rules', () {
      expect(const CareRuleEvaluator().matching(inertFacts), isEmpty);
    });

    test('may tighten a field nothing else covers', () {
      final result = resolver.resolve(
        facts: inertFacts,
        fromInference: const CareConstraint(maxTempC: 30),
      );
      expect(result.instructions.wash.maxTempC, 30);
      expect(result.profile.source, Provenance.aiInference);
    });

    test('a fired rule is reported as the source ahead of inference', () {
      // Both contribute, and both tighten the result — but the reported
      // provenance is the strongest one, because a deterministic derivation
      // from fibre content is better evidence than a guess from a photograph.
      final result = resolver.resolve(
        // Polyester is thermoplastic, so a rule fires for it.
        facts: buildFacts(composition: {Fiber.polyester: 100}),
        fromInference: const CareConstraint(maxTempC: 30),
      );
      expect(result.instructions.wash.maxTempC, 30);
      expect(result.profile.source, Provenance.careRule);
    });

    test('cannot loosen what a rule established', () {
      final result = resolver.resolve(
        facts: woolFacts,
        fromInference: const CareConstraint(
          tumbleDryAllowed: true,
          tumbleDryHeat: TumbleDryHeat.high,
        ),
      );
      expect(result.instructions.dry.tumbleDryAllowed, isFalse);
    });

    test('an empty constraint is treated as saying nothing at all', () {
      const empty = CareConstraint();
      expect(empty.statesNothing, isTrue);

      final result = resolver.resolve(
        facts: inertFacts,
        fromInference: empty,
      );
      expect(result.profile.source, Provenance.fallbackDefault);
    });
  });

  group('confidence reporting', () {
    test('a high-confidence label produces a trusted profile', () {
      final result = resolver.resolve(
        facts: buildFacts(),
        fromLabel: const CareConstraint(maxTempC: 40),
        labelConfidence: 0.95,
      );
      expect(result.profile.isTrusted, isTrue);
      expect(result.profile.shouldPromptForTagScan, isFalse);
    });

    test('a weak model guess prompts for a tag scan', () {
      final result = resolver.resolve(
        facts: buildFacts(composition: const {}),
        fromInference: const CareConstraint(maxTempC: 40),
        inferenceConfidence: 0.3,
      );
      expect(result.profile.band, ConfidenceBand.low);
      expect(result.profile.shouldPromptForTagScan, isTrue);
    });

    test('a scanned label never prompts to be scanned again', () {
      final result = resolver.resolve(
        facts: buildFacts(),
        fromLabel: const CareConstraint(maxTempC: 40),
        labelConfidence: 0.4,
      );
      expect(result.profile.shouldPromptForTagScan, isFalse);
    });

    test('a rule fired on established facts is worth its full weight', () {
      final result = resolver.resolve(facts: woolFacts);

      expect(result.profile.source, Provenance.careRule);
      expect(result.profile.confidence, closeTo(0.7, 1e-9));
    });

    test('a rule fired on a guessed fabric reports itself as a guess', () {
      // The wool rule is exact. What it was applied *to* was a vision model's
      // reading of a photograph, and the conclusion cannot be surer than that.
      final result = resolver.resolve(facts: woolFacts, factsConfidence: 0.62);

      expect(result.profile.source, Provenance.careRule);
      expect(result.profile.confidence, closeTo(0.7 * 0.62, 1e-9));
      // Which is what puts the "scan the label" prompt on exactly the garments
      // whose care rests on an uncertain fibre reading.
      expect(result.profile.band, ConfidenceBand.low);
      expect(result.profile.shouldPromptForTagScan, isTrue);
    });

    test('a label is not attenuated by how well the fabric was guessed', () {
      // The manufacturer's own instruction supersedes our reading of the
      // fabric; it does not build on it. Attenuating here would make a clear
      // photograph of a care label look uncertain because the garment shot
      // beside it was blurry.
      final result = resolver.resolve(
        facts: woolFacts,
        fromLabel: const CareConstraint(maxTempC: 40),
        labelConfidence: 0.95,
        factsConfidence: 0.3,
      );

      expect(result.profile.source, Provenance.tagScan);
      expect(result.profile.confidence, closeTo(0.95, 1e-9));
      expect(result.profile.isTrusted, isTrue);
    });
  });

  test('explanations come back with the result', () {
    final result = resolver.resolve(facts: woolFacts);
    expect(result.rationales, isNotEmpty);
    expect(result.rationales.first, contains('felt'));
  });

  group('resolving from the item itself', () {
    WardrobeItem woolJumper({Confident<CareConstraint>? label}) {
      final now = DateTime.utc(2026, 8, 5);
      return WardrobeItem(
        id: const ItemId('jumper'),
        name: 'Wool jumper',
        type: Confident(
          ItemType.sweater,
          confidence: 0.95,
          source: Provenance.aiInference,
        ),
        composition: Confident(
          FabricComposition(const {Fiber.wool: 100}),
          confidence: 0.95,
          source: Provenance.tagScan,
        ),
        colors: Confident(
          ColorPalette.empty(),
          confidence: 0.9,
          source: Provenance.aiInference,
        ),
        careLabel: label,
        care: const CareProfile.unknown(),
        addedAt: now,
        updatedAt: now,
      );
    }

    test('without a label, the wool rule decides', () {
      final result = resolver.forItem(woolJumper());

      expect(result.profile.source, Provenance.careRule);
      expect(result.instructions.dry.tumbleDryAllowed, isFalse);
    });

    test('a stored label overrides the generic rule', () {
      // Superwash wool: the manufacturer knows something the fibre does not.
      final result = resolver.forItem(
        woolJumper(
          label: Confident(
            const CareConstraint(
              method: WashMethod.machine,
              maxTempC: 40,
              tumbleDryAllowed: true,
              tumbleDryHeat: TumbleDryHeat.low,
            ),
            confidence: 0.93,
            source: Provenance.tagScan,
          ),
        ),
      );

      expect(result.profile.source, Provenance.tagScan);
      expect(result.instructions.wash.maxTempC, 40);
      expect(result.instructions.dry.tumbleDryAllowed, isTrue);
      expect(result.fieldsOverriddenByLabel, contains('dry.tumbleDryAllowed'));
    });

    test('correcting the fabric later does not discard the label', () {
      // The reason the label is stored on the item as evidence rather than
      // folded into the resolved profile. Re-resolving after an edit has to
      // re-run the rule table, and a label lost at that point would downgrade
      // a manufacturer's instruction to a generic rule without telling anyone.
      final scanned = Confident(
        const CareConstraint(tumbleDryAllowed: true),
        confidence: 0.93,
        source: Provenance.tagScan,
      );

      final corrected = woolJumper(label: scanned).copyWith(
        composition: Confident(
          FabricComposition(const {Fiber.wool: 50, Fiber.acrylic: 50}),
          confidence: 1.0,
          source: Provenance.userEdited,
        ),
      );

      final result = resolver.forItem(corrected);

      expect(result.instructions.dry.tumbleDryAllowed, isTrue);
      expect(result.profile.source, Provenance.tagScan);
    });
  });
}
