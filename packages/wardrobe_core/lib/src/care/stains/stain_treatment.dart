/// Treating a stain, and refusing to ruin the garment doing it.
///
/// Stain removal is the one place in this app where an open vocabulary is
/// unavoidable. Sorting a wash is a closed problem over attributes the app
/// already holds; "what do I do about turmeric on a silk shirt" is not, and a
/// rule table that knew twenty substances would be silently useless for the
/// twenty-first. So the *treatment* is proposed by a model.
///
/// What is emphatically **not** left to the model is whether the treatment is
/// safe for this particular garment. Bad stain advice destroys clothes in ways
/// that cannot be undone — chlorine dissolves wool and silk outright, a hot
/// soak sets a protein stain permanently, and rubbing silk abrades it — and a
/// confident paragraph is indistinguishable from a correct one. So every step
/// arrives with machine-checkable attributes beside its prose, and this file
/// throws out the ones the garment's own care forbids.
///
/// That split is the same one the rest of the app already makes: the model
/// perceives and proposes, the core judges. The difference here is that the
/// core is judging the model's output rather than a photograph's.
library;

import '../../wardrobe/model/fabric.dart';
import '../../wardrobe/model/wardrobe_item.dart';
import '../model/care_instructions.dart';
import '../model/care_symbols.dart';

/// The kind of bleach a step calls for.
///
/// Separated because care labels separate them, and the difference is the
/// difference between a garment surviving and not: "non-chlorine only" is the
/// most common bleach symbol on clothing, and treating it as "no bleach" would
/// throw away most of what actually works on a stain.
enum BleachUse {
  chlorine('chlorine bleach'),
  oxygen('oxygen bleach');

  const BleachUse(this.label);

  final String label;
}

/// One instruction in a stain treatment.
///
/// The prose is what the user reads. The rest is what [StainSafety] reads, and
/// it exists because "soak in hot water" and "soak in cool water" are one word
/// apart in a sentence and worlds apart for a wool jumper. A step that stated
/// only prose could not be checked at all.
final class TreatmentStep {
  const TreatmentStep({
    required this.instruction,
    this.because,
    this.temperatureC,
    this.bleach,
    this.isMachineWash = false,
    this.abrades = false,
  });

  /// A complete sentence, ready to follow.
  final String instruction;

  /// Why this step, in one line. Optional — some steps are self-evident.
  final String? because;

  /// Water temperature the step calls for, when it names one.
  final int? temperatureC;

  /// The bleach the step uses, if any.
  final BleachUse? bleach;

  /// Whether this step puts the garment through a machine.
  final bool isMachineWash;

  /// Whether the step rubs, scrubs or otherwise works the fabric.
  ///
  /// Not a safety question for cotton and a serious one for wool and silk,
  /// which felt and abrade — so it is recorded rather than inferred from the
  /// wording, which would mean parsing English to find the verb.
  final bool abrades;

  @override
  String toString() => instruction;
}

/// A step that was dropped, and what it contradicted.
final class RefusedStep {
  const RefusedStep({required this.step, required this.reason});

  final TreatmentStep step;

  /// Phrased for the user, naming the garment's own instruction rather than
  /// the rule that fired: "the care label says do not bleach" is checkable by
  /// the person holding the garment; "rule bleach.none" is not.
  final String reason;

  @override
  String toString() => '${step.instruction} — $reason';
}

/// A vetted treatment: what to do, what was thrown out, and what to watch.
final class TreatmentPlan {
  const TreatmentPlan({
    required this.steps,
    this.refused = const [],
    this.cautions = const [],
  });

  /// The steps that survived, in order.
  final List<TreatmentStep> steps;

  /// The steps that did not, each with its reason.
  ///
  /// Shown rather than silently dropped. A treatment that quietly loses half
  /// its steps looks like a weak answer; one that says "the usual next step is
  /// a chlorine soak, and this label forbids it" is a useful one, and it is
  /// also the honest account of what happened.
  final List<RefusedStep> refused;

  /// Warnings the garment itself earns, whatever the substance.
  final List<String> cautions;

