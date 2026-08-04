/// A user's washing machine, described in enough detail to give exact advice.
///
/// The product's core promise is not "wash cold" but "run *Delicates* at 30°C,
/// 800 rpm, on **your** machine". That requires knowing which programmes the
/// machine actually has, which temperatures and spin speeds each allows, and
/// what each is designed for.
library;

import '../../care/model/care_symbols.dart';
import '../../shared/ids.dart';
import '../../wardrobe/model/fabric.dart';

/// The role a programme plays, independent of what the manufacturer calls it.
///
/// Brands name the same cycle a dozen ways — "Delicates", "Hand Wash",
/// "Silk/Wool", "Gentle". Matching on [WashProgramKind] rather than on the
/// display name keeps the matcher working across brands and locales.
enum WashProgramKind {
  cotton('Cotton'),
  syntheticsMixed('Synthetics / mixed'),
  delicates('Delicates'),
  wool('Wool'),
  handWash('Hand wash'),
  quick('Quick wash'),
  heavyDuty('Heavy duty'),
  sportswear('Sportswear'),
  bedding('Bedding / bulky'),
  eco('Eco'),
  rinseSpin('Rinse and spin'),
  drumClean('Drum clean');

  const WashProgramKind(this.label);

  final String label;

  /// Whether this programme is for washing clothes at all, as opposed to
  /// maintenance cycles the sorter must never recommend.
  bool get isWashCycle => this != drumClean && this != rinseSpin;
}

/// Extra options a machine may offer, beyond programme, temperature and spin.
enum WasherOption {
  extraRinse('Extra rinse'),
  prewash('Prewash'),
  steam('Steam'),
  stainRemoval('Stain removal'),
  delayStart('Delay start'),
  ecoMode('Eco mode'),
  softenerDispenser('Fabric softener'),
  timeSaver('Time saver');

  const WasherOption(this.label);

  final String label;
}

/// One programme on a washing machine.
final class WashProgram {
  const WashProgram({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.availableTempsC,
    required this.defaultTempC,
    required this.agitation,
    required this.spinSpeedsRpm,
    required this.suitableFor,
    this.maxLoadFraction = 1.0,
    this.typicalDuration = const Duration(minutes: 90),
  });

  final String id;

  /// What the dial or display actually says, so the user can find it.
  final String displayName;

  final WashProgramKind kind;

  /// Selectable temperatures in Celsius. `0` represents a cold/tap-cold wash.
  final List<int> availableTempsC;

  final int defaultTempC;

  /// The mechanical action this programme applies.
  final Agitation agitation;

  /// Selectable spin speeds. `0` represents spin off / drain only.
  final List<int> spinSpeedsRpm;

  /// Fabric classes this programme is designed for.
  final Set<FabricClass> suitableFor;

  /// Fraction of the drum's rated capacity this programme allows.
  ///
  /// Delicate and wool cycles are typically restricted to a half load, because
  /// gentle agitation cannot move a full drum of wet fabric.
  final double maxLoadFraction;

  final Duration typicalDuration;

  int get maxSpinRpm =>
      spinSpeedsRpm.isEmpty ? 0 : spinSpeedsRpm.reduce((a, b) => a > b ? a : b);

  int get minSpinRpm =>
      spinSpeedsRpm.isEmpty ? 0 : spinSpeedsRpm.reduce((a, b) => a < b ? a : b);

  /// The coldest available temperature at or below [target].
  ///
  /// Returns null when even the lowest setting is hotter than the item can
  /// take, which is a genuine incompatibility the caller must report rather
  /// than quietly wash too hot.
  int? bestTemperatureFor(int? target) {
    if (availableTempsC.isEmpty) return null;
    if (target == null) return defaultTempC;
    final permitted = availableTempsC.where((t) => t <= target).toList();
    if (permitted.isEmpty) return null;
    return permitted.reduce((a, b) => a > b ? a : b);
  }

