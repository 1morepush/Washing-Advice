/// The default care rule table.
///
/// This file is the product's encoded textile knowledge. Each entry is a claim
/// about how a material or garment behaves, and each carries the explanation
/// shown to the user. Adding knowledge means adding a row here.
///
/// The rules are conservative by design. Where sources differ on whether
/// something is survivable, the gentler instruction is chosen: the cost of
/// over-caution is a slower dry, and the cost of under-caution is a ruined
/// garment.
library;

import '../../wardrobe/model/condition.dart';
import '../../wardrobe/model/fabric.dart';
import '../../wardrobe/model/item_attributes.dart';
import '../../wardrobe/model/item_color.dart';
import '../model/care_symbols.dart';
import 'care_rule.dart';

/// The compiled-in rule set.
const RuleSource defaultRuleSource = StaticRuleSource(defaultCareRules);

/// Every rule the system applies, grouped by what drives it.
const List<CareRule> defaultCareRules = [
  // --- Protein fibres ----------------------------------------------------
  CareRule(
    id: 'protein.felting',
    priority: 100,
    appliesWhen: _feltsWithAgitation,
    imposes: CareConstraint(
      maxTempC: 30,
      agitation: Agitation.veryMild,
      tumbleDryAllowed: false,
      tumbleDryHeat: TumbleDryHeat.noHeat,
      naturalDry: NaturalDryMethod.flatDry,
      doNotWring: true,
      warnings: {CareWarning.reshapeWhileDamp},
    ),
    rationale: 'Wool and cashmere fibers have microscopic scales that lock '
        'together under heat and agitation. Once felted, a garment shrinks '
        'permanently and cannot be restored.',
  ),
  CareRule(
    id: 'protein.no_chlorine',
    priority: 95,
    appliesWhen: _isProteinFibre,
    imposes: CareConstraint(bleach: BleachAllowance.none),
    rationale: 'Chlorine bleach dissolves protein fibers such as wool and '
        'silk, yellowing and weakening them.',
  ),
  CareRule(
    id: 'silk.gentle',
    priority: 90,
    appliesWhen: _containsSilk,
    imposes: CareConstraint(
      method: WashMethod.hand,
      maxTempC: 30,
      agitation: Agitation.veryMild,
      tumbleDryAllowed: false,
      naturalDry: NaturalDryMethod.flatDry,
      dryInShade: true,
      doNotWring: true,
      ironTemperature: IronTemperature.low,
      steamAllowed: false,
      warnings: {CareWarning.doNotUseSoftener},
    ),
    rationale: 'Silk loses strength when wet and is dulled by heat, sunlight '
        'and alkaline detergent. Direct sun also yellows it.',
  ),
  CareRule(
    id: 'leather.no_domestic_wash',
    priority: 120,
    appliesWhen: _containsLeather,
    imposes: CareConstraint(
      method: WashMethod.doNotWash,
      tumbleDryAllowed: false,
      naturalDry: NaturalDryMethod.flatDry,
      dryInShade: true,
      ironTemperature: IronTemperature.none,
      warnings: {CareWarning.washSeparately},
    ),
    rationale: 'Water strips the oils from leather, leaving it stiff and '
        'cracked. It needs specialist cleaning.',
  ),
  CareRule(
    id: 'down.special_handling',
    priority: 85,
    appliesWhen: _containsDown,
    imposes: CareConstraint(
      maxTempC: 30,
      agitation: Agitation.veryMild,
      tumbleDryAllowed: true,
      tumbleDryHeat: TumbleDryHeat.low,
      doNotWring: true,
      warnings: {CareWarning.doNotUseSoftener},
    ),
    rationale: 'Down must be tumble dried on low to break up clumps and fully '
        'dry the clusters — left damp it will mildew and lose loft. Softener '
        'coats the down and flattens it.',
  ),

  // --- Regenerated cellulosics -------------------------------------------
  CareRule(
    id: 'cellulosic.weak_when_wet',
    priority: 80,
    appliesWhen: _weakensWhenWet,
    imposes: CareConstraint(
      maxTempC: 30,
      agitation: Agitation.veryMild,
      tumbleDryAllowed: false,
      naturalDry: NaturalDryMethod.flatDry,
      doNotWring: true,
    ),
    rationale: 'Viscose and acetate lose much of their strength when wet, so '
        'wringing or a hard spin tears the fibers and stretches the garment '
        'out of shape.',
  ),

  // --- Synthetics ---------------------------------------------------------
  CareRule(
    id: 'elastane.heat_degrades',
    priority: 75,
    appliesWhen: _containsElastane,
    imposes: CareConstraint(
      maxTempC: 40,
      tumbleDryHeat: TumbleDryHeat.low,
      ironTemperature: IronTemperature.low,
      warnings: {CareWarning.doNotUseSoftener},
    ),
    rationale: 'Even a few percent of elastane will break down in high heat, '
        'and the garment permanently loses its stretch and shape.',
  ),
  CareRule(
    id: 'thermoplastic.melts',
    priority: 70,
    appliesWhen: _isThermoplastic,
    imposes: CareConstraint(
      ironTemperature: IronTemperature.low,
      tumbleDryHeat: TumbleDryHeat.medium,
    ),
    rationale: 'Polyester, nylon and acrylic melt rather than scorch. A hot '
        'iron will glaze or hole the fabric instantly.',
  ),
  CareRule(
    id: 'synthetic.holds_odour',
    priority: 40,
    appliesWhen: _holdsOdour,
    imposes: CareConstraint(warnings: {CareWarning.doNotUseSoftener}),
    rationale: 'Synthetics trap body oils that cause odor, and fabric '
        'softener leaves a coating that seals them in. Skip the softener.',
  ),
  CareRule(
    id: 'synthetic.pills',
    priority: 35,
    appliesWhen: _pillsReadily,
    imposes: CareConstraint(
      agitation: Agitation.mild,
      warnings: {CareWarning.washInsideOut},
    ),
    rationale: 'Acrylic pills where it rubs. Washing inside out and on a '
        'milder cycle moves the abrasion to the side nobody sees.',
  ),

  // --- Garment type -------------------------------------------------------
  CareRule(
    id: 'type.bra_structure',
    priority: 65,
    appliesWhen: _isBra,
    imposes: CareConstraint(
      method: WashMethod.hand,
      maxTempC: 30,
      agitation: Agitation.veryMild,
      tumbleDryAllowed: false,
      naturalDry: NaturalDryMethod.flatDry,
      warnings: {CareWarning.useMeshBag, CareWarning.closeFastenings},
    ),
    rationale: 'Machine agitation bends underwires out of shape and the hooks '
        'snag other garments. A mesh bag solves both.',
  ),
  CareRule(
    id: 'type.swimwear_chlorine',
    priority: 60,
    appliesWhen: _isSwimwear,
    imposes: CareConstraint(
      method: WashMethod.hand,
      maxTempC: 30,
      agitation: Agitation.veryMild,
      bleach: BleachAllowance.none,
      tumbleDryAllowed: false,
      naturalDry: NaturalDryMethod.flatDry,
      dryInShade: true,
      warnings: {CareWarning.doNotUseSoftener},
    ),
    rationale: 'Chlorine, heat and sunlight all attack swimwear elastane. '
        'Rinse in cool water and dry out of direct sun.',
  ),
  CareRule(
    id: 'type.lint_producer',
    priority: 50,
    appliesWhen: _producesLint,
    // Deliberately *not* `washSeparately`. Towels should be washed with other
    // towels, not one per load — and keeping them away from lint-attracting
    // fabrics is already enforced structurally by `SeparationRules`, which can
    // reason about what else is in the drum. Setting the warning here would
    // isolate every single towel into its own wash.
    imposes: CareConstraint(warnings: {CareWarning.doNotUseSoftener}),
    rationale: 'Toweling sheds fibers that cling to smooth and dark fabrics, '
        'so it is kept away from them. Softener also ruins a towel\'s '
        'absorbency.',
  ),
  CareRule(
    id: 'type.activewear_gentle',
    priority: 45,
    appliesWhen: _isActivewear,
    imposes: CareConstraint(
      maxTempC: 40,
      agitation: Agitation.mild,
      tumbleDryHeat: TumbleDryHeat.low,
      warnings: {CareWarning.washInsideOut, CareWarning.doNotUseSoftener},
    ),
    rationale: 'Technical fabrics rely on a wicking finish that softener and '
        'high heat destroy. Inside out puts the sweat-facing surface against '
        'the water.',
  ),

  // --- Colour -------------------------------------------------------------
  CareRule(
    id: 'colour.new_bright_bleeds',
    priority: 55,
    appliesWhen: _isNewAndSaturated,
    imposes: CareConstraint(
      maxTempC: 30,
      warnings: {
        CareWarning.washSeparately,
        CareWarning.washWithLikeColours,
      },
    ),
    rationale: 'Saturated dye runs heavily in the first few washes. Wash this '
        'separately until it stops bleeding.',
  ),
  CareRule(
    id: 'colour.dark_fading',
    priority: 30,
    appliesWhen: _isDark,
    imposes: CareConstraint(
      maxTempC: 30,
      dryInShade: true,
      warnings: {CareWarning.washInsideOut},
    ),
    rationale: 'Dark dyes fade with heat, abrasion and sunlight. A cool wash '
        'inside out keeps them looking new far longer.',
  ),
  CareRule(
    id: 'colour.whites_brightening',
    priority: 25,
    appliesWhen: _isWhite,
    imposes: CareConstraint(warnings: {CareWarning.washWithLikeColours}),
    rationale: 'Whites pick up dye from anything darker sharing the load, and '
        'gray out permanently once they do.',
  ),

  // --- Condition ----------------------------------------------------------
  CareRule(
    id: 'condition.damaged_gentler',
    priority: 110,
    appliesWhen: _isDamaged,
    imposes: CareConstraint(
      maxTempC: 30,
      agitation: Agitation.veryMild,
      tumbleDryAllowed: false,
      warnings: {CareWarning.useMeshBag, CareWarning.washInsideOut},
    ),
    rationale: 'A care label describes a new garment. With existing damage, a '
        'normal cycle will make the tear or hole considerably worse.',
  ),
];