  /// Whether anything survived vetting.
  ///
  /// False is a real outcome — a dry-clean-only silk with a set oil stain has
  /// no safe home treatment, and inventing one would be worse than saying so.
  bool get isEmpty => steps.isEmpty;
}

/// Checks a proposed treatment against what a garment can actually take.
///
/// Deliberately not configurable and not overridable: every rule here is a
/// physical fact about the fibre or an instruction from the manufacturer, and
/// neither is a preference. A user who wants to bleach their wool anyway can
/// do it; the app just will not be the thing that told them to.
final class StainSafety {
  const StainSafety();

  /// Returns [proposed] with every unsafe step removed.
  TreatmentPlan vet(List<TreatmentStep> proposed,
      {required WardrobeItem item}) {
    final care = item.effectiveCare;
    final fibres = item.composition.value;

    final kept = <TreatmentStep>[];
    final refused = <RefusedStep>[];

    for (final step in proposed) {
      final reason = _refuse(step, care: care, fibres: fibres);
      if (reason == null) {
        kept.add(step);
      } else {
        refused.add(RefusedStep(step: step, reason: reason));
      }
    }

    return TreatmentPlan(
      steps: kept,
      refused: refused,
      cautions: _cautions(item, kept),
    );
  }

  /// Why this step must not be followed on this garment, or null to keep it.
  ///
  /// Ordered by severity, so the reason given is the worst thing wrong with
  /// the step rather than the first thing checked.
  String? _refuse(
    TreatmentStep step, {
    required CareInstructions care,
    required FabricComposition fibres,
  }) {
    // Physics before paperwork. Chlorine hydrolyses protein fibres — it does
    // not fade wool or silk, it destroys them — so this holds even when a
    // label has said bleach is fine, because that label is then wrong.
    if (step.bleach == BleachUse.chlorine && _hasProtein(fibres)) {
      return 'Chlorine bleach dissolves wool and silk, whatever the label '
          'says about bleaching.';
    }

    if (step.bleach != null && care.bleach == BleachAllowance.none) {
      return 'The care label says do not bleach.';
    }
    if (step.bleach == BleachUse.chlorine &&
        care.bleach == BleachAllowance.nonChlorineOnly) {
      return 'The care label allows non-chlorine bleach only.';
    }

    if (step.temperatureC case final int temperature) {
      if (care.wash.maxTempC case final int limit when temperature > limit) {
        return 'The care label allows no more than $limit°C, and this step '
            'calls for $temperature°C.';
      }
    }

    if (step.isMachineWash) {
      switch (care.wash.method) {
        case WashMethod.doNotWash:
          return 'The care label says do not wash this at home.';
        case WashMethod.hand:
          return 'The care label says hand wash only.';
        case WashMethod.machine:
          break;
      }
    }

    return null;
  }

  /// Warnings the garment earns regardless of what was spilled on it.
  ///
  /// Additions rather than refusals: each of these makes a step riskier
  /// without making it wrong, and a treatment that refused every risky step on
  /// a silk shirt would refuse all of them.
  List<String> _cautions(WardrobeItem item, List<TreatmentStep> steps) {
    final fibres = item.composition.value;
    final cautions = <String>[];

    if (_hasProtein(fibres) && steps.any((step) => step.abrades)) {
      cautions.add(
        'Blot rather than rub. Wool and silk felt and abrade when worked, and '
        'that damage does not come out.',
      );
    }

    if (item.isLikelyToBleed && steps.any((step) => step.bleach != null)) {
      cautions.add(
        'This is a strong colour that has not been washed much. Test any '
        'bleach on an inside seam first — it can lift the dye as readily as '
        'the stain.',
      );
    }

    if (item.effectiveCare.warnings.contains(CareWarning.doNotIronDecoration)) {
      cautions.add(
        'Keep heat away from the print or trim while you work.',
      );
    }

    return cautions;
  }

  bool _hasProtein(FabricComposition fibres) =>
      fibres.percentages.keys.any((fibre) => fibre.isProtein);
}
