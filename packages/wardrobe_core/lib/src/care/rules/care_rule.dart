/// The care rule model: typed, declarative, inspectable.
///
/// Care knowledge — "wool must not go in a tumble dryer", "3% elastane rules
/// out high heat" — has to live somewhere. Scattering it through `if` branches
/// in the sorter makes it untestable and invisible to the user. Building a
/// generic condition/action interpreter would make it configurable at the cost
/// of type safety and compile-time exhaustiveness.
///
/// The middle path taken here: each rule is a typed value holding a predicate,
/// the constraint it imposes, and a human-readable rationale. Adding knowledge
/// means adding a row to a table. Every rule is independently unit-testable,
/// the compiler still checks every constraint, and because each carries its own
/// explanation the app can always say *why* it is recommending something.
///
/// [RuleSource] exists so a remote, JSON-backed rule set can be introduced
/// later without changing the evaluator or any caller.
library;

import '../../wardrobe/model/condition.dart';
import '../../wardrobe/model/fabric.dart';
import '../../wardrobe/model/item_attributes.dart';
import '../../wardrobe/model/item_color.dart';
import '../model/care_instructions.dart';
import '../model/care_symbols.dart';

/// The facts a rule may examine.
///
/// A deliberately narrow projection of a wardrobe item. Rules must not see the
/// item's existing care instructions, because they are one of the inputs used
/// to *derive* those instructions — letting a rule read them would make the
/// result depend on evaluation order.
final class ItemFacts {
  const ItemFacts({
    required this.type,
    required this.composition,
    this.colors,
    this.pattern,
    this.conditionGrade = ConditionGrade.pristine,
    this.timesWashed = 0,
  });

  final ItemType type;
  final FabricComposition composition;
  final ColorPalette? colors;
  final Pattern? pattern;
  final ConditionGrade conditionGrade;

  /// How many times the item has been washed. Dye bleed drops off sharply
  /// after the first few washes, so this changes the advice.
  final int timesWashed;

  /// True when [fiber] is present at or above its escalation threshold.
  bool hasEnough(Fiber fiber) =>
      composition.contains(fiber, minPercent: fiber.escalationThreshold);

  /// True when any fibre satisfying [test] is present in a decisive amount.
  bool hasTrait(bool Function(Fiber fiber) test) =>
      composition.hasDominantTrait(test);

  bool get isNew => timesWashed < 3;

  ColorClass? get colorClass => colors?.colorClass;
}

/// A partial set of care requirements that a rule imposes.
///
/// Every field is optional: a rule about drying says nothing about ironing.
/// [applyTo] folds the set fields into an existing [CareInstructions] using the
/// same restrictive-merge semantics as everywhere else, so a rule can only ever
/// make care *safer*, never more permissive. That property is what makes it
/// safe to apply the whole table in any order.
final class CareConstraint {
  const CareConstraint({
    this.method,
    this.maxTempC,
    this.agitation,
    this.bleach,
    this.tumbleDryAllowed,
    this.tumbleDryHeat,
    this.naturalDry,
    this.dryInShade,
    this.doNotWring,
    this.ironTemperature,
    this.steamAllowed,
    this.doNotDryClean,
    this.warnings = const {},
  });

  final WashMethod? method;
  final int? maxTempC;

  /// The cycle the label calls for.
  ///
  /// A care-tag scan should state this whenever the wash tub is legible, and
  /// state [Agitation.normal] for a tub with no bars beneath it — under ISO
  /// 3758 the *absence* of bars means normal agitation, it does not mean the
  /// label is silent. Leaving it null instead makes every ordinary garment
  /// inherit the conservative default and be recommended a gentle cycle it
  /// does not need, which under-cleans and erodes trust in the advice.
  final Agitation? agitation;
  final BleachAllowance? bleach;
  final bool? tumbleDryAllowed;
  final TumbleDryHeat? tumbleDryHeat;
  final NaturalDryMethod? naturalDry;
  final bool? dryInShade;
  final bool? doNotWring;
  final IronTemperature? ironTemperature;
  final bool? steamAllowed;
  final bool? doNotDryClean;
  final Set<CareWarning> warnings;