// Predicates are named top-level functions rather than inline closures so the
// rule list can stay `const`, and so each is separately testable.

bool _feltsWithAgitation(ItemFacts f) =>
    f.hasTrait((fiber) => fiber.feltsWithAgitation);

bool _isProteinFibre(ItemFacts f) => f.hasTrait((fiber) => fiber.isProtein);

bool _containsSilk(ItemFacts f) => f.hasEnough(Fiber.silk);

bool _containsLeather(ItemFacts f) => f.hasEnough(Fiber.leather);

bool _containsDown(ItemFacts f) => f.hasEnough(Fiber.down);

bool _weakensWhenWet(ItemFacts f) =>
    f.hasTrait((fiber) => fiber.weakensWhenWet);

bool _containsElastane(ItemFacts f) => f.hasEnough(Fiber.elastane);

bool _isThermoplastic(ItemFacts f) =>
    f.hasTrait((fiber) => fiber.isThermoplastic);

bool _holdsOdour(ItemFacts f) => f.hasTrait((fiber) => fiber.holdsOdour);

bool _pillsReadily(ItemFacts f) => f.hasTrait((fiber) => fiber.pillsReadily);

bool _isBra(ItemFacts f) => f.type == ItemType.bra;

bool _isSwimwear(ItemFacts f) => f.type == ItemType.swimwear;

bool _producesLint(ItemFacts f) => f.type.producesLint;

bool _isActivewear(ItemFacts f) => f.type.category == ItemCategory.activewear;

bool _isNewAndSaturated(ItemFacts f) =>
    f.isNew && (f.colors?.isLikelyToBleed ?? false);

bool _isDark(ItemFacts f) => f.colorClass == ColorClass.darks;

bool _isWhite(ItemFacts f) => f.colorClass == ColorClass.whites;

bool _isDamaged(ItemFacts f) =>
    f.conditionGrade == ConditionGrade.damaged ||
    f.conditionGrade == ConditionGrade.endOfLife;
