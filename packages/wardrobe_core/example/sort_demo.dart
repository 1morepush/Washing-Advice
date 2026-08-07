/// Runs a realistic pile of laundry through the sorting engine and prints the
/// result, so the behaviour can be inspected rather than only asserted.
///
///     dart run example/sort_demo.dart
library;

import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final washer = seededWashers['LG']!;
  final dryer = seededDryers['LG']!;
  final sorter = LaundrySorter(clock: FixedClock(DateTime.utc(2026, 3, 15)));

  final pile = _buildPile();
  final plan = sorter.sort(pile, washer: washer, dryer: dryer);

  _printHeader(pile, washer, dryer);
  _printPlan(plan);
  _printCareTranslation(pile);
}

void _printHeader(
  List<WardrobeItem> pile,
  WasherProfile washer,
  DryerProfile dryer,
) {
  print('═' * 78);
  print('  LAUNDRY PLAN');
  print('═' * 78);
  print('  Pile:   ${pile.length} items');
  print('  Washer: ${washer.displayName} (${washer.capacityKg} kg)');
  print('  Dryer:  ${dryer.displayName}');
  print('');
}

void _printPlan(LaundryPlan plan) {
  print('  ${plan.loadCount} loads for ${plan.itemsSorted} items.');
  print('');

  for (var i = 0; i < plan.loads.length; i++) {
    final load = plan.loads[i];
    print('─' * 78);
    print('  LOAD ${i + 1}: ${load.label}');
    print('─' * 78);

    for (final item in load.items) {
      final composition = item.composition.value.label;
      print('    • ${item.displayName.padRight(28)} $composition');
    }
    print('    ${load.totalWeightKg.toStringAsFixed(1)} kg');
    print('');

    if (load.washerSetting case final WasherSetting wash) {
      print('    WASH');
      print('      Programme:   ${wash.programName}');
      print('      Temperature: ${wash.temperatureLabel}');
      print('      Spin:        ${wash.spinLabel}');
      for (final entry in wash.options.entries) {
        print('      ${entry.key.padRight(12)} ${entry.value ? "ON" : "OFF"}');
      }
      for (final note in wash.notes) {
        print('      ${_severityMark(note.severity)} ${note.text}');
      }
    }

    if (load.dryerSetting case final DryerSetting dry) {
      print('    DRY');
      if (dry.isAirDry) {
        print('      Do not tumble dry');
      } else {
        print('      Programme: ${dry.programName}');
        print('      Heat:      ${dry.heat.label}');
        print('      Control:   ${dry.usesSensor ? "Sensor dry" : "Timed"}');
      }
      for (final note in dry.notes) {
        print('      ${_severityMark(note.severity)} ${note.text}');
      }
    }

    if (load.rationale.isNotEmpty) {
      print('    WHY');
      for (final reason in load.rationale) {
        print('      · ${reason.reason}');
      }
    }
    print('');
  }

  if (plan.unassigned.isNotEmpty) {
    print('─' * 78);
    print('  NOT WASHED');
    print('─' * 78);
    for (final left in plan.unassigned) {
      final marker = left.needsUserAction ? '!' : '·';
      print('    $marker ${left.item.displayName}');
      print('      ${left.reason}');
    }
    print('');
  }
}

/// Shows the care-label translation for one item — the Phase 2 promise that a
/// user never has to decode a symbol.
void _printCareTranslation(List<WardrobeItem> pile) {
  final sweater = pile.firstWhere((i) => i.id.value == 'wool-sweater');
  const language = CareLanguage();

  print('═' * 78);
  print('  CARE LABEL, IN PLAIN ENGLISH — ${sweater.displayName}');
  print('═' * 78);
  print('  ${sweater.composition.value.label}');
  print('');
  for (final sentence in language.describe(sweater.effectiveCare)) {
    final mark = sentence.isProhibition ? '✕' : '•';
    print('  $mark ${sentence.text}');
  }
  print('');

  // And the rules that produced it, each with its reasoning.
  final evaluation = const CareRuleEvaluator().evaluate(
    ItemFacts(
      type: sweater.type.value,
      composition: sweater.composition.value,
      colors: sweater.colors.value,
    ),
    base: sweater.care.instructions,
  );
  if (evaluation.applied.isNotEmpty) {
    print('  WHY');
    for (final rule in evaluation.applied) {
      print('  · ${rule.rationale}');
    }
    print('');
  }
}

String _severityMark(NoteSeverity severity) => switch (severity) {
      NoteSeverity.info => 'i',
      NoteSeverity.caution => '!',
      NoteSeverity.warning => '⚠',
    };

