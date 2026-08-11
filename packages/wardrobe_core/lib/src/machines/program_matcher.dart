/// Chooses the best programme on a real machine for an abstract requirement.
///
/// This is where "wash cold, very gentle" becomes "run *Delicates* at 30°C,
/// 800 rpm, extra rinse on". Every programme is scored against the requirement
/// and the best is chosen; when nothing genuinely fits, the matcher says so
/// rather than quietly recommending something that will cause damage.
library;

import '../care/model/care_symbols.dart';
import '../care/model/wash_spec.dart';
import '../wardrobe/model/fabric.dart';
import 'model/dryer_profile.dart';
import 'model/machine_setting.dart';
import 'model/washer_profile.dart';

/// A programme with its fitness score, for debugging and tests.
final class ProgramCandidate {
  const ProgramCandidate({
    required this.program,
    required this.score,
    required this.temperatureC,
    required this.spinRpm,
    this.disqualified = false,
    this.reasons = const [],
  });

  final WashProgram program;
  final double score;
  final int temperatureC;
  final int spinRpm;

  /// True when the programme cannot safely run this load at all.
  final bool disqualified;

  /// Why points were added or removed, for explaining and testing.
  final List<String> reasons;

  @override
  String toString() =>
      'ProgramCandidate(${program.displayName}, ${score.toStringAsFixed(1)}'
      '${disqualified ? ", disqualified" : ""})';
}

/// Translates specs into concrete machine settings.
final class ProgramMatcher {
  const ProgramMatcher();

  /// Score below which a match is reported as a compromise.
  static const double _compromiseThreshold = 60;

  /// Picks a wash programme and its settings.
  WasherSetting matchWash(WashSpec spec, WasherProfile washer) {
    if (spec.method == WashMethod.doNotWash) {
      return const WasherSetting(
        programName: 'Do not wash',
        temperatureC: 0,
        spinRpm: 0,
        notes: [
          SettingNote.warning(
            'This item must not be washed. Have it professionally cleaned.',
          ),
        ],
      );
    }

    final candidates = rankPrograms(spec, washer);
    final viable = candidates.where((c) => !c.disqualified).toList();

    if (viable.isEmpty) {
      return _noViableProgram(spec, washer, candidates);
    }

    final best = viable.first;
    final notes = <SettingNote>[];

    // Hand-wash items on a machine with no hand-wash cycle: the single most
    // common real-world mismatch, and worth an explicit explanation.
    if (spec.method == WashMethod.hand &&
        best.program.kind != WashProgramKind.handWash &&
        best.program.kind != WashProgramKind.delicates) {
      notes.add(
        const SettingNote.warning(
          'This item should be hand washed and your machine has no hand-wash '
          'cycle. Wash it by hand, or accept some risk on the gentlest '
          'program below.',
        ),
      );
    } else if (spec.method == WashMethod.hand &&
        best.program.kind == WashProgramKind.delicates) {
      notes.add(
        const SettingNote.caution(
          'Your machine has no dedicated hand-wash cycle. Delicates at the '
          'lowest spin is the closest equivalent.',
        ),
      );
    }

    if (spec.maxTempC != null && best.temperatureC > spec.maxTempC!) {
      notes.add(
        SettingNote.warning(
          'The coldest setting on this program is ${best.temperatureC}°C, '
          'above the ${spec.maxTempC}°C this load needs.',
        ),
      );
    }

    if (!best.program.suitableFor.contains(spec.fabricClass)) {
      notes.add(
        SettingNote.caution(
          '${best.program.displayName} is not designed for '
          '${spec.fabricClass.name} fabrics, but it is the closest fit '
          'available.',
        ),
      );
    }

    if (best.program.maxLoadFraction < 1.0) {
      notes.add(
        SettingNote(
          'Fill the drum to no more than '
          '${(best.program.maxLoadFraction * 100).round()}% on this '
          'program — gentle cycles cannot move a full drum.',
        ),
      );
    }

    final options = <WasherOptionSetting, bool>{};
    if (washer.supports(WasherOption.extraRinse)) {
      options[WasherOption.extraRinse.label] = spec.needsExtraRinse;
    }
    if (washer.supports(WasherOption.softenerDispenser) && spec.avoidSoftener) {
      options[WasherOption.softenerDispenser.label] = false;
      notes.add(
        const SettingNote(
          'Leave the softener dispenser empty for this load.',
        ),
      );
    }
    if (washer.supports(WasherOption.steam) &&
        spec.fabricClass == FabricClass.delicate) {
      options[WasherOption.steam.label] = false;
    }

    return WasherSetting(
      programName: best.program.displayName,
      temperatureC: best.temperatureC,
      spinRpm: best.spinRpm,
      options: options,
      notes: notes,
      isCompromise: best.score < _compromiseThreshold ||
          notes.any(
            (n) => n.severity != NoteSeverity.info,
          ),
      estimatedDuration: best.program.typicalDuration,
    );
  }

