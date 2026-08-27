/// The laundry sorting engine.
///
/// Takes a pile of items and produces the loads to run, the settings for each,
/// and the reasoning behind them. Entirely deterministic and offline: no model
/// is consulted, so the same pile always yields the same plan and every
/// decision can be traced to a rule.
///
/// ## The algorithm
///
/// 1. **Partition.** Set aside anything that is not laundry (shoes, bags) or
///    must not be washed, each with a reason.
/// 2. **Bind.** Items linked by `RelationKind.washTogetherWith` or
///    `suitSet` are fused into inseparable units, so a suit is never split.
/// 3. **Isolate.** Items whose label demands separate washing, or whose new dye
///    is still bleeding, get their own load.
/// 4. **Bucket.** Group the rest by [WashGroupKey] — method, colour, fabric
///    class and temperature band.
/// 5. **Merge.** Greedily combine buckets that no separation rule forbids and
///    that the drum can hold, largest first, so the user runs fewer loads.
/// 6. **Split.** Break up anything over capacity.
/// 7. **Resolve.** For each load compute the most restrictive care across its
///    members, derive the wash and dry specs, translate them into settings for
///    the user's machines, and record why.
library;

import '../../care/model/care_instructions.dart';
import '../../care/model/care_symbols.dart';
import '../../care/model/wash_spec.dart';
import '../../machines/model/dryer_profile.dart';
import '../../machines/model/machine_setting.dart';
import '../../machines/model/washer_profile.dart';
import '../../machines/program_matcher.dart';
import '../../shared/clock.dart';
import '../../shared/ids.dart';
import '../../wardrobe/model/relationship.dart';
import '../../wardrobe/model/wardrobe_item.dart';
import '../model/laundry_load.dart';
import 'separation_rules.dart';

/// Tunable preferences for how aggressively to combine loads.
final class SortingPreferences {
  const SortingPreferences({
    this.fillFraction = 0.8,
    this.mergeAcrossColorClasses = true,
    this.splitDrying = false,
    this.minimumItemsPerLoad = 1,
  });

  /// How full to fill the drum, as a fraction of its rated capacity.
  ///
  /// Defaults to 80%: a packed drum does not let water and detergent
  /// circulate, and clothes come out still dirty.
  final double fillFraction;

  /// Whether to merge groups whose colour classes differ but do not conflict —
  /// lights with brights, for instance.
  final bool mergeAcrossColorClasses;

  /// Whether a load may be split into more than one drying group.
  ///
  /// Off by default, which is what every earlier version did: the load dries
  /// as one, at the most restrictive spec any member demands. That is safe and
  /// it is wasteful — a single air-dry-only garment sends the whole drum to
  /// the airer.
  ///
  /// On, the tumble-dryable part goes in the machine and the rest is hung. The
  /// clothes are better served and the user has more to do, which is why this
  /// is a preference rather than a decision made for them.
  final bool splitDrying;

  /// Loads smaller than this are reported but flagged as inefficient.
  final int minimumItemsPerLoad;
}

/// Sorts laundry into loads.
final class LaundrySorter {
  const LaundrySorter({
    this.matcher = const ProgramMatcher(),
    this.clock = const SystemClock(),
    this.preferences = const SortingPreferences(),
  });

  final ProgramMatcher matcher;
  final Clock clock;
  final SortingPreferences preferences;