  /// Folds this constraint into [base], keeping whichever is safer per field.
  CareInstructions applyTo(CareInstructions base) {
    final constrained = CareInstructions(
      wash: WashCare(
        method: method ?? base.wash.method,
        maxTempC: maxTempC ?? base.wash.maxTempC,
        agitation: agitation ?? base.wash.agitation,
      ),
      bleach: bleach ?? base.bleach,
      dry: DryCare(
        tumbleDryAllowed: tumbleDryAllowed ?? base.dry.tumbleDryAllowed,
        tumbleDryHeat: tumbleDryHeat ?? base.dry.tumbleDryHeat,
        naturalDry: naturalDry ?? base.dry.naturalDry,
        dryInShade: dryInShade ?? base.dry.dryInShade,
        doNotWring: doNotWring ?? base.dry.doNotWring,
      ),
      iron: IronCare(
        temperature: ironTemperature ?? base.iron.temperature,
        steamAllowed: steamAllowed ?? base.iron.steamAllowed,
      ),
      professional: ProfessionalCare(
        solvent: base.professional.solvent,
        gentleCycle: base.professional.gentleCycle,
        doNotDryClean: doNotDryClean ?? base.professional.doNotDryClean,
      ),
      warnings: {...base.warnings, ...warnings},
    );
    // Merging rather than returning `constrained` directly guarantees the rule
    // can only tighten: if the base was already stricter on some field, the
    // base value survives.
    return base.restrictiveMerge(constrained);
  }

  /// Replaces the fields this constraint states, ignoring whether the result
  /// is safer.
  ///
  /// Reserved for authoritative sources — a scanned care label or the user.
  /// A manufacturer stating "machine wash 40, tumble low" on a superwash wool
  /// jumper knows something the generic wool rule does not, and forcing our
  /// rule over their instruction would be both wrong and infuriating. Warnings
  /// still accumulate, since they are advisory rather than contradictory.
  CareInstructions overrideOnto(CareInstructions base) => CareInstructions(
        wash: WashCare(
          method: method ?? base.wash.method,
          maxTempC: maxTempC ?? base.wash.maxTempC,
          agitation: agitation ?? base.wash.agitation,
        ),
        bleach: bleach ?? base.bleach,
        dry: DryCare(
          tumbleDryAllowed: tumbleDryAllowed ?? base.dry.tumbleDryAllowed,
          tumbleDryHeat: tumbleDryHeat ?? base.dry.tumbleDryHeat,
          naturalDry: naturalDry ?? base.dry.naturalDry,
          dryInShade: dryInShade ?? base.dry.dryInShade,
          doNotWring: doNotWring ?? base.dry.doNotWring,
        ),
        iron: IronCare(
          temperature: ironTemperature ?? base.iron.temperature,
          steamAllowed: steamAllowed ?? base.iron.steamAllowed,
        ),
        professional: ProfessionalCare(
          solvent: base.professional.solvent,
          gentleCycle: base.professional.gentleCycle,
          doNotDryClean: doNotDryClean ?? base.professional.doNotDryClean,
        ),
        warnings: {...base.warnings, ...warnings},
      );

  /// Which care fields this constraint actually states.
  ///
  /// Lets the resolver report where a label overrode a rule, and drives the
  /// "parts of this label were illegible" prompt.
  Set<String> get statedFields => {
        if (method != null) 'wash.method',
        if (maxTempC != null) 'wash.maxTempC',
        if (agitation != null) 'wash.agitation',
        if (bleach != null) 'bleach',
        if (tumbleDryAllowed != null) 'dry.tumbleDryAllowed',
        if (tumbleDryHeat != null) 'dry.tumbleDryHeat',
        if (naturalDry != null) 'dry.naturalDry',
        if (dryInShade != null) 'dry.dryInShade',
        if (doNotWring != null) 'dry.doNotWring',
        if (ironTemperature != null) 'iron.temperature',
        if (steamAllowed != null) 'iron.steamAllowed',
        if (doNotDryClean != null) 'professional.doNotDryClean',
      };

  bool get statesNothing => statedFields.isEmpty && warnings.isEmpty;