  /// The highest spin speed not exceeding [maxRpm], for the fastest safe spin.
  int spinFor(int? maxRpm) {
    if (spinSpeedsRpm.isEmpty) return 0;
    if (maxRpm == null) return maxSpinRpm;
    final permitted = spinSpeedsRpm.where((s) => s <= maxRpm).toList();
    if (permitted.isEmpty) return minSpinRpm;
    return permitted.reduce((a, b) => a > b ? a : b);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        'kind': kind.name,
        'availableTempsC': availableTempsC,
        'defaultTempC': defaultTempC,
        'agitation': agitation.name,
        'spinSpeedsRpm': spinSpeedsRpm,
        'suitableFor': suitableFor.map((f) => f.name).toList(),
        'maxLoadFraction': maxLoadFraction,
        'typicalDurationMinutes': typicalDuration.inMinutes,
      };

  static WashProgram fromJson(Map<String, Object?> json) => WashProgram(
        id: json['id']! as String,
        displayName: json['displayName']! as String,
        kind: WashProgramKind.values.byName(json['kind']! as String),
        availableTempsC: [
          for (final t in json['availableTempsC']! as List<Object?>)
            (t! as num).toInt(),
        ],
        defaultTempC: (json['defaultTempC']! as num).toInt(),
        agitation: Agitation.values.byName(json['agitation']! as String),
        spinSpeedsRpm: [
          for (final s in json['spinSpeedsRpm']! as List<Object?>)
            (s! as num).toInt(),
        ],
        suitableFor: {
          for (final f in json['suitableFor']! as List<Object?>)
            FabricClass.values.byName(f! as String),
        },
        maxLoadFraction: (json['maxLoadFraction'] as num?)?.toDouble() ?? 1.0,
        typicalDuration: Duration(
          minutes: (json['typicalDurationMinutes'] as num?)?.toInt() ?? 90,
        ),
      );

  @override
  String toString() => 'WashProgram($displayName)';
}

/// A configured washing machine.
final class WasherProfile {
  const WasherProfile({
    required this.id,
    required this.brand,
    required this.model,
    required this.capacityKg,
    required this.programs,
    this.options = const {},
    this.isVerifiedModel = false,
  });

  final WasherId id;
  final String brand;

  /// Model name, or a description such as `'Front loader'` for an archetype.
  final String model;

  /// Rated dry-laundry capacity in kilograms.
  final double capacityKg;

  final List<WashProgram> programs;
  final Set<WasherOption> options;

  /// Whether these settings were confirmed against a real manual.
  ///
  /// The seeded brand profiles are archetypes built from each manufacturer's
  /// common cycle line-up, not model-exact specifications. The UI must say so
  /// and invite correction — quietly presenting a guess as fact is how a user
  /// ends up trusting a cycle their machine does not have.
  final bool isVerifiedModel;

  String get displayName => '$brand $model';

  /// Programmes usable for washing clothes.
  Iterable<WashProgram> get washCycles =>
      programs.where((p) => p.kind.isWashCycle);

  WashProgram? programOfKind(WashProgramKind kind) {
    for (final program in programs) {
      if (program.kind == kind) return program;
    }
    return null;
  }

  bool supports(WasherOption option) => options.contains(option);

  /// Whether the machine can wash without heating, which many care labels
  /// effectively require.
  bool get hasColdWash =>
      washCycles.any((p) => p.availableTempsC.any((t) => t <= 20));

  Map<String, Object?> toJson() => {
        'id': id.value,
        'brand': brand,
        'model': model,
        'capacityKg': capacityKg,
        'programs': [for (final p in programs) p.toJson()],
        'options': options.map((o) => o.name).toList(),
        'isVerifiedModel': isVerifiedModel,
      };

  static WasherProfile fromJson(Map<String, Object?> json) => WasherProfile(
        id: WasherId(json['id']! as String),
        brand: json['brand']! as String,
        model: json['model']! as String,
        capacityKg: (json['capacityKg']! as num).toDouble(),
        programs: [
          for (final p in json['programs']! as List<Object?>)
            WashProgram.fromJson(p! as Map<String, Object?>),
        ],
        options: {
          for (final o in (json['options'] as List<Object?>? ?? const []))
            WasherOption.values.byName(o! as String),
        },
        isVerifiedModel: json['isVerifiedModel'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is WasherProfile && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'WasherProfile($displayName, ${capacityKg}kg)';
}