  /// Builds a plan for [items].
  ///
  /// [washer] and [dryer] are optional: without them the plan still groups
  /// items and states abstract requirements, it just cannot name a programme.
  /// That keeps the feature useful before the user has set their machines up.
  LaundryPlan sort(
    List<WardrobeItem> items, {
    WasherProfile? washer,
    DryerProfile? dryer,
    RelationshipGraph? relationships,
  }) {
    final unassigned = <UnassignedItem>[];
    final launderable = <WardrobeItem>[];

    // 1. Partition.
    for (final item in items) {
      final exclusion = _exclusionReason(item);
      if (exclusion != null) {
        unassigned.add(exclusion);
      } else {
        launderable.add(item);
      }
    }

    if (launderable.isEmpty) {
      return LaundryPlan(
        loads: const [],
        unassigned: unassigned,
        generatedAt: clock.now(),
      );
    }

    // 2. Bind items that must stay together.
    final units = _bindUnits(launderable, relationships);

    // 3 + 4. Isolate, then bucket the remainder.
    final isolated = <List<WardrobeItem>>[];
    final buckets = <WashGroupKey, List<WardrobeItem>>{};

    for (final unit in units) {
      if (unit.any(SeparationRules.requiresOwnLoad)) {
        isolated.add(unit);
        continue;
      }
      // A bound unit is keyed by its most restrictive member so the whole unit
      // lands in a bucket that suits all of it.
      final key = _keyForUnit(unit);
      buckets.putIfAbsent(key, () => []).addAll(unit);
    }

    // 5 + 6. Merge compatible buckets, then split by capacity.
    final capacityKg = _effectiveCapacity(washer);
    final groups = <List<WardrobeItem>>[
      ...isolated,
      ..._mergeBuckets(buckets, capacityKg),
    ];

    final finalGroups = <List<WardrobeItem>>[];
    for (final group in groups) {
      finalGroups.addAll(_splitByCapacity(group, capacityKg));
    }

    // 7. Resolve each group into a load.
    final loads = <LaundryLoad>[];
    for (var index = 0; index < finalGroups.length; index++) {
      loads.add(
        _buildLoad(
          finalGroups[index],
          index: index,
          washer: washer,
          dryer: dryer,
          capacityKg: capacityKg,
        ),
      );
    }

    return LaundryPlan(
      loads: loads,
      unassigned: unassigned,
      generatedAt: clock.now(),
    );
  }

  // --- Step 1: partition ---------------------------------------------------

  UnassignedItem? _exclusionReason(WardrobeItem item) {
    if (!item.type.value.isWashable) {
      return UnassignedItem(
        item: item,
        reason: '${item.type.value.label} does not go in a washing machine.',
      );
    }
    if (item.effectiveCare.wash.method == WashMethod.doNotWash) {
      return UnassignedItem(
        item: item,
        reason: 'The care label says this must not be washed. It needs '
            'professional cleaning.',
      );
    }
    if (!item.lifecycle.isLaunderable) {
      return UnassignedItem(
        item: item,
        reason: 'This item is ${item.lifecycle.label.toLowerCase()} and is not '
            'available to wash.',
      );
    }
    if (item.needsCareTagScan) {
      return UnassignedItem(
        item: item,
        reason: 'Scan this item\'s care label so it can be sorted safely.',
        needsUserAction: true,
      );
    }
    return null;
  }

  // --- Step 2: bind --------------------------------------------------------

  /// Fuses items that must be washed together into single units.
  List<List<WardrobeItem>> _bindUnits(
    List<WardrobeItem> items,
    RelationshipGraph? relationships,
  ) {
    if (relationships == null || relationships.isEmpty) {
      return [
        for (final item in items) [item]
      ];
    }

    final byId = {for (final item in items) item.id: item};
    final assigned = <ItemId>{};
    final units = <List<WardrobeItem>>[];

    for (final item in items) {
      if (!assigned.add(item.id)) continue;
      final unit = <WardrobeItem>[item];
      for (final partnerId in relationships.mustWashWith(item.id)) {
        final partner = byId[partnerId];
        if (partner != null && assigned.add(partnerId)) {
          unit.add(partner);
        }
      }
      units.add(unit);
    }
    return units;
  }

  /// The key for a bound unit: the most restrictive across its members.
  WashGroupKey _keyForUnit(List<WardrobeItem> unit) {
    var key = WashGroupKey.of(unit.first);
    for (final item in unit.skip(1)) {
      final other = WashGroupKey.of(item);
      key = WashGroupKey(
        method: key.method.stricter(other.method),
        // Colour and fabric take the first member's, since a bound unit is a
        // single garment in practice (a suit, a jacket and its liner).
        colorClass: key.colorClass,
        fabricClass: key.fabricClass.leastRobust(other.fabricClass),
        temperatureBand:
            key.temperatureBand.index <= other.temperatureBand.index
                ? key.temperatureBand
                : other.temperatureBand,
      );
    }
    return key;
  }