  Map<String, Object?> toJson() => {
        if (method != null) 'method': method!.name,
        if (maxTempC != null) 'maxTempC': maxTempC,
        if (agitation != null) 'agitation': agitation!.name,
        if (bleach != null) 'bleach': bleach!.name,
        if (tumbleDryAllowed != null) 'tumbleDryAllowed': tumbleDryAllowed,
        if (tumbleDryHeat != null) 'tumbleDryHeat': tumbleDryHeat!.name,
        if (naturalDry != null) 'naturalDry': naturalDry!.name,
        if (dryInShade != null) 'dryInShade': dryInShade,
        if (doNotWring != null) 'doNotWring': doNotWring,
        if (ironTemperature != null) 'ironTemperature': ironTemperature!.name,
        if (steamAllowed != null) 'steamAllowed': steamAllowed,
        if (doNotDryClean != null) 'doNotDryClean': doNotDryClean,
        if (warnings.isNotEmpty)
          'warnings': [for (final warning in warnings) warning.name],
      };

  /// Reads a constraint from the wire.
  ///
  /// Lives in the core rather than in the app's API client because the
  /// absent-versus-null distinction is a domain invariant, not a transport
  /// detail: a missing key means the label was silent and the rule table
  /// should fill the gap, while a present one overrides it. A second parser
  /// elsewhere would eventually get that backwards, and the failure mode is a
  /// garment washed at the wrong temperature.
  ///
  /// A key that is present but null is therefore treated as absent — that is
  /// what a JSON encoder that does not strip nulls produces, and reading it as
  /// a stated value would invent an instruction the label never gave.
  static CareConstraint fromJson(Map<String, Object?> json) {
    T? read<T>(String key, T Function(Object raw) decode) {
      final raw = json[key];
      return raw == null ? null : decode(raw);
    }

    return CareConstraint(
      method: read('method', (r) => WashMethod.values.byName(r as String)),
      maxTempC: read('maxTempC', (r) => (r as num).toInt()),
      agitation: read('agitation', (r) => Agitation.values.byName(r as String)),
      bleach: read('bleach', (r) => BleachAllowance.values.byName(r as String)),
      tumbleDryAllowed: read('tumbleDryAllowed', (r) => r as bool),
      tumbleDryHeat: read(
          'tumbleDryHeat', (r) => TumbleDryHeat.values.byName(r as String)),
      naturalDry: read(
          'naturalDry', (r) => NaturalDryMethod.values.byName(r as String)),
      dryInShade: read('dryInShade', (r) => r as bool),
      doNotWring: read('doNotWring', (r) => r as bool),
      ironTemperature: read(
        'ironTemperature',
        (r) => IronTemperature.values.byName(r as String),
      ),
      steamAllowed: read('steamAllowed', (r) => r as bool),
      doNotDryClean: read('doNotDryClean', (r) => r as bool),
      warnings: {
        for (final raw in (json['warnings'] as List<Object?>?) ?? const [])
          CareWarning.values.byName(raw! as String),
      },
    );
  }

  @override
  String toString() => 'CareConstraint(${[
        if (method != null) 'method=${method!.name}',
        if (maxTempC != null) 'maxTemp=$maxTempC',
        if (agitation != null) 'agitation=${agitation!.name}',
        if (tumbleDryAllowed != null) 'tumble=$tumbleDryAllowed',
        if (ironTemperature != null) 'iron=${ironTemperature!.name}',
        if (warnings.isNotEmpty) 'warnings=${warnings.length}',
      ].join(', ')})';
}

/// One piece of care knowledge.
final class CareRule {
  const CareRule({
    required this.id,
    required this.appliesWhen,
    required this.imposes,
    required this.rationale,
    this.priority = 0,
  });

  /// Stable identifier, used in tests and to explain decisions.
  final String id;

  /// Whether this rule has anything to say about the item.
  final bool Function(ItemFacts facts) appliesWhen;

  /// What the rule requires when it applies.
  final CareConstraint imposes;

  /// Why, in words a user would accept. Surfaced in the app, so it must be a
  /// real explanation and not a restatement of the rule.
  final String rationale;

  /// Higher priority rules are reported first when explaining a decision.
  /// Does not affect the outcome — constraints only ever tighten, so the
  /// result is independent of order.
  final int priority;

  @override
  String toString() => 'CareRule($id)';
}

/// Supplies the active rule set.
///
/// The seam for over-the-air rule updates: a future implementation can fetch
/// serialized rules from a server and cache them, without the evaluator or any
/// caller changing.
abstract interface class RuleSource {
  List<CareRule> get rules;
}

/// A fixed, compiled-in rule set.
final class StaticRuleSource implements RuleSource {
  const StaticRuleSource(this.rules);

  @override
  final List<CareRule> rules;
}
