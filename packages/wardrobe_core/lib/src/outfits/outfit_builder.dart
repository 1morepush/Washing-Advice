/// Suggesting something to wear.
///
/// The brief for this feature is not "generate every valid combination" — a
/// two-hundred-item wardrobe has millions, and a list of millions is worse
/// than no list. It is "show me a handful of things I would actually wear,
/// including ones I have forgotten I own".
///
/// That shapes the algorithm. Rather than enumerate the product of all slots,
/// the builder scores each item on its own, keeps only the strongest few per
/// slot, and enumerates within that shortlist. The combinatorics stay bounded
/// by [_shortlist] regardless of wardrobe size, and the results stay
/// explainable because every suggestion can name why each piece was chosen.
///
/// It also states its reasoning. A suggestion with no explanation is either
/// obeyed blindly or ignored, and both are worse than a suggestion the user
/// can argue with.
library;

import 'dart:math' as math;

import '../shared/clock.dart';
import '../shared/ids.dart';
import '../wardrobe/model/item_attributes.dart';
import '../wardrobe/model/item_color.dart';
import '../wardrobe/model/relationship.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'color_harmony.dart';
import 'model/occasion.dart';
import 'model/outfit.dart';
import 'weather.dart';
import 'weather_fit.dart';

/// How many candidates per slot survive individual scoring.
///
/// Four is enough that the pairing stage has real choices to make and small
/// enough that the worst case — four tops, four bottoms, four layers, four
/// pairs of shoes — is a few hundred combinations rather than millions.
const int _shortlist = 4;

/// Days after which an item counts as neglected, and gets a nudge.
const int _neglectedAfterDays = 60;

/// How much a suggestion is discounted per item it reuses from one already
/// chosen.
///
/// Ranking by score alone produced five suggestions that shared the same jeans
/// and the same shoes, because the same well-matching bottom pairs well with
/// every top. Five variations on one outfit is one suggestion presented five
/// times. Applied multiplicatively so reusing two items costs more than
/// reusing one, and gently enough that a wardrobe with only one pair of shoes
/// still gets suggestions rather than a shorter list.
const double _repeatPenalty = 0.8;

/// A weather adjustment at or below this marks a piece as a misfit for the
/// day (see `_dropWeatherMisfits`).
const double _misfitBelow = -0.3;

/// What the user is dressing for.
final class OutfitRequest {
  const OutfitRequest({
    this.occasion = Occasion.everyday,
    this.season = Season.allSeason,
    this.count = 5,
    this.includeOuterwear = false,
    this.includeFootwear = true,
    this.mustInclude,
    this.exclude = const {},
    this.needs,
  });

  final Occasion occasion;
  final Season season;

  /// How many suggestions to return.
  final int count;

  final bool includeOuterwear;
  final bool includeFootwear;

  /// Build outfits around this item — "what goes with this?".
  final ItemId? mustInclude;

  /// Items to leave out: already packed, in the wash, deliberately rejected.
  final Set<ItemId> exclude;

  /// What today's weather asks of the outfit, or null to ignore the weather.
  ///
  /// Null is not "mild": with no needs the builder behaves exactly as it did
  /// before weather existed, which is what the person gets until they set a
  /// place and what they get from "ignore the weather".
  final DressingNeeds? needs;
}

/// One proposed outfit, with its reasoning.
final class OutfitSuggestion {
  const OutfitSuggestion({
    required this.items,
    required this.score,
    required this.reasons,
    this.weatherReasons = const [],
  });

  final List<WardrobeItem> items;

  /// `0..1`, comparable only against other suggestions from the same request.
  final double score;

  /// Why this was suggested, in plain English, strongest reason first.
  final List<String> reasons;

  /// Why this suits today's weather, e.g. "Cold and rainy: a waterproof
  /// jacket and closed shoes". Empty when the request carried no weather.
  /// Kept apart from [reasons] so the screen can lead with it.
  final List<String> weatherReasons;

  Iterable<ItemId> get itemIds => items.map((i) => i.id);

  /// A stable key for deduplication, independent of the order slots were
  /// filled in.
  String get signature =>
      (itemIds.map((id) => id.value).toList()..sort()).join('|');

