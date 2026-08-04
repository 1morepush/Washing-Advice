/// Machine-independent statements of what a wash or dry must achieve.
///
/// Sits between care instructions and a specific machine. A [WashSpec] says
/// "cold, very gentle, delicate fabrics, spin no faster than 600" without
/// knowing whether the user owns an LG or a Bosch; the program matcher then
/// turns that into a named programme on their actual machine.
///
/// Keeping this layer separate is what stops machine quirks leaking into the
/// sorting engine, and lets both be tested independently.
library;

import '../../wardrobe/model/fabric.dart';
import 'care_instructions.dart';
import 'care_symbols.dart';

/// What a wash must satisfy.
final class WashSpec {
  const WashSpec({
    required this.method,
    required this.agitation,
    required this.fabricClass,
    this.maxTempC,
    this.maxSpinRpm,
    this.needsExtraRinse = false,
    this.avoidSoftener = false,
  });

  /// Derives the requirement from resolved care instructions.
  ///
  /// The spin limit is inferred rather than read: care labels almost never
  /// state one, but fabric class and wetness behaviour imply it. A hard spin is
  /// what stretches a wet viscose dress out of shape.
  factory WashSpec.from(
    CareInstructions care,
    FabricClass fabricClass, {
    bool weakWhenWet = false,
  }) =>
      WashSpec(
        method: care.wash.method,
        agitation: care.wash.agitation,
        fabricClass: fabricClass,
        maxTempC: care.wash.maxTempC,
        maxSpinRpm: _spinLimitFor(
          fabricClass,
          weakWhenWet: weakWhenWet || care.dry.doNotWring,
        ),
        needsExtraRinse: fabricClass == FabricClass.delicate,
        avoidSoftener: care.warnings.contains(CareWarning.doNotUseSoftener),
      );

  final WashMethod method;
  final Agitation agitation;
  final FabricClass fabricClass;
  final int? maxTempC;

  /// Fastest safe spin. Null means no particular limit.
  final int? maxSpinRpm;

  /// Whether a second rinse is worth recommending. Delicates hold detergent,
  /// and residue is what makes fine fabrics feel stiff.
  final bool needsExtraRinse;

  final bool avoidSoftener;

  static int? _spinLimitFor(FabricClass fabricClass,
      {required bool weakWhenWet}) {
    if (weakWhenWet) return 600;
    return switch (fabricClass) {
      FabricClass.delicate => 800,
      FabricClass.normal => null,
      FabricClass.heavy => null,
    };
  }

  /// Combines two requirements so the result satisfies both.
  WashSpec restrictiveMerge(WashSpec other) => WashSpec(
        method: method.stricter(other.method),
        agitation: agitation.gentler(other.agitation),
        fabricClass: fabricClass.leastRobust(other.fabricClass),
        maxTempC: switch ((maxTempC, other.maxTempC)) {
          (null, final b) => b,
          (final a, null) => a,
          (final a?, final b?) => a < b ? a : b,
        },
        maxSpinRpm: switch ((maxSpinRpm, other.maxSpinRpm)) {
          (null, final b) => b,
          (final a, null) => a,
          (final a?, final b?) => a < b ? a : b,
        },
        needsExtraRinse: needsExtraRinse || other.needsExtraRinse,
        avoidSoftener: avoidSoftener || other.avoidSoftener,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WashSpec &&
          other.method == method &&
          other.agitation == agitation &&
          other.fabricClass == fabricClass &&
          other.maxTempC == maxTempC &&
          other.maxSpinRpm == maxSpinRpm &&
          other.needsExtraRinse == needsExtraRinse &&
          other.avoidSoftener == avoidSoftener;

  @override
  int get hashCode => Object.hash(
        method,
        agitation,
        fabricClass,
        maxTempC,
        maxSpinRpm,
        needsExtraRinse,
        avoidSoftener,
      );

  @override
  String toString() => 'WashSpec(${method.name}, ${maxTempC ?? "any"}C, '
      '${agitation.name}, ${fabricClass.name})';
}

/// What a dry must satisfy.
final class DrySpec {
  const DrySpec({
    required this.tumbleDryAllowed,
    required this.maxHeat,
    required this.fabricClass,
    this.naturalDry,
    this.dryInShade = false,
  });

  factory DrySpec.from(CareInstructions care, FabricClass fabricClass) =>
      DrySpec(
        tumbleDryAllowed: care.dry.tumbleDryAllowed,
        maxHeat: care.dry.tumbleDryHeat,
        fabricClass: fabricClass,
        naturalDry: care.dry.naturalDry,
        dryInShade: care.dry.dryInShade,
      );

  final bool tumbleDryAllowed;
  final TumbleDryHeat maxHeat;
  final FabricClass fabricClass;
  final NaturalDryMethod? naturalDry;
  final bool dryInShade;

  DrySpec restrictiveMerge(DrySpec other) => DrySpec(
        tumbleDryAllowed: tumbleDryAllowed && other.tumbleDryAllowed,
        maxHeat: maxHeat.cooler(other.maxHeat),
        fabricClass: fabricClass.leastRobust(other.fabricClass),
        naturalDry: switch ((naturalDry, other.naturalDry)) {
          (null, final b) => b,
          (final a, null) => a,
          (final a?, final b?) => a.index >= b.index ? a : b,
        },
        dryInShade: dryInShade || other.dryInShade,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrySpec &&
          other.tumbleDryAllowed == tumbleDryAllowed &&
          other.maxHeat == maxHeat &&
          other.fabricClass == fabricClass &&
          other.naturalDry == naturalDry &&
          other.dryInShade == dryInShade;

  @override
  int get hashCode => Object.hash(
        tumbleDryAllowed,
        maxHeat,
        fabricClass,
        naturalDry,
        dryInShade,
      );

  @override
  String toString() =>
      'DrySpec(tumble=$tumbleDryAllowed, ${maxHeat.name}, ${fabricClass.name})';
}
