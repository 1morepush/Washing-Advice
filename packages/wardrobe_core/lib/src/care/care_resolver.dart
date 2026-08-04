/// Turns everything known about an item into one set of care instructions.
///
/// Three sources can have an opinion, and they routinely disagree:
///
///  * the **care label**, read by OCR — the manufacturer's own instruction;
///  * the **rule table**, derived from fibre content, garment type and colour;
///  * a **vision model's guess**, when there is no label to read.
///
/// The resolution order encodes who actually knows best:
///
///  1. Start from conservative defaults.
///  2. Apply the rule table, which can only tighten.
///  3. Let a scanned label **override** the fields it states. A manufacturer
///     saying "machine wash 40, tumble low" on superwash wool knows something
///     the generic wool rule does not.
///  4. Let a model's guess tighten only fields nobody else has covered.
///  5. Let a user correction override everything.
///
/// Warnings accumulate from every source, since they advise rather than
/// contradict.
library;

import '../shared/confidence.dart';
import 'model/care_instructions.dart';
import 'rules/care_rule.dart';
import 'rules/rule_evaluator.dart';

/// The result of resolving care for one item.
final class CareResolution {
  const CareResolution({
    required this.profile,
    required this.appliedRules,
    this.fieldsOverriddenByLabel = const {},
  });

  /// The resolved instructions, with provenance and confidence.
  final CareProfile profile;

  /// Rules that fired, in priority order, each carrying its explanation.
  final List<AppliedRule> appliedRules;

  /// Fields where a scanned label overruled the rule table.
  ///
  /// Worth surfacing: "the label says this wool jumper is machine washable,
  /// which is unusual" is genuinely useful information.
  final Set<String> fieldsOverriddenByLabel;

  CareInstructions get instructions => profile.instructions;

  /// Explanations to show beneath a recommendation.
  List<String> get rationales =>
      [for (final rule in appliedRules) rule.rationale];

  @override
  String toString() => 'CareResolution(${profile.source.name}, '
      '${appliedRules.length} rules)';
}

/// Combines label, rules and inference into a single care profile.
final class CareResolver {
  const CareResolver({CareRuleEvaluator? evaluator})
      : _evaluator = evaluator ?? const CareRuleEvaluator();

  final CareRuleEvaluator _evaluator;

  /// Resolves care for an item.
  ///
  /// [fromLabel] and [fromInference] are partial: a null field means that
  /// source said nothing about it, which is different from saying "no". A
  /// creased care label with an illegible drying symbol produces a constraint
  /// with `tumbleDryAllowed: null`, and the rule table fills that gap.
  CareResolution resolve({
    required ItemFacts facts,
    CareConstraint? fromLabel,
    double labelConfidence = 0.9,
    CareConstraint? fromInference,
    double inferenceConfidence = 0.5,
    CareInstructions? userOverride,
  }) {
    // 1 + 2: conservative defaults, tightened by the rule table.
    final evaluation = _evaluator.evaluate(facts);
    var instructions = evaluation.instructions;

    // 4 (applied before the label so the label still wins): a model's guess
    // may only tighten, and only where it has something to say.
    if (fromInference != null && !fromInference.statesNothing) {
      instructions = fromInference.applyTo(instructions);
    }

    // 3: the label overrides the fields it states.
    var overridden = <String>{};
    if (fromLabel != null && !fromLabel.statesNothing) {
      final beforeLabel = instructions;
      instructions = fromLabel.overrideOnto(instructions);
      overridden = _fieldsChangedBy(beforeLabel, instructions, fromLabel);
    }

    // 5: the user is always right.
    if (userOverride != null) {
      return CareResolution(
        profile: CareProfile(
          instructions: userOverride,
          source: Provenance.userEdited,
          confidence: 1.0,
        ),
        appliedRules: evaluation.applied,
        fieldsOverriddenByLabel: overridden,
      );
    }

    final (source, confidence) = _strongestSource(
      hasLabel: fromLabel != null && !fromLabel.statesNothing,
      labelConfidence: labelConfidence,
      hasInference: fromInference != null && !fromInference.statesNothing,
      inferenceConfidence: inferenceConfidence,
      hasRules: evaluation.applied.isNotEmpty,
    );

    return CareResolution(
      profile: CareProfile(
        instructions: instructions,
        source: source,
        confidence: confidence,
      ),
      appliedRules: evaluation.applied,
      fieldsOverriddenByLabel: overridden,
    );
  }

  /// Which fields the label actually changed, as opposed to merely restated.
  Set<String> _fieldsChangedBy(
    CareInstructions before,
    CareInstructions after,
    CareConstraint label,
  ) =>
      {
        for (final field in label.statedFields)
          if (_valueOf(before, field) != _valueOf(after, field)) field,
      };

  Object? _valueOf(CareInstructions instructions, String field) =>
      switch (field) {
        'wash.method' => instructions.wash.method,
        'wash.maxTempC' => instructions.wash.maxTempC,
        'wash.agitation' => instructions.wash.agitation,
        'bleach' => instructions.bleach,
        'dry.tumbleDryAllowed' => instructions.dry.tumbleDryAllowed,
        'dry.tumbleDryHeat' => instructions.dry.tumbleDryHeat,
        'dry.naturalDry' => instructions.dry.naturalDry,
        'dry.dryInShade' => instructions.dry.dryInShade,
        'dry.doNotWring' => instructions.dry.doNotWring,
        'iron.temperature' => instructions.iron.temperature,
        'iron.steamAllowed' => instructions.iron.steamAllowed,
        'professional.doNotDryClean' => instructions.professional.doNotDryClean,
        _ => null,
      };

  /// The provenance and confidence to record for the resolved profile.
  ///
  /// Reports the strongest source that contributed. Rule-derived care is
  /// recorded at a deliberately middling confidence: the derivation is exact,
  /// but it rests on a fibre composition that may itself have been guessed.
  (Provenance, double) _strongestSource({
    required bool hasLabel,
    required double labelConfidence,
    required bool hasInference,
    required double inferenceConfidence,
    required bool hasRules,
  }) {
    if (hasLabel) return (Provenance.tagScan, labelConfidence);
    if (hasRules) return (Provenance.careRule, 0.7);
    if (hasInference) return (Provenance.aiInference, inferenceConfidence);
    return (Provenance.fallbackDefault, 0.0);
  }
}
