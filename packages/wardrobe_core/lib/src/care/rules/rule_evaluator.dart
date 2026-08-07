/// Applies the care rule table to an item.
library;

import '../model/care_instructions.dart';
import 'care_rule.dart';
import 'default_rules.dart';

/// A rule that fired, kept so the app can explain its advice.
final class AppliedRule {
  const AppliedRule({required this.rule, required this.rationale});

  final CareRule rule;

  /// The user-facing explanation, lifted from the rule.
  final String rationale;

  String get id => rule.id;

  @override
  String toString() => 'AppliedRule(${rule.id})';
}

/// The outcome of evaluating the rule table.
final class RuleEvaluation {
  const RuleEvaluation({required this.instructions, required this.applied});

  /// Care requirements after every matching rule has been folded in.
  final CareInstructions instructions;

  /// Which rules fired, most significant first.
  final List<AppliedRule> applied;

  bool get isEmpty => applied.isEmpty;

  /// The explanations, ready to show under a recommendation.
  List<String> get rationales => [for (final rule in applied) rule.rationale];

  @override
  String toString() => 'RuleEvaluation(${applied.length} rules applied)';
}

/// Evaluates care rules against an item's facts.
///
/// Because every [CareConstraint] can only tighten requirements, the result is
/// independent of the order rules are applied in. That is what makes the table
/// safe to extend: a new rule can never accidentally loosen an existing one.
/// [CareRule.priority] therefore affects only the order explanations are
/// listed, never the outcome — a property asserted directly in the tests.
final class CareRuleEvaluator {
  const CareRuleEvaluator([this.source = defaultRuleSource]);

  final RuleSource source;

  /// Folds every matching rule into [base].
  RuleEvaluation evaluate(
    ItemFacts facts, {
    CareInstructions base = const CareInstructions.conservative(),
  }) {
    final matched = <CareRule>[
      for (final rule in source.rules)
        if (rule.appliesWhen(facts)) rule,
    ]..sort((x, y) => y.priority.compareTo(x.priority));

    var result = base;
    for (final rule in matched) {
      result = rule.imposes.applyTo(result);
    }

    return RuleEvaluation(
      instructions: result,
      applied: [
        for (final rule in matched)
          AppliedRule(rule: rule, rationale: rule.rationale),
      ],
    );
  }

  /// The rules that would fire, without computing the merged result.
  List<CareRule> matching(ItemFacts facts) => [
        for (final rule in source.rules)
          if (rule.appliesWhen(facts)) rule,
      ];
}