  @override
  String toString() =>
      '${items.map((i) => i.displayName).join(' + ')} (${score.toStringAsFixed(2)})';
}

/// Builds outfit suggestions from a wardrobe.
final class OutfitBuilder {
  const OutfitBuilder({
    this.relationships,
    this.clock = const SystemClock(),
  });

  /// Recorded links between items. Optional: without it the builder falls back
  /// to colour and usage alone, which is the state of every new wardrobe.
  final RelationshipGraph? relationships;

  final Clock clock;

  List<OutfitSuggestion> suggest(
    List<WardrobeItem> wardrobe,
    OutfitRequest request,
  ) {
    final now = clock.now();
    final needs = request.needs;
    final anchor = request.mustInclude == null
        ? null
        : wardrobe.where((i) => i.id == request.mustInclude).firstOrNull;

    final bySlot = <OutfitSlot, List<_Candidate>>{};
    for (final item in wardrobe) {
      if (request.exclude.contains(item.id)) continue;
      if (!_isAvailable(item, request)) continue;

      final slot = OutfitSlot.ofType(item.type.value);
      if (slot == null || slot == OutfitSlot.accessory) continue;

      (bySlot[slot] ??= []).add(_Candidate(item, _scoreItem(item, now, needs)));
    }

    for (final candidates in bySlot.values) {
      candidates.sort((a, b) => b.score.compareTo(a.score));
    }
    if (needs != null) _dropWeatherMisfits(bySlot, needs);

    // An anchor is forced into its slot as the only candidate, so every
    // suggestion contains it. Ranking it against alternatives it is meant to
    // replace would be answering a question the user did not ask.
    if (anchor != null) {
      final slot = OutfitSlot.ofType(anchor.type.value);
      if (slot == null) return const [];
      bySlot[slot] = [_Candidate(anchor, _scoreItem(anchor, now, needs))];
    }

    final bases = _bases(bySlot, shortlist: _shortlist);
    final suggestions = <String, OutfitSuggestion>{};

    for (final base in bases) {
      var items = base;
      if (request.includeOuterwear || (needs?.outerLayer ?? false)) {
        items = _addBestFit(items, bySlot[OutfitSlot.outerwear]);
      }
      if (request.includeFootwear) {
        items = _addBestFit(items, bySlot[OutfitSlot.footwear]);
      }

      final suggestion = _assess(items, now, needs);
      // Ties on signature are impossible to tell apart, so the first wins;
      // scores would be identical anyway.
      suggestions.putIfAbsent(suggestion.signature, () => suggestion);
    }

    final ranked = suggestions.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return _diversify(ranked, request.count);
  }

  /// Removes the pieces that are plainly wrong for the weather — shorts in a
  /// freeze, sandals in the rain — from any slot that has something better.
  ///
  /// Scoring alone left them in: diversification penalises reusing the one
  /// good pair of trousers, which let the shorts back in as the "different"
  /// option. A slot whose every candidate is a misfit keeps them all, so a
  /// small wardrobe still gets an outfit.
  void _dropWeatherMisfits(
    Map<OutfitSlot, List<_Candidate>> bySlot,
    DressingNeeds needs,
  ) {
    for (final candidates in bySlot.values) {
      final fine = [
        for (final c in candidates)
          if (weatherAdjustment(c.item, needs) > _misfitBelow) c,
      ];
      if (fine.isNotEmpty && fine.length < candidates.length) {
        candidates
          ..clear()
          ..addAll(fine);
      }
    }
  }

  /// Picks [count] suggestions that are not all the same outfit.
  ///
  /// Greedy: take the best, then re-score what is left against what has
  /// already been chosen. An anchored request is unaffected, because every
  /// candidate contains the anchor and the penalty applies to all of them
  /// equally.
  List<OutfitSuggestion> _diversify(List<OutfitSuggestion> ranked, int count) {
    final chosen = <OutfitSuggestion>[];
    final used = <ItemId, int>{};
    final pool = [...ranked];

    while (chosen.length < count && pool.isNotEmpty) {
      var bestIndex = 0;
      var best = double.negativeInfinity;

      for (var i = 0; i < pool.length; i++) {
        final repeats = pool[i].itemIds.fold<int>(
              0,
              (sum, id) => sum + (used[id] ?? 0),
            );
        final adjusted = pool[i].score * math.pow(_repeatPenalty, repeats);
        if (adjusted > best) {
          best = adjusted.toDouble();
          bestIndex = i;
        }
      }

      final pick = pool.removeAt(bestIndex);
      chosen.add(pick);
      for (final id in pick.itemIds) {
        used[id] = (used[id] ?? 0) + 1;
      }
    }

    return chosen;
  }

