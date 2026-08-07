/// The hard rules about what must never share a load.
///
/// These are separate from the *settings* a load runs at. Settings can always
/// be reconciled by taking the most restrictive option; separations cannot. No
/// choice of temperature makes it acceptable to wash a white shirt with a new
/// red one, so these are checked as absolute constraints before any merging.
library;

import '../../care/model/care_symbols.dart';
import '../../wardrobe/model/fabric.dart';
import '../../wardrobe/model/item_color.dart';
import '../../wardrobe/model/wardrobe_item.dart';

/// Why two items must not be washed together.
enum SeparationReason {
  /// Dark or bright dye against whites.
  colorTransfer(
    'Whites will pick up dye from darker items and grey permanently.',
  ),

  /// New saturated dye that runs.
  dyeBleed(
    'This item is new and its dye is still running, so it needs to be washed '
    'on its own.',
  ),

  /// Towelling shedding onto fabrics that show lint.
  lintTransfer(
    'Towelling sheds fibres that cling to smooth and dark fabrics.',
  ),

  /// Fragile items against heavy ones.
  abrasion(
    'Heavy items like jeans batter delicate fabrics in the drum.',
  ),

  /// One must be hand washed, the other machine washed.
  washMethod('These need different washing methods.'),

  /// A care label explicitly demands isolation.
  labelRequiresSeparate('The care label says to wash this separately.');

  const SeparationReason(this.explanation);

  /// A complete sentence explaining the separation to the user.
  final String explanation;
}

/// Decides which items can share a load.
abstract final class SeparationRules {
  /// Whether [a] and [b] can be washed together, and why not if they cannot.
  ///
  /// Returns null when they are compatible. Symmetric by construction: every
  /// check is expressed so that swapping the arguments gives the same answer,
  /// which a test asserts exhaustively across a sample wardrobe.
  static SeparationReason? conflictBetween(WardrobeItem a, WardrobeItem b) {
    // An explicit instruction from the manufacturer wins over any inference.
    if (a.effectiveCare.requiresIsolation ||
        b.effectiveCare.requiresIsolation) {
      return SeparationReason.labelRequiresSeparate;
    }

    // A hand-wash item in a machine load would be washed too aggressively.
    if (a.effectiveCare.wash.method != b.effectiveCare.wash.method) {
      return SeparationReason.washMethod;
    }

    // Bleeding dye ruins everything it touches, so it is checked before the
    // gentler colour rules.
    if (a.isLikelyToBleed || b.isLikelyToBleed) {
      return SeparationReason.dyeBleed;
    }

    if (_colorsConflict(a.colorClass, b.colorClass)) {
      return SeparationReason.colorTransfer;
    }

    if ((a.producesLint && b.attractsLint) ||
        (b.producesLint && a.attractsLint)) {
      return SeparationReason.lintTransfer;
    }

    if (_abrasionConflict(a.fabricClass, b.fabricClass)) {
      return SeparationReason.abrasion;
    }

    return null;
  }

  /// Whether an item can join a group that is already established.
  ///
  /// Checks against every member rather than against the group's aggregate,
  /// because separation is pairwise: an item may be compatible with a load's
  /// merged settings while still being incompatible with one item in it.
  static SeparationReason? conflictWithGroup(
    WardrobeItem candidate,
    Iterable<WardrobeItem> group,
  ) {
    for (final member in group) {
      final conflict = conflictBetween(candidate, member);
      if (conflict != null) return conflict;
    }
    return null;
  }

  /// Whether two groups can be merged into one load.
  static SeparationReason? conflictBetweenGroups(
    Iterable<WardrobeItem> a,
    Iterable<WardrobeItem> b,
  ) {
    for (final candidate in a) {
      final conflict = conflictWithGroup(candidate, b);
      if (conflict != null) return conflict;
    }
    return null;
  }