  // --- Steps 5 and 6: merge and split -------------------------------------

  double _effectiveCapacity(WasherProfile? washer) =>
      (washer?.capacityKg ?? 7.0) * preferences.fillFraction;

  /// Greedily merges buckets that no separation rule forbids.
  ///
  /// Largest bucket first, so big natural groups anchor the loads and small
  /// odds and ends get folded into them rather than forming their own load.
  List<List<WardrobeItem>> _mergeBuckets(
    Map<WashGroupKey, List<WardrobeItem>> buckets,
    double capacityKg,
  ) {
    final ordered = buckets.entries.toList()
      ..sort((x, y) => y.value.length.compareTo(x.value.length));

    final merged = <List<WardrobeItem>>[];

    for (final entry in ordered) {
      var placed = false;
      for (final group in merged) {
        if (!preferences.mergeAcrossColorClasses &&
            WashGroupKey.of(group.first).colorClass != entry.key.colorClass) {
          continue;
        }
        if (SeparationRules.conflictBetweenGroups(entry.value, group) != null) {
          continue;
        }
        if (_weightKg(group) + _weightKg(entry.value) > capacityKg) continue;

        group.addAll(entry.value);
        placed = true;
        break;
      }
      if (!placed) merged.add([...entry.value]);
    }
    return merged;
  }

  double _weightKg(Iterable<WardrobeItem> items) =>
      items.fold(0.0, (total, item) => total + item.drumLoadGrams) / 1000.0;

  /// Breaks a group into drum-sized loads.
  ///
  /// Heaviest first, so each load is filled efficiently rather than leaving a
  /// final load holding one duvet.
  List<List<WardrobeItem>> _splitByCapacity(
    List<WardrobeItem> group,
    double capacityKg,
  ) {
    if (_weightKg(group) <= capacityKg) return [group];

    final remaining = [...group]
      ..sort((x, y) => y.drumLoadGrams.compareTo(x.drumLoadGrams));

    final loads = <List<WardrobeItem>>[];
    for (final item in remaining) {
      final target = loads.firstWhere(
        (load) => _weightKg(load) + item.drumLoadGrams / 1000.0 <= capacityKg,
        orElse: () {
          final fresh = <WardrobeItem>[];
          loads.add(fresh);
          return fresh;
        },
      );
      target.add(item);
    }
    return loads;
  }

  // --- Step 7: resolve -----------------------------------------------------

  LaundryLoad _buildLoad(
    List<WardrobeItem> items, {
    required int index,
    required double capacityKg,
    WasherProfile? washer,
    DryerProfile? dryer,
  }) {
    // Most restrictive care across every member: the load must be safe for its
    // most delicate item.
    var care = items.first.effectiveCare;
    for (final item in items.skip(1)) {
      care = care.restrictiveMerge(item.effectiveCare);
    }

    var fabricClass = items.first.fabricClass;
    for (final item in items.skip(1)) {
      fabricClass = fabricClass.leastRobust(item.fabricClass);
    }

    final weakWhenWet = items.any(
      (item) =>
          item.composition.value.hasDominantTrait((f) => f.weakensWhenWet),
    );

    final washSpec = WashSpec.from(care, fabricClass, weakWhenWet: weakWhenWet);
    final drySpec = DrySpec.from(care, fabricClass);

    final washerSetting =
        washer == null ? null : matcher.matchWash(washSpec, washer);
    final dryerSetting =
        dryer == null ? null : matcher.matchDry(drySpec, dryer);

    return LaundryLoad(
      id: LoadId('load.${index + 1}'),
      items: List.unmodifiable(items),
      effectiveCare: care,
      washSpec: washSpec,
      drySpec: drySpec,
      label: _labelFor(items, washSpec),
      totalWeightKg: _weightKg(items),
      washerSetting: washerSetting,
      dryerSetting: dryerSetting,
      dryingGroups: _dryingGroups(items, drySpec, dryerSetting, dryer),
      rationale: _explain(items, care, washSpec, drySpec, capacityKg),
    );
  }