  /// Whether the item is a legitimate choice for this request at all.
  ///
  /// These are hard filters rather than score penalties: a coat is not a
  /// slightly worse summer choice, and something in the wash is not available
  /// at any score.
  bool _isAvailable(WardrobeItem item, OutfitRequest request) {
    if (!item.lifecycle.isWearable) return false;
    if (!_suitsSeason(item, request.season)) return false;
    // A coat is not on the everyday list, which is a styling default. When the
    // weather calls for a layer, a proper jacket or coat is allowed anyway:
    // being cold is a better reason than a default.
    if ((request.needs?.outerLayer ?? false) && item.isProperOuterLayer) {
      return true;
    }
    return _suitsOccasion(item, request.occasion);
  }

  bool _suitsSeason(WardrobeItem item, Season season) =>
      season == Season.allSeason ||
      item.seasons.isEmpty ||
      item.seasons.contains(season) ||
      item.seasons.contains(Season.allSeason);

  /// Type defaults, overridable by tag — see the note on [Occasion].
  bool _suitsOccasion(WardrobeItem item, Occasion occasion) =>
      item.tags.contains(occasion.tag) || occasion.suits(item.type.value);

  /// How good a choice this item is, ignoring what it will be worn with.
  double _scoreItem(WardrobeItem item, DateTime now, [DressingNeeds? needs]) {
    var score = 0.5;

    if (item.isFavorite) score += 0.15;

    // Surfacing neglected clothes is the point of the feature. Someone who
    // wanted their three most-worn items would not need an app to find them.
    final idle = item.usage.idleFor(now);
    if (item.usage.hasNeverBeenWorn) {
      score += 0.2;
    } else if (idle != null && idle.inDays >= _neglectedAfterDays) {
      score += 0.15;
    } else if (idle != null && idle.inDays <= 2) {
      // Worn in the last couple of days. Not disqualifying — some people wear
      // the same jeans all week on purpose — but it should not lead.
      score -= 0.25;
    }

    if (item.condition.warrantsGentlerCare) score -= 0.05;

    score = score.clamp(0.0, 1.0);
    if (needs != null)
      score = (score + weatherAdjustment(item, needs)).clamp(0.0, 1.0);
    return score;
  }

  /// Every combination of the shortlisted tops and bottoms, plus every
  /// shortlisted one-piece.
  ///
  /// A dress is an outfit's base on its own, which is why [OutfitSlot] has a
  /// `fullBody` value at all — treating it as a top and leaving the bottom
  /// unfilled would report a gap that is not there.
  List<List<WardrobeItem>> _bases(
    Map<OutfitSlot, List<_Candidate>> bySlot, {
    required int shortlist,
  }) {
    final tops = _take(bySlot[OutfitSlot.top], shortlist);
    final bottoms = _take(bySlot[OutfitSlot.bottom], shortlist);
    final onePieces = _take(bySlot[OutfitSlot.fullBody], shortlist);

    return [
      for (final piece in onePieces) [piece],
      for (final top in tops)
        for (final bottom in bottoms) [top, bottom],
    ];
  }

  List<WardrobeItem> _take(List<_Candidate>? candidates, int n) => [
        for (final candidate in (candidates ?? const <_Candidate>[]).take(n))
          candidate.item,
      ];

