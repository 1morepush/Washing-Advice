/// What the server proposed for a stain, before anything has checked it.
///
/// Deliberately a separate type from `TreatmentPlan` in the core, and
/// deliberately named for what it is. This is a *proposal*: it was produced
/// from a summary of the care label rather than the label, by a model that was
/// explicitly told not to do the safety reasoning itself. Handing it straight
/// to a screen would show a wool jumper a bleach soak.
///
/// `StainSafety.vet` turns one of these into a `TreatmentPlan`, and only that
/// is fit to display. Keeping the two types apart is what makes skipping the
/// vetting step a compile error rather than a quiet mistake.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

import 'scan_dto.dart';

/// The model's answer, unvetted.
final class StainAdvice {
  const StainAdvice({required this.steps, this.identifiedAs});

  final List<TreatmentStep> steps;

  /// What the model believes the stain to be.
  ///
  /// Shown above the steps so a misread can be corrected *before* the user
  /// follows advice aimed at the wrong substance — "a greasy stain" over a
  /// treatment for red wine is the one thing that makes the mistake visible.
  final String? identifiedAs;

  static StainAdvice fromJson(Map<String, Object?> json) {
    final steps = json['steps'];
    if (steps is! List) {
      throw ScanContractError('the advice had no "steps"');
    }

    return StainAdvice(
      steps: [
        for (final step in steps) _stepFrom(step! as Map<String, Object?>),
      ],
      identifiedAs: json['identifiedAs'] as String?,
    );
  }
}

/// One step, with the fields the core vets it against.
///
/// A missing structured field is read as "the step does not do that" rather
/// than as an error: a model that omits `temperatureC` is saying this step
/// names no temperature, which is true of "blot it with a cloth". The prompt
/// is what makes sure the fields are stated when they apply; this side only
/// has to not invent them.
TreatmentStep _stepFrom(Map<String, Object?> json) {
  final instruction = json['instruction'];
  if (instruction is! String || instruction.isEmpty) {
    throw ScanContractError('a step had no instruction');
  }

  return TreatmentStep(
    instruction: instruction,
    because: json['because'] as String?,
    temperatureC: (json['temperatureC'] as num?)?.toInt(),
    bleach: _bleachFrom(json['bleach'] as String?),
    isMachineWash: json['isMachineWash'] as bool? ?? false,
    abrades: json['abrades'] as bool? ?? false,
  );
}

/// One thing the server said while the advice was still being written.
///
/// A sealed family rather than a partial [StainAdvice] that grows: the stream
/// carries an outcome as well as content — it can end without finishing — and
/// a type that only ever accumulated steps could not express "that is all of
/// them" or "the model stopped halfway". Both matter here, because a treatment
/// that ends early looks exactly like a short one.
sealed class StainStreamEvent {
  const StainStreamEvent();

  /// Reads one decoded SSE payload.
  ///
  /// An unknown `type` is ignored rather than fatal — a newer server may send
  /// events this build has never heard of, and dropping one costs nothing while
  /// throwing would lose a treatment the user is halfway through.
  static StainStreamEvent? fromJson(Map<String, Object?> json) =>
      switch (json['type']) {
        'identified' => StainIdentified(json['identifiedAs'] as String? ?? ''),
        'step' => StainStep(_stepFrom(json['step']! as Map<String, Object?>)),
        'done' => StainDone(
          diagnostics: json['diagnostics'] == null
              ? null
              : ScanDiagnostics.fromJson(
                  json['diagnostics']! as Map<String, Object?>,
                ),
        ),
        'error' => StainStreamError(
          json['message'] as String? ?? 'The server could not finish.',
        ),
        _ => null,
      };
}

/// What the model believes the stain is.
final class StainIdentified extends StainStreamEvent {
  const StainIdentified(this.identifiedAs);

  final String identifiedAs;
}

/// One finished step, still unvetted.
final class StainStep extends StainStreamEvent {
  const StainStep(this.step);

  final TreatmentStep step;
}

/// The treatment is complete. Its absence is what marks a truncated answer.
final class StainDone extends StainStreamEvent {
  const StainDone({this.diagnostics});

  final ScanDiagnostics? diagnostics;
}

/// The server gave up partway through.
final class StainStreamError extends StainStreamEvent {
  const StainStreamError(this.message);

  final String message;
}

/// Parses the bleach a step uses.
///
/// An unrecognised value throws rather than degrading to null. Everywhere else
/// in this app an unknown enum member is tolerated, because the cost is a
/// stale-looking field; here the cost is a bleach step that reads as using no
/// bleach at all and sails past the check that exists to catch it.
BleachUse? _bleachFrom(String? raw) {
  if (raw == null) return null;
  for (final use in BleachUse.values) {
    if (use.name == raw) return use;
  }
  throw ScanContractError('unknown bleach "$raw"');
}
