/// Recognising an item the user has already scanned.
///
/// The promise is "never scan the same garment twice". Delivering it means
/// deciding, from a photo, whether this is the grey Nike hoodie already in the
/// wardrobe or a different grey hoodie entirely.
///
/// ## What v1 can and cannot do
///
/// [AttributeMatcher] compares structured attributes — type, colour in CIELAB,
/// brand, composition, size. That reliably distinguishes a navy hoodie from a
/// red dress, and it works entirely offline with no model to ship.
///
/// It genuinely **cannot** tell apart two visually identical garments: three
/// black t-shirts of the same brand and size will all match each other. That is
/// a real limitation, not a bug to be tuned away, and it is why the matcher
/// returns *ranked candidates with confidence* rather than a verdict — the app
/// asks the user when the top candidates are close.
///
/// [MatcherChain] exists so an embedding-based matcher can be added later and
/// combined with this one without any caller changing.
library;

import '../shared/confidence.dart';
import '../shared/ids.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'fingerprint.dart';

/// One possible identification, with how strongly it is believed.
final class MatchCandidate {
  const MatchCandidate({
    required this.itemId,
    required this.score,
    this.contributions = const {},
  });

  final ItemId itemId;

  /// Similarity in `0..1`, where 1 is a perfect attribute match.
  final double score;

  /// Per-signal breakdown, so a decision can be explained and debugged.
  final Map<String, double> contributions;

  @override
  String toString() =>
      'MatchCandidate(${itemId.value}, ${(score * 100).round()}%)';
}

/// What the app should do with a match attempt.
sealed class MatchDecision {
  const MatchDecision();

  /// The candidates considered, best first.
  List<MatchCandidate> get candidates;
}

/// Confident enough to reuse the existing item without asking.
final class RecognizedItem extends MatchDecision {
  const RecognizedItem({required this.match, required this.candidates});

  final MatchCandidate match;

  @override
  final List<MatchCandidate> candidates;

  ItemId get itemId => match.itemId;

  @override
  String toString() => 'RecognizedItem(${match.itemId.value})';
}

/// Plausible, but worth confirming — "Is this your grey Nike hoodie?".
final class NeedsConfirmation extends MatchDecision {
  const NeedsConfirmation({
    required this.best,
    required this.candidates,
    required this.reason,
  });

  final MatchCandidate best;

  /// Why confirmation is needed, for the prompt shown to the user.
  final String reason;

  @override
  final List<MatchCandidate> candidates;

  @override
  String toString() => 'NeedsConfirmation(${best.itemId.value}: $reason)';
}

/// Nothing in the wardrobe resembles this. Treat it as new.
final class UnrecognizedItem extends MatchDecision {
  const UnrecognizedItem({this.candidates = const []});

  @override
  final List<MatchCandidate> candidates;

  @override
  String toString() => 'UnrecognizedItem()';
}

/// Ranks wardrobe items by how well they match a fingerprint.
abstract interface class ItemMatcher {
  /// Identifier used when reporting per-matcher contributions.
  String get name;

  /// How much this matcher's opinion counts when several are combined.
  double get weight;

  /// Scores [candidates] against [probe], best first.
  List<MatchCandidate> rank(
    GarmentFingerprint probe,
    Iterable<WardrobeItem> candidates,
  );
}

/// Turns ranked candidates into a decision.
final class MatchResolver {
  const MatchResolver({
    this.recogniseAbove = 0.88,
    this.confirmAbove = 0.62,
    this.ambiguityMargin = 0.06,
  });

  /// Score above which an item is accepted without asking.
  final double recogniseAbove;

  /// Score above which the user is asked to confirm.
  final double confirmAbove;

  /// How close the top two candidates must be before the result is treated as
  /// ambiguous regardless of the leader's score.
  ///
  /// This is what stops the app confidently picking one of three identical
  /// black t-shirts.
  final double ambiguityMargin;

  MatchDecision resolve(List<MatchCandidate> ranked) {
    if (ranked.isEmpty) return const UnrecognizedItem();

    final best = ranked.first;
    if (best.score < confirmAbove) {
      return UnrecognizedItem(candidates: ranked);
    }

    final runnerUp = ranked.length > 1 ? ranked[1] : null;
    final isAmbiguous =
        runnerUp != null && (best.score - runnerUp.score) < ambiguityMargin;

    if (isAmbiguous) {
      return NeedsConfirmation(
        best: best,
        candidates: ranked,
        reason: 'Several items in your wardrobe look almost identical to this '
            'one.',
      );
    }

    if (best.score >= recogniseAbove) {
      return RecognizedItem(match: best, candidates: ranked);
    }

    return NeedsConfirmation(
      best: best,
      candidates: ranked,
      reason: 'This looks like an item you already have, but not closely '
          'enough to be sure.',
    );
  }

  /// Converts a match score into a [Confident] wrapper for storage.
  Confident<ItemId> asConfidentId(MatchCandidate candidate) => Confident(
        candidate.itemId,
        confidence: candidate.score,
        source: Provenance.aiInference,
      );
}

/// Combines several matchers into one ranking.
///
/// The seam that makes embeddings a drop-in addition: register an
/// `EmbeddingMatcher` alongside the attribute matcher and the scores merge by
/// weight, with no caller aware anything changed.
final class MatcherChain implements ItemMatcher {
  const MatcherChain(this.matchers);

  final List<ItemMatcher> matchers;

  @override
  String get name => 'chain';

  @override
  double get weight => 1.0;

  @override
  List<MatchCandidate> rank(
    GarmentFingerprint probe,
    Iterable<WardrobeItem> candidates,
  ) {
    if (matchers.isEmpty) return const [];
    if (matchers.length == 1) return matchers.first.rank(probe, candidates);

    final totals = <ItemId, double>{};
    final contributions = <ItemId, Map<String, double>>{};
    var totalWeight = 0.0;

    for (final matcher in matchers) {
      totalWeight += matcher.weight;
      for (final candidate in matcher.rank(probe, candidates)) {
        totals.update(
          candidate.itemId,
          (value) => value + candidate.score * matcher.weight,
          ifAbsent: () => candidate.score * matcher.weight,
        );
        (contributions[candidate.itemId] ??= {})[matcher.name] =
            candidate.score;
      }
    }

    if (totalWeight == 0) return const [];

    final merged = [
      for (final entry in totals.entries)
        MatchCandidate(
          itemId: entry.key,
          score: entry.value / totalWeight,
          contributions: contributions[entry.key] ?? const {},
        ),
    ]..sort((x, y) => y.score.compareTo(x.score));

    return merged;
  }
}