  /// How this load divides for drying.
  ///
  /// One group unless the user asked for the split, which keeps every earlier
  /// version's behaviour intact: the load dries as one, at the most
  /// restrictive spec any member demands.
  ///
  /// Split, the division is by what a garment can actually take rather than by
  /// anything finer. Two tumble-dryable garments at different heats still dry
  /// together, at the cooler of the two — the point is to stop one air-dry-only
  /// garment holding back a whole drum, not to produce a group per garment.
  List<DryingGroup> _dryingGroups(
    List<WardrobeItem> items,
    DrySpec loadSpec,
    DryerSetting? loadSetting,
    DryerProfile? dryer,
  ) {
    DryingGroup group(List<WardrobeItem> members) {
      var spec = DrySpec.from(
        members.first.effectiveCare,
        members.first.fabricClass,
      );
      for (final item in members.skip(1)) {
        spec = spec.restrictiveMerge(
          DrySpec.from(item.effectiveCare, item.fabricClass),
        );
      }
      return DryingGroup(
        items: List.unmodifiable(members),
        spec: spec,
        dryerSetting: dryer == null ? null : matcher.matchDry(spec, dryer),
      );
    }

    if (!preferences.splitDrying) {
      return [
        DryingGroup(
          items: List.unmodifiable(items),
          spec: loadSpec,
          dryerSetting: loadSetting,
        ),
      ];
    }

    final tumble = <WardrobeItem>[];
    final air = <WardrobeItem>[];
    for (final item in items) {
      (item.effectiveCare.dry.tumbleDryAllowed ? tumble : air).add(item);
    }

    // Nothing to split when they all agree, and a lone group here must look
    // exactly like an unsplit one or the screen would announce a division
    // that does not exist.
    if (tumble.isEmpty || air.isEmpty) {
      return [
        DryingGroup(
          items: List.unmodifiable(items),
          spec: loadSpec,
          dryerSetting: loadSetting,
        ),
      ];
    }

    return [group(tumble), group(air)];
  }

  String _labelFor(List<WardrobeItem> items, WashSpec spec) {
    final key = WashGroupKey.of(items.first);
    final temperature = spec.maxTempC == null
        ? 'any temperature'
        : spec.maxTempC! <= 30
            ? 'cold'
            : spec.maxTempC! <= 40
                ? 'warm'
                : 'hot';
    final cycle = spec.method == WashMethod.hand
        ? 'hand wash'
        : spec.agitation == Agitation.normal
            ? 'normal'
            : spec.agitation.label.toLowerCase();
    return '${key.label} — $temperature, $cycle';
  }

