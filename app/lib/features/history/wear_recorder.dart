/// Writing to the event log.
///
/// Until now the app had an append-only log, a `WardrobeRecorder`, and a
/// `UsageProjection` — and nothing that ever wrote an event. Every feature
/// resting on wear was therefore inert: cost per wear had no divisor,
/// "never worn" matched everything, "recently worn" sorted nothing, and
/// `isLikelyToBleed` treated every red shirt as brand new forever because
/// `timesWashed` never left zero.
///
/// This is the other half of that design. The log is the truth and the
/// counters on an item are a cache of it, so both writes happen together —
/// which is exactly what `WardrobeRecorder.record` exists to guarantee.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';

class WearRecorder {
  const WearRecorder(this._ref);

  final Ref _ref;

  /// Records that [id] was worn.
  ///
  /// [at] defaults to now but is a parameter because `WardrobeEvent` has
  /// carried `occurredAt` from the start for exactly this reason — people log
  /// yesterday evening's outfit this morning. Hardcoding the clock here made
  /// that impossible and, worse, made every batch of taps look like one
  /// occasion to anything reading the log.
  Future<void> recordWear(ItemId id, {String? occasion, DateTime? at}) async {
    await _record(
      ItemWorn(
        id: EventId(_ref.read(idGeneratorProvider).next()),
        itemId: id,
        occurredAt: at ?? DateTime.now(),
        // Always now, even when the wear itself is backdated. This is what
        // sync selects on, and stamping it with the backdated time would put
        // the event behind the push cursor and strand it on this device.
        recordedAt: DateTime.now(),
        occasion: occasion,
      ),
    );
    _ref.invalidate(itemProvider(id));
  }

  /// Records that several items were worn together.
  ///
  /// Every event gets the *same* instant rather than each getting its own
  /// `now`, which is what makes them one occasion to anything reading the log.
  /// Recording them one at a time would still land inside the co-wear window
  /// today, but it would rely on the loop finishing quickly — a correctness
  /// property resting on how fast a for-loop runs is not one worth having.
  Future<void> recordOutfit(
    Iterable<ItemId> ids, {
    String? occasion,
    DateTime? at,
  }) async {
    final instant = at ?? DateTime.now();
    for (final id in ids) {
      await recordWear(id, occasion: occasion, at: instant);
    }
  }

  /// Records that every item in [load] was washed, with the settings used.
  ///
  /// One event per item rather than one per load, because the log is keyed by
  /// item: that is what lets a single garment's history be replayed, and what
  /// makes "how many times have I washed this?" answerable without knowing
  /// which loads it happened to be in.
  ///
  /// The machine's *name* is stored beside its id so the history survives the
  /// user replacing or deleting a machine profile — a wash that happened is a
  /// fact, and it should not become unreadable because they bought a new
  /// washer.
  Future<void> recordWash(LaundryLoad load) async {
    final ids = _ref.read(idGeneratorProvider);
    final washer = _ref.read(washerProvider);
    final dryer = _ref.read(dryerProvider);
    final now = DateTime.now();

    final record = LaundryRecord(
      washedAt: now,
      washerName: washer?.displayName,
      programName: load.washerSetting?.programName,
      temperatureC: load.washerSetting?.temperatureC,
      spinRpm: load.washerSetting?.spinRpm,
      dryerName: dryer?.displayName,
      dryProgramName: load.dryerSetting?.programName,
      loadId: load.id,
      // The user is following a plan the app produced. Recording that lets a
      // later version ask whether its advice actually gets taken, which is the
      // only honest way to find out if it is any good.
      followedRecommendation: true,
    );

    for (final item in load.items) {
      await _record(
        ItemWashed(
          id: EventId(ids.next()),
          itemId: item.id,
          occurredAt: now,
          recordedAt: now,
          record: record,
        ),
      );
      _ref.invalidate(itemProvider(item.id));
    }
  }

  /// Appends an event and refreshes the affected item's cached counters.
  ///
  /// Silently does nothing for an item that is not in the wardrobe, which is
  /// the case for a pile-scan draft: the garment was washed, but there is no
  /// row to update and no history worth keeping for something the app has
  /// never been told about.
  ///
  /// Also drops the co-wear graph, which is a fold over the whole log and so
  /// is stale the moment anything is appended. Invalidated here rather than in
  /// each caller: every write goes through this method, and a derived value
  /// that some writes refresh and others do not is worse than one that is
  /// never refreshed at all.
  Future<void> _record(WardrobeEvent event) async {
    await _ref.read(wardrobeRecorderProvider).record(event);
    _ref.invalidate(coWearGraphProvider);
  }
}

final wearRecorderProvider = Provider<WearRecorder>(WearRecorder.new);