  /// Whites must not meet anything that can shed dye onto them.
  ///
  /// Lights and brights are allowed together: pastels are not dark enough to
  /// mark a bright, and the [SeparationReason.dyeBleed] check above has
  /// already pulled out anything actively running.
  static bool _colorsConflict(ColorClass a, ColorClass b) {
    if (a == b) return false;
    const risky = {ColorClass.darks, ColorClass.brights};
    if (a == ColorClass.whites && risky.contains(b)) return true;
    if (b == ColorClass.whites && risky.contains(a)) return true;
    return false;
  }

  /// Delicates must not share a drum with heavy items.
  static bool _abrasionConflict(FabricClass a, FabricClass b) =>
      (a == FabricClass.delicate && b == FabricClass.heavy) ||
      (b == FabricClass.delicate && a == FabricClass.heavy);

  /// Whether an item needs a load entirely to itself.
  static bool requiresOwnLoad(WardrobeItem item) =>
      item.effectiveCare.requiresIsolation || item.isLikelyToBleed;

  /// The reason an item needs isolation, for reporting.
  static SeparationReason? isolationReason(WardrobeItem item) {
    if (item.effectiveCare.requiresIsolation) {
      return SeparationReason.labelRequiresSeparate;
    }
    if (item.isLikelyToBleed) return SeparationReason.dyeBleed;
    return null;
  }
}

/// Groups items by the constraints that cannot be reconciled by settings.
///
/// Two items with the same key are guaranteed to be washable together as far as
/// *settings* go; whether they may actually share a drum is then decided by
/// [SeparationRules].
final class WashGroupKey {
  const WashGroupKey({
    required this.method,
    required this.colorClass,
    required this.fabricClass,
    required this.temperatureBand,
  });

  factory WashGroupKey.of(WardrobeItem item) => WashGroupKey(
        method: item.effectiveCare.wash.method,
        colorClass: item.colorClass,
        fabricClass: item.fabricClass,
        temperatureBand:
            TemperatureBand.forCelsius(item.effectiveCare.wash.maxTempC),
      );

  final WashMethod method;
  final ColorClass colorClass;
  final FabricClass fabricClass;
  final TemperatureBand temperatureBand;

  /// A short human label, used to name loads.
  String get label {
    final colour = switch (colorClass) {
      ColorClass.whites => 'Whites',
      ColorClass.lights => 'Lights',
      ColorClass.brights => 'Brights',
      ColorClass.darks => 'Darks',
    };
    final qualifier = switch (fabricClass) {
      FabricClass.delicate => 'delicates',
      FabricClass.heavy => 'heavy',
      FabricClass.normal => null,
    };
    return qualifier == null ? colour : '$colour ($qualifier)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WashGroupKey &&
          other.method == method &&
          other.colorClass == colorClass &&
          other.fabricClass == fabricClass &&
          other.temperatureBand == temperatureBand;

  @override
  int get hashCode =>
      Object.hash(method, colorClass, fabricClass, temperatureBand);

  @override
  String toString() => 'WashGroupKey(${method.name}, ${colorClass.name}, '
      '${fabricClass.name}, ${temperatureBand.name})';
}

/// Coarse temperature buckets.
///
/// Grouping by band rather than exact degrees stops a 30°C and a 40°C shirt
/// from being pointlessly split into two loads — they merge, and the load runs
/// at the lower of the two.
enum TemperatureBand {
  cold('Cold', ceilingC: 30),
  warm('Warm', ceilingC: 40),
  hot('Hot', ceilingC: 60),
  veryHot('Very hot', ceilingC: 95);

  const TemperatureBand(this.label, {required this.ceilingC});

  final String label;
  final int ceilingC;

  /// The band a maximum temperature falls into. A null limit — no stated
  /// maximum — is treated as the hottest band, since nothing constrains it.
  static TemperatureBand forCelsius(int? maxTempC) {
    if (maxTempC == null) return TemperatureBand.veryHot;
    for (final band in TemperatureBand.values) {
      if (maxTempC <= band.ceilingC) return band;
    }
    return TemperatureBand.veryHot;
  }
}
