/// Asking a model what goes with what.
///
/// The one place in this app where a model's *opinion* is the thing being
/// asked for. Everywhere else — a care label, a stain, a fibre — the model
/// perceives and the core judges, because being wrong ruins a garment. Nothing
/// here can ruin anything: the worst a bad outfit costs is a bad day, and the
/// judgements involved (pattern against pattern, proportion, how formal a thing
/// reads) are exactly the ones [OutfitBuilder] cannot make and a model can.
///
/// What is still not delegated is the facts. `StyleVetting` resolves every id
/// against the real wardrobe before a single garment is drawn, so a model that
/// invents a plausible id or forgets that the shirt is in the machine produces
/// a dropped suggestion rather than a wrong one.
///
/// Asked for explicitly rather than on every rebuild. It is a paid call over a
/// network, and a screen that fired one each time somebody switched tabs would
/// be spending their money to answer a question they had not asked.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';
import '../../data/api/style_dto.dart';

sealed class StylistState {
  const StylistState();
}

/// Nothing asked for yet.
final class StylistIdle extends StylistState {
  const StylistIdle();
}

final class StylistThinking extends StylistState {
  const StylistThinking();
}

/// Vetted ideas, ready to show.
///
/// Carries the refusals as well as the outfits. A model asked for five ideas
/// that returns two usable ones has not failed, but silently drawing two after
/// somebody asked for ideas looks like a thin wardrobe rather than a model
/// naming clothes that are in the wash — and those want different responses.
final class StylistSuggested extends StylistState {
  const StylistSuggested(
    this.result, {
    required this.occasion,
    this.gaps = const SuggestedPieces(),
  });

  final StyledOutfits result;
  final Occasion occasion;

  /// Pieces the wardrobe does not have, if they were asked for. Kept apart
  /// from [result]: nothing here can be opened, saved or worn.
  final SuggestedPieces gaps;

  List<StyledOutfit> get outfits => result.outfits;

  List<SuggestedPiece> get pieces => gaps.pieces;

  /// Why ideas were dropped, each reason once.
  ///
  /// Deduplicated because three proposals refused for the same reason is one
  /// fact about the answer, not three.
  List<String> get setAside =>
      {for (final refused in result.refused) refused.refusal.reason}.toList();
}

final class StylistFailed extends StylistState {
  const StylistFailed(this.message, {this.isRetryable = true});

  final String message;
  final bool isRetryable;
}

class StylistController extends StateNotifier<StylistState> {
  StylistController(this._ref) : super(const StylistIdle());

  final Ref _ref;

  /// Asks for ideas for [request], and checks what comes back.
  ///
  /// With [suggestGaps] it also asks what the wardrobe is missing, off unless
  /// the screen says otherwise.
  Future<void> ask(
    OutfitRequest request, {
    String? note,
    bool suggestGaps = false,
  }) async {
    final owned = await _ref
        .read(wardrobeRepositoryProvider)
        .query(const WardrobeQuery.owned());

    // Only what could actually be worn today. The vetting refuses unavailable
    // garments anyway, but refusing them after the model has already built an
    // outfit around one spends a call to throw the answer away — and the
    // refusal stays worth keeping for the race where something reaches the
    // basket while the request is in flight.
    final wearable = [
      for (final item in owned)
        if (item.lifecycle.isWearable) item,
    ];

    if (wearable.length < 2) {
      state = const StylistFailed(
        'There is not enough in your wardrobe to put an outfit together yet.',
        isRetryable: false,
      );
      return;
    }

    state = const StylistThinking();

    final StyleAnswer answer;
    try {
      answer = await _ref
          .read(aiGatewayProvider)
          .proposeOutfits(
            wardrobe: wearable,
            occasion: request.occasion.label,
            season: request.season == Season.allSeason
                ? null
                : request.season.label,
            count: request.count,
            note: note,
            suggestGaps: suggestGaps,
          );
    } on ScanFailure catch (failure) {
      state = StylistFailed(failure.message, isRetryable: failure.isRetryable);
      return;
    } on ScanContractError catch (error) {
      state = StylistFailed(
        'The server sent something this version cannot read. $error',
        isRetryable: false,
      );
      return;
    }

    if (!mounted) return;

    // Against `owned` rather than `wearable`: an id the model was never offered
    // is a different mistake from one it was, and vetting against the smaller
    // list would report a garment that went into the wash mid-request as
    // invented rather than as unavailable.
    state = StylistSuggested(
      const StyleVetting().vet(answer.outfits, wardrobe: owned),
      occasion: request.occasion,
      // Against the whole wardrobe rather than the wearable subset: jeans in
      // the laundry basket are still owned, and owning them is the question.
      gaps: const GapVetting().vet(answer.pieces, wardrobe: owned),
    );
  }

  /// Back to the button, so a failure is not permanent and a fresh ask is not
  /// drawn over the last answer.
  void reset() => state = const StylistIdle();
}

final stylistControllerProvider =
    StateNotifierProvider<StylistController, StylistState>(
      StylistController.new,
    );
