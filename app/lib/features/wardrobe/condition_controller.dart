/// Photographing a garment to see whether it has worn.
///
/// The chain this completes has been missing its first step since M1: the core
/// has always known that a pilling jumper needs a gentler cycle than its label
/// says, and the only way to tell it was a form. Nobody opens a form to report
/// pilling.
///
/// Nothing here records anything. The model looks, `ConditionReview` in the
/// core decides which findings are worth putting to a user, and only a tap
/// turns one into a [WearObservation]. That is three deliberate steps for what
/// could have been one, because a wear observation changes the condition grade,
/// can push a garment to end-of-life, and changes how the thing is washed from
/// the next load onward — all on the strength of a photograph of a jumper on a
/// bed.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';
import '../history/wear_recorder.dart';

sealed class ConditionCheckState {
  const ConditionCheckState();
}

final class ConditionIdle extends ConditionCheckState {
  const ConditionIdle();
}

final class ConditionLooking extends ConditionCheckState {
  const ConditionLooking();
}

/// What the review let through, ready to be confirmed or ignored.
///
/// [found] being empty is the commonest outcome and is not a failure. The
/// screen says so plainly rather than showing nothing, because "we looked and
/// it is fine" is a useful answer and a blank panel is not.
final class ConditionRead extends ConditionCheckState {
  const ConditionRead(this.report);

  final ConditionReport report;

  List<NoticedWear> get found => report.noticed;

  /// How many findings the review threw away.
  ///
  /// Surfaced quietly rather than hidden. Somebody who can see a hole and is
  /// told nothing was found deserves to know the app saw something and was not
  /// sure enough to say — otherwise the feature looks blind rather than
  /// careful.
  int get setAside => report.dismissed.length;
}

final class ConditionFailed extends ConditionCheckState {
  const ConditionFailed(this.message, {this.isRetryable = true});

  final String message;
  final bool isRetryable;
}

class ConditionController extends StateNotifier<ConditionCheckState> {
  ConditionController(this._ref, this.itemId) : super(const ConditionIdle());

  final Ref _ref;
  final ItemId itemId;

  /// Looks the garment over, and checks what comes back.
  Future<void> look(List<ScanImage> images) async {
    if (images.isEmpty) return;

    final item = await _ref.read(wardrobeRepositoryProvider).byId(itemId);
    if (item == null) {
      state = const ConditionFailed(
        'That item is no longer in your wardrobe.',
        isRetryable: false,
      );
      return;
    }

    state = const ConditionLooking();

    final List<ObservedWear> observed;
    try {
      observed = await _ref
          .read(aiGatewayProvider)
          .readCondition(
            images: images,
            garment: _describe(item),
            fabric: item.composition.value.label,
            // So the model is not asked to re-find what is already recorded,
            // and so "worse than last time" is a judgement it can make rather
            // than one this side has to infer from a severity alone.
            known: _knownWear(item),
          );
    } on ScanFailure catch (failure) {
      state = ConditionFailed(
        failure.message,
        isRetryable: failure.isRetryable,
      );
      return;
    } on ScanContractError catch (error) {
      state = ConditionFailed(
        'The server sent something this version cannot read. $error',
        isRetryable: false,
      );
      return;
    }

    if (!mounted) return;

    state = ConditionRead(const ConditionReview().read(observed, item: item));
  }

  /// Records one finding the user accepted.
  ///
  /// One at a time rather than all at once. Each is a separate claim about the
  /// garment and the user may agree with one and not the next, and a single
  /// "accept" button would collect agreement it had not been given.
  Future<void> accept(NoticedWear wear) async {
    await _ref
        .read(wearRecorderProvider)
        .recordCondition(
          itemId,
          type: wear.type,
          severity: wear.severity,
          note: wear.observed.note,
        );

    if (!mounted) return;
    if (state case final ConditionRead read) {
      state = ConditionRead(
        ConditionReport(
          noticed: [
            for (final other in read.found)
              if (other != wear) other,
          ],
          dismissed: read.report.dismissed,
        ),
      );
    }
  }

  /// Throws one away without recording it.
  void dismiss(NoticedWear wear) {
    if (state case final ConditionRead read) {
      state = ConditionRead(
        ConditionReport(
          noticed: [
            for (final other in read.found)
              if (other != wear) other,
          ],
          dismissed: read.report.dismissed,
        ),
      );
    }
  }

  void reset() => state = const ConditionIdle();

  /// The garment in the words the app already shows for it.
  ///
  /// The name alone is not enough — somebody's "Blue one" tells a model
  /// nothing — and the type alone throws away everything they typed. Both,
  /// which is what the wardrobe row shows anyway.
  String _describe(WardrobeItem item) =>
      '${item.displayName} (${item.type.value.label})';

  /// What is already on record, as a sentence.
  ///
  /// Only the current state of each kind of wear, which is what
  /// [ConditionAssessment.current] means: the history matters to the app and
  /// not to a model being asked what it can see today.
  String? _knownWear(WardrobeItem item) {
    final current = item.condition.current.values;
    if (current.isEmpty) return null;
    return current
        .map(
          (o) =>
              '${o.severity.label.toLowerCase()} '
              '${o.type.label.toLowerCase()}',
        )
        .join(', ');
  }
}

final conditionControllerProvider = StateNotifierProvider.family
    .autoDispose<ConditionController, ConditionCheckState, ItemId>(
      ConditionController.new,
    );
