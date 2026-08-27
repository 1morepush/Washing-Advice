/// What the user says about washing one particular garment.
///
/// For the case a label cannot cover: worn away, cut out, or never there. The
/// app could already infer care from fabric and read it off a tag; the one
/// thing it could not do was be told.
///
/// The seam existed and was unused — `CareResolver.forItem` documented itself
/// as the way to avoid forgetting "the user's override" and then did not pass
/// one. What is tested here is the ordering, because getting it wrong is the
/// kind of mistake that ruins a garment quietly.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 21);

  WardrobeItem item({
    CareConstraint? ownCare,
    Confident<CareConstraint>? label,
    Map<Fiber, int> fibers = const {Fiber.cotton: 100},
  }) {
    final built = WardrobeItem(
      id: const ItemId('a'),
      name: 'Jumper',
      type: Confident(
        ItemType.sweater,
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      composition: Confident(
        FabricComposition(fibers),
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      colors: Confident(
        ColorPalette([ItemColor.fromHex('#1F2A44')]),
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      careLabel: label,
      ownCare: ownCare,
      care: const CareProfile.unknown(),
      addedAt: now,
      updatedAt: now,
    );
    return built.copyWith(care: const CareResolver().forItem(built).profile);
  }

  group('being told, when there is no label to read', () {
    test('what the user states is what the garment gets', () {
      final told = item(ownCare: const CareConstraint(maxTempC: 20));

      expect(told.effectiveCare.wash.maxTempC, 20);
      expect(told.care.source, Provenance.userEdited);
    });

    test('it only has to state what the user actually knows', () {
      // The whole reason this is partial. Somebody whose label has worn away
      // knows "wash it cold" and has no opinion about a bleach symbol, and a
      // form demanding one would be inviting them to invent it.
      final told = item(
        ownCare: const CareConstraint(maxTempC: 20),
        fibers: const {Fiber.wool: 100},
      );

      expect(told.effectiveCare.wash.maxTempC, 20);
      // Still the rule table's answer for wool, which nobody had to restate.
      expect(told.effectiveCare.dry.tumbleDryAllowed, isFalse);
    });

    test('saying nothing at all leaves the rules in charge', () {
      // An empty statement must not read as a user assertion, or clearing the
      // form would silently claim the garment needs nothing.
      final untold = item(ownCare: const CareConstraint());

      expect(untold.care.source, isNot(Provenance.userEdited));
    });

    test('and a garment nobody has said anything about is unaffected', () {
      expect(item().care.source, isNot(Provenance.userEdited));
    });
  });

  group('against a label', () {
    Confident<CareConstraint> label(CareConstraint value) =>
        Confident(value, confidence: 0.95, source: Provenance.tagScan);

    test('the user wins, because that is the case this exists for', () {
      // A label that is illegible, cut out or simply wrong is exactly why
      // somebody types their own answer. Deferring to the tag here would make
      // the feature useless in the case it was built for.
      final told = item(
        ownCare: const CareConstraint(maxTempC: 20),
        label: label(const CareConstraint(maxTempC: 60)),
      );

      expect(told.effectiveCare.wash.maxTempC, 20);
      expect(told.care.source, Provenance.userEdited);
    });

    test('the label still covers what the user did not mention', () {
      // Layered, not replaced. Overriding one field must not throw away every
      // other thing the manufacturer stated.
      final told = item(
        ownCare: const CareConstraint(maxTempC: 20),
        label: label(
          const CareConstraint(maxTempC: 60, doNotDryClean: true),
        ),
      );

      expect(told.effectiveCare.wash.maxTempC, 20);
      expect(told.effectiveCare.professional.doNotDryClean, isTrue);
    });
  });

  group('what it must not be able to do', () {
    test('it cannot talk a damaged garment into a dryer', () async {
      // The user wins on care, and observed wear still wins over the user.
      // `effectiveCare` merges restrictively on top of the resolved profile,
      // so somebody insisting a pilling jumper may be tumbled at 60 gets their
      // instruction recorded and the garment still kept off the heat.
      final pilling = ConditionAssessment([
        WearObservation(
          type: WearType.pilling,
          severity: WearSeverity.moderate,
          observedAt: now,
        ),
      ]);
      final told = item(
        ownCare: const CareConstraint(
          maxTempC: 60,
          tumbleDryAllowed: true,
          tumbleDryHeat: TumbleDryHeat.high,
        ),
        fibers: const {Fiber.wool: 100},
      ).copyWith(condition: pilling);

      expect(told.care.instructions.wash.maxTempC, 60);
      expect(told.effectiveCare.dry.tumbleDryAllowed, isFalse);
      expect(told.effectiveCare.wash.maxTempC, lessThanOrEqualTo(30));
    });
  });

  group('keeping it', () {
    test('it survives a round trip through storage', () {
      final told = item(
        ownCare: const CareConstraint(maxTempC: 20, tumbleDryAllowed: false),
      );

      final read = WardrobeItem.fromJson(told.toJson());

      expect(read.ownCare?.maxTempC, 20);
      expect(read.ownCare?.tumbleDryAllowed, isFalse);
      // And still resolves the same way on the other side.
      expect(read.effectiveCare.wash.maxTempC, 20);
    });

    test('a garment nobody has told anything stores nothing', () {
      expect(item().toJson().containsKey('ownCare'), isFalse);
    });
  });
}
