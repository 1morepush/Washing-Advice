/// Where each garment is between the basket and the wardrobe.
///
/// The sorting engine has existed since the pile scan, and is complete: give
/// `LaundrySorter` a list of items and it returns the loads, their settings and
/// the reason behind each choice. What it never had was a *pile* — the scan
/// photographs a heap, plans it, and throws the plan away. Nothing in the app
/// knew that the shirt you took off last night was dirty.
///
/// So this holds no laundry logic of its own. It is the plumbing between an
/// item's [LifecycleState] and the sorter that was already there.
///
/// Loads are deliberately **not** stored. "What is in the washer" is simply the
/// set of items in [LifecycleState.beingWashed], and the grouping is re-derived
/// whenever it is needed. That avoids a whole table and a second source of
/// truth; the one thing it cannot express is two loads running at once, which
/// is worth revisiting only if it turns out to bite.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../history/wear_recorder.dart';

/// The items in one stage of the wash.
///
/// Derived from [ownedItemsProvider] rather than querying per stage, so the
/// four piles and the wardrobe cannot disagree about what exists, and a move
/// refreshes all of them at once.
final pileProvider =
    Provider.family<AsyncValue<List<WardrobeItem>>, LifecycleState>(
      (ref, stage) => ref
          .watch(ownedItemsProvider)
          .whenData(
            (items) => [
              for (final item in items)
                if (item.lifecycle == stage) item,
            ],
          ),
    );

/// What to run, for whatever is in the basket right now.
///
/// The same `sort` call the pile scan makes, so a plan cannot depend on how the
/// clothes were put in front of it. Only items in the basket are offered:
/// something already turning in the drum is being washed, not waiting to be,
/// and `isLaunderable` says so.
final laundryPlanProvider = Provider<AsyncValue<LaundryPlan>>(
  (ref) => ref
      .watch(pileProvider(LifecycleState.inLaundry))
      .whenData(
        (dirty) => ref
            .watch(laundrySorterProvider)
            .sort(
              dirty,
              washer: ref.watch(washerProvider),
              dryer: ref.watch(dryerProvider),
            ),
      ),
);

/// Moves garments between the wardrobe, the basket and the machine.
class LaundryController {
  const LaundryController(this._ref);

  final Ref _ref;

  /// Moves every item in [ids] to [stage].
  ///
  /// Goes through [WardrobeItem.transitionTo], which refuses moves that make no
  /// sense — nothing here should be able to drag a discarded garment back into
  /// the wash — and records a [LifecycleChanged] event so the move is in the
  /// history rather than only in the row.
  ///
  /// An item that has been deleted, or that refuses the move, is skipped rather
  /// than aborting the rest: a bulk move of twelve things should not fail
  /// wholesale because one of them was retired on another device.
  Future<void> move(Iterable<ItemId> ids, LifecycleState stage) async {
    final repository = _ref.read(wardrobeRepositoryProvider);
    final log = _ref.read(eventLogProvider);
    final generator = _ref.read(idGeneratorProvider);
    final now = DateTime.now();

    for (final id in ids) {
      final item = await repository.byId(id);
      final moved = item?.transitionTo(stage, at: now);
      if (moved == null) continue;

      await repository.save(moved);
      await log.append(
        LifecycleChanged(
          id: EventId(generator.next()),
          itemId: id,
          occurredAt: now,
          recordedAt: now,
          to: stage,
        ),
      );
      _ref.invalidate(itemProvider(id));
    }
  }

  /// Records [load] as washed and moves its garments into the machine.
  ///
  /// The wash is recorded **here**, at the start, rather than when the clothes
  /// come out. Once a load is running the grouping is gone — the machine
  /// contains a set of items in [LifecycleState.beingWashed] and nothing says
  /// which load they were — so this is the last moment the settings are known.
  /// Recording later would mean re-deriving them and hoping they matched, and
  /// a `LaundryRecord` that says a garment was washed at a temperature it was
  /// not is worse than no record at all.
  ///
  /// Both halves, always. Recording without moving leaves the clothes in the
  /// basket the app thinks it just washed; moving without recording loses the
  /// only evidence a wash happened, which is what "times washed" and every
  /// later fading and shrinkage judgement rest on.
  Future<void> start(LaundryLoad load) async {
    await _ref.read(wearRecorderProvider).recordWash(load);
    await move([
      for (final item in load.items) item.id,
    ], LifecycleState.beingWashed);
  }
}

final laundryControllerProvider = Provider<LaundryController>(
  LaundryController.new,
);
