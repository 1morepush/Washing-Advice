/// Saying what you wore, at the moment you are least willing to say anything.
///
/// The app has always been able to record this — "Wore it" on a garment's own
/// screen, and "Put in the wash" on the clean pile. Both are per-garment and
/// they live on different screens, so logging three things worn today meant
/// finding each one twice. That is a fine cost at a desk and an impossible one
/// at the front door at the end of a working day, which is the only moment
/// this information exists.
///
/// So the whole design is about the *ordering*. Nothing here is faster than
/// tapping three garments — the work is making sure the three you want are the
/// three already on screen, because a scroll or a search is where somebody
/// tired gives up and throws the clothes in the pile unrecorded.
///
/// Four signals do that, and they are all facts the app already holds:
///
/// * **Worn with something you have already picked.** Much the strongest, and
///   the reason the list re-sorts as you tap. Clothes are worn in outfits, so
///   the second and third answers are usually neighbours of the first.
/// * **Worn recently.** People re-wear.
/// * **Due a wash.** `wearsSinceWash` is the domain's own answer to "does this
///   need washing", and something on its third wear is a likelier candidate
///   than something fresh out of the drawer.
/// * **Worn often.** Favourites come round again.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../history/wear_recorder.dart';
import 'laundry_controller.dart';

/// One garment offered as something you might have worn.
final class WornCandidate {
  const WornCandidate({required this.item, required this.wornWithPicked});

  final WardrobeItem item;

  /// Whether this is usually worn with something already selected.
  ///
  /// Surfaced as well as ranked on. A garment jumping up the list is
  /// disorienting unless it says why, and "usually with what you picked" is a
  /// claim the user can check against their own memory.
  final bool wornWithPicked;
}

final class WornTodayState {
  const WornTodayState({
    this.candidates = const [],
    this.selected = const {},
    this.saving = false,
    this.saved = 0,
  });

  /// Clean garments, likeliest first.
  final List<WornCandidate> candidates;

  final Set<ItemId> selected;

  final bool saving;

  /// How many were logged, once it is done.
  final int saved;

  bool get isDone => saved > 0;
}

class WornTodayController extends StateNotifier<WornTodayState> {
  WornTodayController(this._ref) : super(const WornTodayState()) {
    ready = _load();
  }

  final Ref _ref;

  /// Completes once the wardrobe and the co-wear graph are in hand.
  ///
  /// Exposed because the ranking is the whole feature, and a test that
  /// asserted on it before the load finished would be asserting on an empty
  /// list — which passes for the wrong reason far too easily.
  late final Future<void> ready;

  RelationshipGraph _graph = RelationshipGraph.empty();
  List<WardrobeItem> _clean = const [];

  Future<void> _load() async {
    // Only what is in the wardrobe. A garment already in the basket cannot
    // have been worn today and put back in the basket, and offering it would
    // spend the top of the list on answers that are already recorded.
    final items = await _ref
        .read(wardrobeRepositoryProvider)
        .query(const WardrobeQuery.owned());
    _clean = [
      for (final item in items)
        if (item.lifecycle == LifecycleState.active) item,
    ];

    try {
      _graph = await _ref.read(coWearGraphProvider.future);
    } on Exception {
      // Derived from the event log, so a wardrobe with no history has none.
      // That is the ordinary first-week state, not a failure.
      _graph = RelationshipGraph.empty();
    }

    if (!mounted) return;
    state = WornTodayState(candidates: _rank(const {}), selected: const {});
  }

  /// Orders the clean wardrobe by how likely each garment is to be the answer.
  List<WornCandidate> _rank(Set<ItemId> selected) {
    final neighbours = <ItemId>{
      for (final id in selected)
        ..._graph.neighbours(id, kind: RelationKind.wornWith),
    };

    final scored =
        [
          for (final item in _clean)
            (
              item: item,
              withPicked:
                  neighbours.contains(item.id) && !selected.contains(item.id),
              score: _scoreOf(item, neighbours.contains(item.id)),
            ),
        ]..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          // Name last, so an unscored wardrobe is at least in a stable order
          // rather than whatever the database handed back.
          return byScore != 0
              ? byScore
              : a.item.displayName.compareTo(b.item.displayName);
        });

    return [
      for (final entry in scored)
        WornCandidate(item: entry.item, wornWithPicked: entry.withPicked),
    ];
  }

  double _scoreOf(WardrobeItem item, bool wornWithPicked) {
    // Deliberately far larger than the rest put together. Once one garment is
    // picked, what it is worn with is better evidence than every habit
    // statistic combined, and a ranking that merely nudged them up would leave
    // the user scrolling for a shirt the app already knew about.
    var score = wornWithPicked ? 1000.0 : 0.0;

    final usage = item.usage;

    if (usage.lastWornAt case final DateTime last) {
      // Decays over a fortnight. Something worn yesterday is a live candidate;
      // something worn six weeks ago is back to being an ordinary garment.
      final days = DateTime.now().difference(last).inDays;
      score += days <= 14 ? (14 - days) * 6.0 : 0.0;
    }

    // The domain's own "does this need washing" counter. Something on its
    // third wear is a likelier answer than something fresh from the drawer.
    score += usage.wearsSinceWash * 8.0;

    // Favourites come round again. Capped, so one much-worn garment does not
    // sit at the top of the list forever.
    score += (usage.timesWorn > 40 ? 40 : usage.timesWorn) * 0.5;

    return score;
  }

  /// Adds or removes a garment, and re-ranks around what is now picked.
  void toggle(ItemId id) {
    if (state.saving || state.isDone) return;

    final selected = {...state.selected};
    if (!selected.remove(id)) selected.add(id);

    state = WornTodayState(
      candidates: _rank(selected),
      selected: selected,
      saving: false,
    );
  }

  /// Records the wear and puts them in the basket.
  ///
  /// Both, because they are one event to the person doing it. Recording the
  /// wear without moving the garment leaves the wardrobe claiming a shirt is
  /// available to wear when it is in a heap; moving it without recording the
  /// wear loses the only evidence that it was worn at all, which is what cost
  /// per wear and every fading judgement rest on.
  Future<void> commit() async {
    if (state.saving || state.selected.isEmpty) return;
    final ids = state.selected.toList();

    state = WornTodayState(
      candidates: state.candidates,
      selected: state.selected,
      saving: true,
    );

    // The wear first. `recordOutfit` stamps them all with one instant, which
    // is what makes them a single occasion to the co-wear graph — the thing
    // that puts the right garments on screen next time.
    await _ref.read(wearRecorderProvider).recordOutfit(ids);
    await _ref
        .read(laundryControllerProvider)
        .move(ids, LifecycleState.inLaundry);

    if (!mounted) return;
    state = WornTodayState(candidates: const [], saved: ids.length);
  }
}

final wornTodayControllerProvider =
    StateNotifierProvider.autoDispose<WornTodayController, WornTodayState>(
      WornTodayController.new,
    );