  /// Adds the shortlisted item from [candidates] that best harmonises with
  /// what is already chosen, or returns the outfit unchanged if there is none.
  List<WardrobeItem> _addBestFit(
    List<WardrobeItem> items,
    List<_Candidate>? candidates,
  ) {
    final shortlisted = (candidates ?? const <_Candidate>[]).take(_shortlist);
    if (shortlisted.isEmpty) return items;

    _Candidate? best;
    var bestScore = double.negativeInfinity;
    for (final candidate in shortlisted) {
      final score =
          _harmony([...items, candidate.item]) * 0.6 + candidate.score * 0.4;
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return [...items, best!.item];
  }

  OutfitSuggestion _assess(
    List<WardrobeItem> items,
    DateTime now,
    DressingNeeds? needs,
  ) {
    final harmony = _harmony(items);
    final individual =
        items.map((i) => _scoreItem(i, now, needs)).reduce((a, b) => a + b) /
            items.length;
    final affinity = _affinity(items);

    // Weighting: how the pieces look together matters most, since that is the
    // question being asked. Individual desirability breaks ties and is what
    // surfaces neglected clothes. Recorded links are a small deliberate nudge
    // — they encode the user's own past choices, but leaning on them hard
    // would make the builder repeat outfits back rather than propose any.
    final score = harmony * 0.5 + individual * 0.35 + affinity * 0.15;

    return OutfitSuggestion(
      items: items,
      score: score.clamp(0.0, 1.0),
      reasons: _reasons(items, now, affinity: affinity),
      weatherReasons: needs == null ? const [] : weatherReasons(items, needs),
    );
  }

  /// What the wardrobe cannot supply for the request's weather, e.g. "No
  /// waterproof layer in your wardrobe". Empty without weather.
  List<String> weatherGapsFor(
    List<WardrobeItem> wardrobe,
    OutfitRequest request,
  ) {
    final needs = request.needs;
    return needs == null ? const [] : weatherGaps(wardrobe, needs);
  }

  double _harmony(List<WardrobeItem> items) => harmonyOf([
        for (final item in items)
          if (item.colors.value.dominant case final ItemColor color) color,
      ]);

  /// How strongly the wardrobe's recorded links connect these items, `0..1`.
  double _affinity(List<WardrobeItem> items) {
    final graph = relationships;
    if (graph == null || items.length < 2) return 0;

    var total = 0.0;
    var pairs = 0;
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        pairs++;
        total += _edgeStrength(graph, items[i].id, items[j].id);
      }
    }
    return pairs == 0 ? 0 : total / pairs;
  }

  double _edgeStrength(RelationshipGraph graph, ItemId a, ItemId b) {
    var strongest = 0.0;
    for (final edge in graph.edgesFor(a)) {
      if (edge.otherEnd(a) != b) continue;
      final weight = switch (edge.kind) {
        RelationKind.pairsWith => 1.0,
        RelationKind.wornWith => 0.8,
        RelationKind.suitSet => 1.0,
        RelationKind.partOfOutfit => 0.6,
        _ => 0.0,
      };
      final strength = weight * edge.strength;
      if (strength > strongest) strongest = strength;
    }
    return strongest;
  }

  List<String> _reasons(
    List<WardrobeItem> items,
    DateTime now, {
    required double affinity,
  }) {
    final reasons = <String>[];

    if (affinity >= 0.5) reasons.add('You have worn these together before');

    // The colour note describes the pair that scored worst, because that is
    // the one the user will look at and question.
    if (_weakestPairing(items) case final String note) reasons.add(note);

    for (final item in items) {
      if (item.usage.hasNeverBeenWorn) {
        reasons.add('${item.displayName} has never been worn');
        continue;
      }
      final idle = item.usage.idleFor(now);
      if (idle != null && idle.inDays >= _neglectedAfterDays) {
        reasons.add(
          '${item.displayName} has not been worn in ${idle.inDays} days',
        );
      }
    }

    return reasons;
  }

  String? _weakestPairing(List<WardrobeItem> items) {
    final colors = [
      for (final item in items)
        if (item.colors.value.dominant case final ItemColor color) color,
    ];
    if (colors.length < 2) return null;

    ItemColor? worstX;
    ItemColor? worstY;
    var worst = double.infinity;
    for (var i = 0; i < colors.length; i++) {
      for (var j = i + 1; j < colors.length; j++) {
        final score = harmonyBetween(colors[i], colors[j]);
        if (score < worst) {
          worst = score;
          worstX = colors[i];
          worstY = colors[j];
        }
      }
    }
    if (worstX == null || worstY == null) return null;
    return describePairing(worstX, worstY);
  }
}

/// An item with its standalone score, before anything is paired with it.
final class _Candidate {
  const _Candidate(this.item, this.score);

  final WardrobeItem item;
  final double score;
}
