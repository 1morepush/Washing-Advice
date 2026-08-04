/// A user's tumble dryer.
///
/// The same idea as [WasherProfile]: translate "low heat" into the programme
/// and heat setting this particular machine actually offers.
library;

import '../../care/model/care_symbols.dart';
import '../../shared/ids.dart';
import '../../wardrobe/model/fabric.dart';

/// The role a drying programme plays.
enum DryProgramKind {
  normal('Normal'),
  permanentPress('Permanent press'),
  delicates('Delicates'),
  wool('Wool'),
  airFluff('Air fluff — no heat'),
  timedDry('Timed dry'),
  bedding('Bedding / bulky'),
  quick('Quick dry'),
  steamRefresh('Steam refresh');

  const DryProgramKind(this.label);

  final String label;

  /// Whether this programme actually dries, as opposed to refreshing.
  bool get dries => this != steamRefresh;
}

/// Extra dryer options.
enum DryerOption {
  wrinkleGuard('Wrinkle guard'),
  steam('Steam'),
  ecoDry('Eco dry'),
  damdDryStop('Damp dry signal'),
  sanitize('Sanitise'),
  reverseTumble('Reverse tumble');

  const DryerOption(this.label);

  final String label;
}

/// How dryness is judged.
enum DrynessControl {
  /// Moisture sensors stop the cycle when the load is dry. Gentler and more
  /// efficient, because it never over-dries.
  sensor('Sensor dry'),

  /// Runs for a set time regardless of the load.
  timed('Timed dry');

  const DrynessControl(this.label);

  final String label;
}

/// One programme on a dryer.
final class DryProgram {
  const DryProgram({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.availableHeats,
    required this.defaultHeat,
    required this.suitableFor,
    this.control = DrynessControl.sensor,
    this.maxLoadFraction = 1.0,
    this.typicalDuration = const Duration(minutes: 60),
  });

  final String id;
  final String displayName;
  final DryProgramKind kind;
  final List<TumbleDryHeat> availableHeats;
  final TumbleDryHeat defaultHeat;
  final Set<FabricClass> suitableFor;
  final DrynessControl control;
  final double maxLoadFraction;
  final Duration typicalDuration;

  /// The hottest available setting not exceeding [maxHeat].
  ///
  /// Returns null when every setting on this programme is hotter than allowed.
  TumbleDryHeat? bestHeatFor(TumbleDryHeat maxHeat) {
    final permitted =
        availableHeats.where((h) => h.index <= maxHeat.index).toList();
    if (permitted.isEmpty) return null;
    return permitted.reduce((a, b) => a.index > b.index ? a : b);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        'kind': kind.name,
        'availableHeats': availableHeats.map((h) => h.name).toList(),
        'defaultHeat': defaultHeat.name,
        'suitableFor': suitableFor.map((f) => f.name).toList(),
        'control': control.name,
        'maxLoadFraction': maxLoadFraction,
        'typicalDurationMinutes': typicalDuration.inMinutes,
      };

  static DryProgram fromJson(Map<String, Object?> json) => DryProgram(
        id: json['id']! as String,
        displayName: json['displayName']! as String,
        kind: DryProgramKind.values.byName(json['kind']! as String),
        availableHeats: [
          for (final h in json['availableHeats']! as List<Object?>)
            TumbleDryHeat.values.byName(h! as String),
        ],
        defaultHeat:
            TumbleDryHeat.values.byName(json['defaultHeat']! as String),
        suitableFor: {
          for (final f in json['suitableFor']! as List<Object?>)
            FabricClass.values.byName(f! as String),
        },
        control: DrynessControl.values.byName(
          json['control'] as String? ?? DrynessControl.sensor.name,
        ),
        maxLoadFraction: (json['maxLoadFraction'] as num?)?.toDouble() ?? 1.0,
        typicalDuration: Duration(
          minutes: (json['typicalDurationMinutes'] as num?)?.toInt() ?? 60,
        ),
      );

  @override
  String toString() => 'DryProgram($displayName)';
}

/// A configured tumble dryer.
final class DryerProfile {
  const DryerProfile({
    required this.id,
    required this.brand,
    required this.model,
    required this.capacityKg,
    required this.programs,
    this.options = const {},
    this.isVerifiedModel = false,
  });

  final DryerId id;
  final String brand;
  final String model;
  final double capacityKg;
  final List<DryProgram> programs;
  final Set<DryerOption> options;

  /// See [WasherProfile.isVerifiedModel] — seeded profiles are archetypes.
  final bool isVerifiedModel;

  String get displayName => '$brand $model';

  DryProgram? programOfKind(DryProgramKind kind) {
    for (final program in programs) {
      if (program.kind == kind) return program;
    }
    return null;
  }

  bool supports(DryerOption option) => options.contains(option);

  /// Whether the dryer can tumble without heat, which many delicate items
  /// require.
  bool get hasNoHeatOption =>
      programs.any((p) => p.availableHeats.contains(TumbleDryHeat.noHeat));

  Map<String, Object?> toJson() => {
        'id': id.value,
        'brand': brand,
        'model': model,
        'capacityKg': capacityKg,
        'programs': [for (final p in programs) p.toJson()],
        'options': options.map((o) => o.name).toList(),
        'isVerifiedModel': isVerifiedModel,
      };

  static DryerProfile fromJson(Map<String, Object?> json) => DryerProfile(
        id: DryerId(json['id']! as String),
        brand: json['brand']! as String,
        model: json['model']! as String,
        capacityKg: (json['capacityKg']! as num).toDouble(),
        programs: [
          for (final p in json['programs']! as List<Object?>)
            DryProgram.fromJson(p! as Map<String, Object?>),
        ],
        options: {
          for (final o in (json['options'] as List<Object?>? ?? const []))
            DryerOption.values.byName(o! as String),
        },
        isVerifiedModel: json['isVerifiedModel'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DryerProfile && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'DryerProfile($displayName, ${capacityKg}kg)';
}
