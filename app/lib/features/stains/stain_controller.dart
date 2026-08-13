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
final class StainAdvised extends StainState {
  const StainAdvised({
    required this.substance,
    required this.plan,
    this.identifiedAs,
  });

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

  /// Asks for a treatment and vets it before anyone sees it.
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

    final StainAdvice advice;
    try {
      advice = await _ref
          .read(aiGatewayProvider)
          .adviseOnStain(
            substance: substance.trim(),
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

    state = StainAdvised(
      substance: substance.trim(),
      // The whole point. Everything the label forbids is dropped here, with
      // the reason, before a single step is drawn.
      plan: const StainSafety().vet(advice.steps, item: item),
      identifiedAs: advice.identifiedAs,
    );
  }

  void reset() => state = const StainIdle();

  /// Records the treatment against the item.
  ///
  /// A `ConditionObserved` rather than an event of its own: a stain *is* an
  /// observation about the garment's condition, the projection that counts
  /// them already exists, and a new event type would have to be taught to the
  /// sync contract and to every reducer for no gain the user can see.
  Future<void> record(String substance) async {
    final ids = _ref.read(idGeneratorProvider);
    final now = DateTime.now();

    await _ref
        .read(eventLogProvider)
        .append(
          ConditionObserved(
            id: EventId(ids.next()),
            itemId: itemId,
            occurredAt: now,
            recordedAt: now,
            observation: WearObservation(
              type: WearType.stain,
              // The mildest grade on purpose. This records a stain that has
              // just been *treated*, not an assessment of what is left —
              // nobody can judge that until it has dried, and overstating it
              // would drag the item's condition down for something that may
              // well have come out.
              severity: WearSeverity.slight,
              observedAt: now,
              note: 'Treated: $substance',
            ),
          ),
        );

    _ref.invalidate(itemProvider(itemId));
  }
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