  /// Scores every programme, best first. Exposed so tests and diagnostics can
  /// inspect *why* a programme was chosen.
  List<ProgramCandidate> rankPrograms(WashSpec spec, WasherProfile washer) {
    final candidates = <ProgramCandidate>[
      for (final program in washer.washCycles) _score(spec, program),
    ]..sort((x, y) => y.score.compareTo(x.score));
    return candidates;
  }

  ProgramCandidate _score(WashSpec spec, WashProgram program) {
    var score = 100.0;
    final reasons = <String>[];
    var disqualified = false;

    // Temperature. A programme that cannot go cold enough is disqualified:
    // washing a 30°C garment at 60°C is exactly the mistake this app exists to
    // prevent.
    final temperature = program.bestTemperatureFor(spec.maxTempC);
    if (temperature == null) {
      disqualified = true;
      reasons.add('cannot reach ${spec.maxTempC}°C or below');
    }

    // Agitation. Too aggressive is dangerous; gentler than needed merely
    // cleans a little less well, so the penalties are asymmetric.
    final agitationDelta = program.agitation.index - spec.agitation.index;
    if (agitationDelta < 0) {
      score += agitationDelta * 45; // negative delta, so this subtracts
      reasons.add('agitation is harsher than required');
      if (spec.agitation == Agitation.veryMild) {
        disqualified = true;
        reasons.add('delicate load cannot take this much agitation');
      }
    } else if (agitationDelta > 0) {
      score -= agitationDelta * 6;
      reasons.add('gentler than necessary');
    }

    // Fabric suitability.
    if (!program.suitableFor.contains(spec.fabricClass)) {
      score -= 35;
      reasons.add('not intended for ${spec.fabricClass.name} fabrics');
    }

    // Affinity between the requirement and what the programme is named for.
    score += _kindAffinity(spec, program.kind);

    // Prefer the shorter of two equally good programmes.
    score -= program.typicalDuration.inMinutes / 60.0;

    return ProgramCandidate(
      program: program,
      score: score,
      temperatureC: temperature ?? program.availableTempsC.first,
      spinRpm: program.spinFor(spec.maxSpinRpm),
      disqualified: disqualified,
      reasons: reasons,
    );
  }

  /// Bonus for programmes designed for this kind of load.
  double _kindAffinity(WashSpec spec, WashProgramKind kind) {
    if (spec.method == WashMethod.hand) {
      return switch (kind) {
        WashProgramKind.handWash => 45,
        WashProgramKind.wool => 30,
        WashProgramKind.delicates => 25,
        _ => 0,
      };
    }
    return switch ((spec.fabricClass, kind)) {
      (FabricClass.delicate, WashProgramKind.delicates) => 35,
      (FabricClass.delicate, WashProgramKind.wool) => 20,
      (FabricClass.delicate, WashProgramKind.handWash) => 15,
      (FabricClass.heavy, WashProgramKind.heavyDuty) => 30,
      (FabricClass.heavy, WashProgramKind.cotton) => 25,
      (FabricClass.normal, WashProgramKind.cotton) => 20,
      (FabricClass.normal, WashProgramKind.syntheticsMixed) => 22,
      (FabricClass.normal, WashProgramKind.eco) => 10,
      _ => 0,
    };
  }

