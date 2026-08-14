/// Getting a stain out of a particular garment.
///
/// The only flow in this app where a model's answer is *acted on* rather than
/// reviewed as a suggestion — somebody follows these steps with the garment in
/// their hands — and the damage is irreversible. Chlorine dissolves wool, a hot
/// soak sets a protein stain, rubbing abrades silk, and a confident paragraph
/// looks exactly like a correct one.
///
/// So the model's answer never reaches the screen. `AiGateway` returns a
/// [StainAdvice], which is a *proposal*, and `StainSafety.vet` turns it into a
/// [TreatmentPlan] against this garment's real care. Those are different types
/// on purpose: skipping the vetting is a compile error rather than an
/// oversight.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';
import '../../data/api/stain_dto.dart';
import '../history/wear_recorder.dart';
import '../wardrobe/care_text.dart';

sealed class StainState {
  const StainState();
}

final class StainIdle extends StainState {
  const StainIdle();
}

final class StainThinking extends StainState {
  const StainThinking();
}

/// A vetted treatment, ready to follow.
///
/// Reached with [isComplete] false while the rest is still arriving. The steps
/// already here are final — each was vetted against this garment as it landed,
/// and nothing that follows can take one back — so they are safe to act on
/// before the last one has been written. That is the entire point: the first
/// step is the one to do first, and waiting for the whole treatment before
/// showing any of it spends the wait on advice the user has not reached.
final class StainAdvised extends StainState {
  const StainAdvised({
    required this.substance,
    required this.plan,
    this.identifiedAs,
    this.isComplete = true,
  });

  /// Whether the server said it had finished.
  ///
  /// False means either "still writing" or "stopped early", and the screen
  /// distinguishes them by whether a failure followed. A treatment that ended
  /// early looks exactly like a short one, and the step most often lost is the
  /// one about checking the mark before it goes near heat.
  final bool isComplete;

  /// What the user said was spilled, kept so the screen can show what the
  /// advice is actually about.
  final String substance;

  final TreatmentPlan plan;

  /// What the model made of it, when it said. Shown above the steps so a
  /// misread is visible before anybody acts on it.
  final String? identifiedAs;
}

final class StainFailed extends StainState {
  const StainFailed(this.message, {this.isRetryable = true});

  final String message;
  final bool isRetryable;
}

class StainController extends StateNotifier<StainState> {
  StainController(this._ref, this.itemId) : super(const StainIdle());

  final Ref _ref;
  final ItemId itemId;

  /// Asks for a treatment and vets it, step by step, as it arrives.
  ///
  /// Every step is vetted the moment it lands rather than at the end. Doing it
  /// once at the close would mean either showing unvetted steps — the one thing
  /// this flow exists to prevent — or holding them all back and streaming for
  /// nothing. `StainSafety.vet` is pure and takes the whole list, so re-running
  /// it over the steps so far gives exactly the answer the batch call would
  /// have given, including the cautions, which depend on what was kept.
  Future<void> advise({
    required String substance,
    String? note,
    ScanImage? photo,
  }) async {
    if (substance.trim().isEmpty) return;

    final item = await _ref.read(wardrobeRepositoryProvider).byId(itemId);
    if (item == null) {
      state = const StainFailed(
        'That item is no longer in your wardrobe.',
        isRetryable: false,
      );
      return;
    }

    state = const StainThinking();

    final trimmed = substance.trim();
    final proposed = <TreatmentStep>[];
    String? identifiedAs;
    var finished = false;

    void publish({bool complete = false}) {
      state = StainAdvised(
        substance: trimmed,
        // The whole point. Everything the label forbids is dropped here, with
        // the reason, before a single step is drawn.
        plan: const StainSafety().vet(proposed, item: item),
        identifiedAs: identifiedAs,
        isComplete: complete,
      );
    }

    try {
      final events = _ref
          .read(aiGatewayProvider)
          .streamStainAdvice(
            substance: trimmed,
            fabric: item.composition.value.label,
            // The care summary the app already shows on the item's own screen,
            // so the model is told exactly what the user was told. A second
            // way of phrasing the label here would be a second thing to keep
            // true.
            care: _careSummary(item),
            color: item.colors.value.dominant?.name,
            note: note,
            photo: photo,
          );

      await for (final event in events) {
        if (!mounted) return;

        switch (event) {
          case StainIdentified(identifiedAs: final name):
            identifiedAs = name;
            // Only worth a repaint once there is something to draw it above.
            if (proposed.isNotEmpty) publish();
          case StainStep(:final step):
            proposed.add(step);
            publish();
          case StainDone():
            finished = true;
            publish(complete: true);
          case StainStreamError(:final message):
            state = StainFailed(message);
            return;
        }
      }
    } on ScanFailure catch (failure) {
      state = StainFailed(failure.message, isRetryable: failure.isRetryable);
      return;
    } on ScanContractError catch (error) {
      state = StainFailed(
        'The server sent something this version cannot read. $error',
        isRetryable: false,
      );
      return;
    }

    if (!mounted) return;

    // The stream ended without saying it was done — a dropped connection
    // partway through. What arrived was vetted and is safe to follow, but it is
    // not the whole treatment, and presenting a truncated one as complete is
    // how somebody misses the step about checking the mark before it dries.
    if (!finished) {
      state = proposed.isEmpty
          ? const StainFailed(
              'The connection dropped before any advice arrived.',
            )
          : StainAdvised(
              substance: trimmed,
              plan: const StainSafety().vet(proposed, item: item),
              identifiedAs: identifiedAs,
              isComplete: false,
            );
    }
  }

  void reset() => state = const StainIdle();

  /// Records the treatment against the item.
  ///
  /// Through [WearRecorder.recordCondition] rather than by appending the event
  /// here, and the difference is not cosmetic: that method also folds the
  /// observation into the item's own `condition`, which is what
  /// `hasStainAwaitingAWash` reads and therefore what puts "check this before
  /// it goes near heat" on the load card. Appending the event alone would look
  /// right in the history and leave the wash plan silent.
  ///
  /// A `WearType.stain` observation rather than an event of its own: a stain
  /// *is* an observation about condition, the projection already exists, and a
  /// new event type would have to be taught to the sync contract and to every
  /// reducer for nothing the user can see.
  ///
  /// Logged at the mildest grade, because this records a stain that has just
  /// been *treated* rather than an assessment of what is left — nobody can
  /// judge that until it dries, and overstating it would drag the garment's
  /// condition down for something that may well have come out.
  Future<void> record(String substance) => _ref
      .read(wearRecorderProvider)
      .recordCondition(
        itemId,
        type: WearType.stain,
        severity: WearSeverity.slight,
        note: 'Treated: $substance',
      );
}

/// The care summary in the same words the item screen uses.
String _careSummary(WardrobeItem item) {
  final care = item.effectiveCare;
  return [
    washSummary(care.wash),
    drySummary(care.dry),
    care.bleach.label,
    if (dryCleanSummary(care) case final String line) line,
  ].join('. ');
}

/// Keyed by item, so advice for one garment is not shown against another.
final stainControllerProvider =
    StateNotifierProvider.family<StainController, StainState, ItemId>(
      StainController.new,
    );
