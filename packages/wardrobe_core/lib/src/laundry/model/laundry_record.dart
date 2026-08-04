/// A record of one item actually being washed.
///
/// Recording the *settings used*, not just that a wash happened, is what makes
/// later analysis possible: whether a garment shrank after a hot wash, whether
/// a colour faded faster in one machine than another, whether the app's own
/// recommendations were followed. Without this, "times washed" is a number with
/// no explanatory power.
library;

import '../../care/model/care_symbols.dart';
import '../../shared/ids.dart';

/// What was used to wash a load.
final class LaundryRecord {
  const LaundryRecord({
    required this.washedAt,
    this.washerId,
    this.washerName,
    this.programName,
    this.temperatureC,
    this.spinRpm,
    this.detergent,
    this.usedSoftener = false,
    this.dryerId,
    this.dryerName,
    this.dryProgramName,
    this.dryHeat,
    this.duration,
    this.followedRecommendation,
    this.loadId,
  });

  final DateTime washedAt;

  final WasherId? washerId;

  /// The machine's display name, kept alongside the id so history survives the
  /// user deleting or replacing a machine profile.
  final String? washerName;

  final String? programName;
  final int? temperatureC;
  final int? spinRpm;

  /// Free text — brand names change and users have strong opinions.
  final String? detergent;

  final bool usedSoftener;

  final DryerId? dryerId;
  final String? dryerName;
  final String? dryProgramName;
  final TumbleDryHeat? dryHeat;

  /// How long the whole wash took, when known.
  final Duration? duration;

  /// Whether the user followed the app's recommendation.
  ///
  /// The honest feedback signal: consistent divergence means the advice is
  /// wrong, or is being explained badly.
  final bool? followedRecommendation;

  /// The generated load this wash came from, when it came from a plan.
  final LoadId? loadId;

  /// Whether this was a hot wash, for shrinkage and fading analysis.
  bool get wasHot => (temperatureC ?? 0) >= 50;

  Map<String, Object?> toJson() => {
        'washedAt': washedAt.toIso8601String(),
        if (washerId != null) 'washerId': washerId!.value,
        if (washerName != null) 'washerName': washerName,
        if (programName != null) 'programName': programName,
        if (temperatureC != null) 'temperatureC': temperatureC,
        if (spinRpm != null) 'spinRpm': spinRpm,
        if (detergent != null) 'detergent': detergent,
        'usedSoftener': usedSoftener,
        if (dryerId != null) 'dryerId': dryerId!.value,
        if (dryerName != null) 'dryerName': dryerName,
        if (dryProgramName != null) 'dryProgramName': dryProgramName,
        if (dryHeat != null) 'dryHeat': dryHeat!.name,
        if (duration != null) 'durationMinutes': duration!.inMinutes,
        if (followedRecommendation != null)
          'followedRecommendation': followedRecommendation,
        if (loadId != null) 'loadId': loadId!.value,
      };

  static LaundryRecord fromJson(Map<String, Object?> json) => LaundryRecord(
        washedAt: DateTime.parse(json['washedAt']! as String),
        washerId: json['washerId'] == null
            ? null
            : WasherId(json['washerId']! as String),
        washerName: json['washerName'] as String?,
        programName: json['programName'] as String?,
        temperatureC: (json['temperatureC'] as num?)?.toInt(),
        spinRpm: (json['spinRpm'] as num?)?.toInt(),
        detergent: json['detergent'] as String?,
        usedSoftener: json['usedSoftener'] as bool? ?? false,
        dryerId: json['dryerId'] == null
            ? null
            : DryerId(json['dryerId']! as String),
        dryerName: json['dryerName'] as String?,
        dryProgramName: json['dryProgramName'] as String?,
        dryHeat: json['dryHeat'] == null
            ? null
            : TumbleDryHeat.values.byName(json['dryHeat']! as String),
        duration: json['durationMinutes'] == null
            ? null
            : Duration(minutes: (json['durationMinutes']! as num).toInt()),
        followedRecommendation: json['followedRecommendation'] as bool?,
        loadId:
            json['loadId'] == null ? null : LoadId(json['loadId']! as String),
      );

  @override
  String toString() => 'LaundryRecord($washedAt, $programName)';
}
