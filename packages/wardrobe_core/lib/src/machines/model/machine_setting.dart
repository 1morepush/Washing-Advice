/// Concrete settings to dial into a specific machine.
library;

import '../../care/model/care_symbols.dart';

/// How seriously to take a note attached to a recommendation.
enum NoteSeverity {
  /// Helpful context.
  info,

  /// The machine cannot do exactly what was asked; this is the closest safe
  /// alternative.
  caution,

  /// Following this recommendation still carries risk, or the item should not
  /// go in this machine at all.
  warning,
}

/// Something the user should know about a recommendation.
final class SettingNote {
  const SettingNote(this.text, {this.severity = NoteSeverity.info});

  const SettingNote.caution(this.text) : severity = NoteSeverity.caution;

  const SettingNote.warning(this.text) : severity = NoteSeverity.warning;

  final String text;
  final NoteSeverity severity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingNote && other.text == text && other.severity == severity;

  @override
  int get hashCode => Object.hash(text, severity);

  @override
  String toString() => text;
}

/// What to select on the washing machine.
final class WasherSetting {
  const WasherSetting({
    required this.programName,
    required this.temperatureC,
    required this.spinRpm,
    this.options = const {},
    this.notes = const [],
    this.isCompromise = false,
    this.estimatedDuration,
  });

  /// The programme name as it appears on the machine.
  final String programName;

  /// Temperature to select. `0` means the cold or tap-cold setting.
  final int temperatureC;

  /// Spin speed to select. `0` means spin off.
  final int spinRpm;

  /// Options to turn on or off, keyed by option.
  final Map<WasherOptionSetting, bool> options;

  final List<SettingNote> notes;

  /// Whether the machine could not do exactly what was required.
  ///
  /// When true the recommendation is the closest safe alternative, and [notes]
  /// explains the gap. The UI must surface this rather than presenting a
  /// compromise as a perfect match.
  final bool isCompromise;

  final Duration? estimatedDuration;

  bool get hasWarnings => notes.any((n) => n.severity == NoteSeverity.warning);

  /// Human-readable temperature, e.g. `'Cold'` or `'30°C'`.
  String get temperatureLabel => temperatureC <= 0 ? 'Cold' : '$temperatureC°C';

  String get spinLabel => spinRpm <= 0 ? 'No spin' : '$spinRpm rpm';

  @override
  String toString() =>
      'WasherSetting($programName, $temperatureLabel, $spinLabel)';
}

/// An option that must be explicitly on or off. Mirrors `WasherOption`, kept
/// separate so settings can be compared without importing the profile model.
typedef WasherOptionSetting = String;

/// What to select on the dryer.
final class DryerSetting {
  const DryerSetting({
    required this.programName,
    required this.heat,
    required this.usesSensor,
    this.timedMinutes,
    this.notes = const [],
    this.isCompromise = false,
    this.estimatedDuration,
  });

  /// Air-drying instead, because the item must not be tumbled.
  const DryerSetting.airDryInstead(this.notes)
      : programName = 'Do not tumble dry',
        heat = TumbleDryHeat.noHeat,
        usesSensor = false,
        timedMinutes = null,
        isCompromise = false,
        estimatedDuration = null;

  final String programName;
  final TumbleDryHeat heat;

  /// Whether the programme stops on moisture sensing rather than a timer.
  final bool usesSensor;

  /// Minutes to set, when the programme is timed.
  final int? timedMinutes;

  final List<SettingNote> notes;
  final bool isCompromise;
  final Duration? estimatedDuration;

  /// True when this recommends not using the dryer at all.
  bool get isAirDry => programName == 'Do not tumble dry';

  bool get hasWarnings => notes.any((n) => n.severity == NoteSeverity.warning);

  @override
  String toString() => 'DryerSetting($programName, ${heat.label})';
}