  /// Builds the explanation for a load, naming the item responsible for each
  /// constraint wherever one item is to blame.
  List<LoadRationale> _explain(
    List<WardrobeItem> items,
    CareInstructions care,
    WashSpec washSpec,
    DrySpec drySpec,
    double capacityKg,
  ) {
    final rationale = <LoadRationale>[];

    // Temperature: find the item that forced the limit.
    if (care.wash.maxTempC case final int limit) {
      final driver = _itemDriving(
        items,
        (item) => item.effectiveCare.wash.maxTempC == limit,
      );
      rationale.add(
        LoadRationale(
          kind: RationaleKind.temperature,
          reason: driver == null
              ? 'Running at $limit°C, the warmest every item in this load can '
                  'take.'
              : 'Running at $limit°C because ${driver.displayName} must not be '
                  'washed hotter.',
          causedBy: driver?.id,
          causedByName: driver?.displayName,
        ),
      );
    }

    // Agitation.
    if (washSpec.agitation != Agitation.normal) {
      final driver = _itemDriving(
        items,
        (item) => item.effectiveCare.wash.agitation == washSpec.agitation,
      );
      rationale.add(
        LoadRationale(
          kind: RationaleKind.agitation,
          reason: driver == null
              ? 'Using a ${washSpec.agitation.label.toLowerCase()} cycle to '
                  'protect the load.'
              : 'Using a ${washSpec.agitation.label.toLowerCase()} cycle '
                  'because ${driver.displayName} needs gentle handling.',
          causedBy: driver?.id,
          causedByName: driver?.displayName,
        ),
      );
    }

    // Spin.
    if (washSpec.maxSpinRpm case final int limit) {
      final driver = _itemDriving(
        items,
        (item) =>
            item.composition.value.hasDominantTrait((f) => f.weakensWhenWet),
      );
      rationale.add(
        LoadRationale(
          kind: RationaleKind.spin,
          reason: driver == null
              ? 'Spin capped at $limit rpm to protect delicate fabrics.'
              : 'Spin capped at $limit rpm because ${driver.displayName} loses '
                  'strength when wet and a hard spin would stretch it.',
          causedBy: driver?.id,
          causedByName: driver?.displayName,
        ),
      );
    }

    // Isolation.
    if (items.length == 1) {
      final reason = SeparationRules.isolationReason(items.first);
      if (reason != null) {
        rationale.add(
          LoadRationale(
            kind: RationaleKind.separation,
            reason: reason.explanation,
            causedBy: items.first.id,
            causedByName: items.first.displayName,
          ),
        );
      }
    }

    // Drying.
    if (!drySpec.tumbleDryAllowed) {
      final driver = _itemDriving(
        items,
        (item) => !item.effectiveCare.dry.tumbleDryAllowed,
      );
      rationale.add(
        LoadRationale(
          kind: RationaleKind.drying,
          // Deliberately states the constraint without inventing a cause. The
          // item may be forbidden from the dryer by its label, or simply have
          // an unreadable drying symbol that fell back to the safe default —
          // and asserting "the heat would damage it" would be a fabricated
          // explanation in the second case.
          reason: driver == null
              ? 'Air dry this load — it must not be tumble dried.'
              : 'Air dry this load: ${driver.displayName} must not be tumble '
                  'dried.',
          causedBy: driver?.id,
          causedByName: driver?.displayName,
        ),
      );
    }

    // Capacity.
    final weight = _weightKg(items);
    if (weight > capacityKg * 0.95) {
      rationale.add(
        LoadRationale(
          kind: RationaleKind.capacity,
          reason: 'This load is close to your machine\'s capacity at '
              '${weight.toStringAsFixed(1)} kg. Do not add anything else — a '
              'packed drum does not wash clean.',
        ),
      );
    }

    // Handling warnings that apply to specific items.
    for (final warning in care.warnings) {
      final driver = _itemDriving(
        items,
        (item) => item.effectiveCare.warnings.contains(warning),
      );
      rationale.add(
        LoadRationale(
          kind: RationaleKind.handling,
          reason: driver == null || items.length == 1
              ? warning.label
              : '${warning.label} (${driver.displayName})',
          causedBy: driver?.id,
          causedByName: driver?.displayName,
        ),
      );
    }

    // A garment whose stain has been treated but not yet washed. Heat sets
    // whatever the treatment failed to lift and a dryer makes it permanent, so
    // this is the one thing worth saying about a load that has nothing to do
    // with its settings: look before you dry it.
    final treated = [
      for (final item in items)
        if (item.hasStainAwaitingAWash) item,
    ];
    if (treated.isNotEmpty) {
      final driver = treated.length == 1 ? treated.single : null;
      rationale.add(
        LoadRationale(
          kind: RationaleKind.handling,
          reason: driver == null
              ? 'Check ${treated.length} treated marks before this load goes '
                  'near heat — drying sets whatever did not come out.'
              : 'Check the treated mark on ${driver.displayName} before this '
                  'load goes near heat — drying sets whatever did not come '
                  'out.',
          causedBy: driver?.id,
          causedByName: driver?.displayName,
        ),
      );
    }

    return rationale;
  }

  /// The single item responsible for a constraint, or null when several share
  /// responsibility and naming one would be misleading.
  WardrobeItem? _itemDriving(
    List<WardrobeItem> items,
    bool Function(WardrobeItem item) test,
  ) {
    WardrobeItem? found;
    for (final item in items) {
      if (!test(item)) continue;
      if (found != null) return null;
      found = item;
    }
    return found;
  }
}