  WasherSetting _noViableProgram(
    WashSpec spec,
    WasherProfile washer,
    List<ProgramCandidate> candidates,
  ) {
    // Fall back to the least-bad option so the user is not left stranded, but
    // be explicit that it is not safe.
    final fallback = candidates.isEmpty ? null : candidates.first;
    if (fallback == null) {
      return const WasherSetting(
        programName: 'No suitable program',
        temperatureC: 0,
        spinRpm: 0,
        isCompromise: true,
        notes: [
          SettingNote.warning(
            'This machine has no program that can wash this load safely. '
            'Wash it by hand.',
          ),
        ],
      );
    }

    return WasherSetting(
      programName: fallback.program.displayName,
      temperatureC: fallback.temperatureC,
      spinRpm: fallback.spinRpm,
      isCompromise: true,
      estimatedDuration: fallback.program.typicalDuration,
      notes: [
        SettingNote.warning(
          'No program on your ${washer.displayName} matches what this load '
          'needs (${fallback.reasons.join('; ')}). Washing by hand is safer.',
        ),
      ],
    );
  }

  /// Picks a drying programme and its settings.
  DryerSetting matchDry(DrySpec spec, DryerProfile dryer) {
    if (!spec.tumbleDryAllowed) {
      final method = spec.naturalDry;
      final instruction = switch (method) {
        NaturalDryMethod.flatDry => 'Dry flat to keep its shape.',
        NaturalDryMethod.dripDry => 'Hang to dry without spinning.',
        NaturalDryMethod.lineDry => 'Hang to dry.',
        null => 'Air dry.',
      };
      return DryerSetting.airDryInstead([
        SettingNote.warning('Do not tumble dry this load. $instruction'),
        if (spec.dryInShade)
          const SettingNote('Keep it out of direct sunlight while it dries.'),
      ]);
    }

    final ranked = <({DryProgram program, TumbleDryHeat heat, double score})>[];
    for (final program in dryer.programs.where((p) => p.kind.dries)) {
      final heat = program.bestHeatFor(spec.maxHeat);
      if (heat == null) continue;

      var score = 100.0;
      if (!program.suitableFor.contains(spec.fabricClass)) score -= 35;
      score += switch ((spec.fabricClass, program.kind)) {
        (FabricClass.delicate, DryProgramKind.delicates) => 35,
        (FabricClass.delicate, DryProgramKind.wool) => 30,
        (FabricClass.delicate, DryProgramKind.airFluff) => 25,
        (FabricClass.heavy, DryProgramKind.normal) => 25,
        (FabricClass.normal, DryProgramKind.normal) => 20,
        (FabricClass.normal, DryProgramKind.permanentPress) => 22,
        _ => 0.0,
      };
      // Sensor drying is gentler than a timer, because it stops when the load
      // is dry instead of continuing to bake it.
      if (program.control == DrynessControl.sensor) score += 12;
      // Using less heat than allowed is safer, so prefer the cooler option
      // when scores are otherwise close.
      score -= heat.index * 2;

      ranked.add((program: program, heat: heat, score: score));
    }

    if (ranked.isEmpty) {
      return DryerSetting.airDryInstead([
        SettingNote.warning(
          'Your ${dryer.displayName} has no setting cool enough for this load '
          '(it needs ${spec.maxHeat.label.toLowerCase()} or less). Air dry it '
          'instead.',
        ),
      ]);
    }

    ranked.sort((x, y) => y.score.compareTo(x.score));
    final best = ranked.first;
    final notes = <SettingNote>[];

    if (!best.program.suitableFor.contains(spec.fabricClass)) {
      notes.add(
        SettingNote.caution(
          '${best.program.displayName} is not intended for '
          '${spec.fabricClass.name} fabrics, but it is the closest fit.',
        ),
      );
    }
    if (best.program.control == DrynessControl.timed) {
      notes.add(
        const SettingNote(
          'This is a timed program — check the load before it finishes so it '
          'is not over-dried.',
        ),
      );
    }

    return DryerSetting(
      programName: best.program.displayName,
      heat: best.heat,
      usesSensor: best.program.control == DrynessControl.sensor,
      timedMinutes: best.program.control == DrynessControl.timed
          ? best.program.typicalDuration.inMinutes
          : null,
      notes: notes,
      isCompromise: notes.any((n) => n.severity != NoteSeverity.info),
      estimatedDuration: best.program.typicalDuration,
    );
  }
}