/// A pile designed to exercise every separation rule at once.
List<WardrobeItem> _buildPile() {
  final now = DateTime.utc(2026, 3, 15);

  /// Builds an item the way the app actually would: the care label is a
  /// partial [CareConstraint] (only what was legible), and [CareResolver]
  /// combines it with the fibre rule table to produce the stored profile.
  ///
  /// Setting `care` directly would skip the rules entirely and quietly produce
  /// unsafe advice — the 13% elastane in the leggings below only caps the
  /// dryer heat because the resolver runs.
  WardrobeItem item({
    required String id,
    required String name,
    required ItemType type,
    required Map<Fiber, int> composition,
    required ItemColor colour,
    required CareConstraint label,
    String? brand,
    int timesWashed = 12,
  }) {
    final fabric = FabricComposition(composition);
    final palette = ColorPalette([colour]);

    final resolution = const CareResolver().resolve(
      facts: ItemFacts(
        type: type,
        composition: fabric,
        colors: palette,
        timesWashed: timesWashed,
      ),
      fromLabel: label,
    );

    return WardrobeItem(
      id: ItemId(id),
      name: name,
      type: Confident(type, confidence: 0.94, source: Provenance.aiInference),
      composition: Confident(
        fabric,
        confidence: 0.92,
        source: Provenance.tagScan,
      ),
      colors: Confident(
        palette,
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      brand: brand == null ? null : Confident.fromUser(brand),
      care: resolution.profile,
      usage: UsageStats(timesWashed: timesWashed, timesWorn: timesWashed * 2),
      addedAt: now,
      updatedAt: now,
    );
  }

  // Care labels as they are actually read: a set of stated facts, with silence
  // where a symbol was absent or illegible. Nulls are filled by the rule table.
  const everydayLabel = CareConstraint(
    method: WashMethod.machine,
    maxTempC: 40,
    // A tub with no bars under it: normal agitation, explicitly stated.
    agitation: Agitation.normal,
    bleach: BleachAllowance.nonChlorineOnly,
    tumbleDryAllowed: true,
    tumbleDryHeat: TumbleDryHeat.medium,
    ironTemperature: IronTemperature.high,
  );

  const sturdyLabel = CareConstraint(
    method: WashMethod.machine,
    maxTempC: 60,
    agitation: Agitation.normal,
    bleach: BleachAllowance.any,
    tumbleDryAllowed: true,
    tumbleDryHeat: TumbleDryHeat.high,
    ironTemperature: IronTemperature.high,
  );

  // A worn activewear label: the wash tub is legible but the drying symbol has
  // rubbed away. The nulls are real gaps, and the rule table fills them — the
  // 13% elastane is what caps the dryer heat here.
  const wornActivewearLabel = CareConstraint(
    method: WashMethod.machine,
    maxTempC: 40,
    agitation: Agitation.normal,
  );

  const woolLabel = CareConstraint(
    method: WashMethod.hand,
    maxTempC: 30,
    agitation: Agitation.veryMild,
    bleach: BleachAllowance.none,
    tumbleDryAllowed: false,
    naturalDry: NaturalDryMethod.flatDry,
    doNotWring: true,
    ironTemperature: IronTemperature.low,
    steamAllowed: false,
  );

  return [
    item(
      id: 'white-shirt',
      name: 'White dress shirt',
      type: ItemType.dressShirt,
      composition: {Fiber.cotton: 100},
      colour: ItemColor.fromHex('#FAFAFA', name: 'White'),
      label: everydayLabel,
    ),
    item(
      id: 'white-tee',
      name: 'White t-shirt',
      type: ItemType.tShirt,
      composition: {Fiber.cotton: 100},
      colour: ItemColor.fromHex('#F5F5F0', name: 'White'),
      label: everydayLabel,
    ),
    item(
      id: 'grey-hoodie',
      name: 'Grey Nike hoodie',
      type: ItemType.hoodie,
      composition: {Fiber.cotton: 80, Fiber.polyester: 20},
      colour: ItemColor.fromHex('#8A8A8A', name: 'Grey'),
      label: everydayLabel,
      brand: 'Nike',
    ),
    item(
      id: 'black-jeans',
      name: 'Black jeans',
      type: ItemType.jeans,
      composition: {Fiber.cotton: 98, Fiber.elastane: 2},
      colour: ItemColor.fromHex('#1C1C1C', name: 'Black'),
      label: sturdyLabel,
    ),
    item(
      id: 'navy-tee',
      name: 'Navy t-shirt',
      type: ItemType.tShirt,
      composition: {Fiber.cotton: 100},
      colour: ItemColor.fromHex('#1F2A44', name: 'Navy'),
      label: everydayLabel,
    ),
    item(
      id: 'wool-sweater',
      name: 'Wool sweater',
      type: ItemType.sweater,
      composition: {Fiber.wool: 70, Fiber.acrylic: 30},
      colour: ItemColor.fromHex('#5A4632', name: 'Brown'),
      label: woolLabel,
    ),
    item(
      id: 'silk-blouse',
      name: 'Silk blouse',
      type: ItemType.blouse,
      composition: {Fiber.silk: 100},
      colour: ItemColor.fromHex('#EFE3D0', name: 'Ivory'),
      label: woolLabel,
    ),
    item(
      id: 'new-red-tee',
      name: 'New red t-shirt',
      type: ItemType.tShirt,
      composition: {Fiber.cotton: 100},
      colour: ItemColor.fromHex('#C81E1E', name: 'Red'),
      label: everydayLabel,
      timesWashed: 0,
    ),
    item(
      id: 'bath-towel',
      name: 'Bath towel',
      type: ItemType.bathTowel,
      composition: {Fiber.cotton: 100},
      colour: ItemColor.fromHex('#EDEDE8', name: 'White'),
      label: sturdyLabel,
    ),
    item(
      id: 'gym-leggings',
      name: 'Gym leggings',
      type: ItemType.activewearBottom,
      composition: {Fiber.polyester: 87, Fiber.elastane: 13},
      colour: ItemColor.fromHex('#232323', name: 'Black'),
      label: wornActivewearLabel,
    ),
    item(
      id: 'running-shoes',
      name: 'Running shoes',
      type: ItemType.sneakers,
      composition: {Fiber.polyester: 100},
      colour: ItemColor.fromHex('#BBBBBB', name: 'Grey'),
      label: everydayLabel,
    ),
  ];
}
