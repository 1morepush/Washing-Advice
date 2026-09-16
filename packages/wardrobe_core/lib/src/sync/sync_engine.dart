/// Reconciling a local wardrobe with a remote one.
///
/// ## Offline is the normal case, not the exception
///
/// Everything already works with no network: Drift holds the wardrobe, the
/// event log is local, and the sorter never calls anything. Sync is an
/// *addition* to a working offline app rather than the thing that makes it
/// work, which is why this runs when it can and never blocks a user.
///
/// ## Two kinds of data, two rules
///
/// **Events merge by union.** They are immutable, carry their own ids, and
/// describe things that happened. Two devices that each recorded a wash have
/// both recorded a real wash, and the union is the truth. Re-receiving an
/// event already held is a no-op — which is what makes a retry after a dropped
/// connection safe, and why the engine needs no delivery guarantees from the
/// transport.
///
/// **Items merge by provenance**, per `mergedWith`. They are mutable state and
/// two versions genuinely conflict.
///
/// ## Why counters are rebuilt rather than merged
///
/// `WardrobeItem.usage` is a projection of the event log, and once the union
/// of both logs is in hand the projection can simply be recomputed. That is
/// strictly better than the approximation `mergedWith` uses, and it is the
/// reason the events are pulled *before* the items are reconciled.
library;

import 'dart:math' as math;

import '../events/event_log.dart';
import '../events/projections.dart';
import '../events/wardrobe_event.dart';
import '../shared/clock.dart';
import '../shared/ids.dart';
import '../wardrobe/model/lifecycle.dart';
import '../wardrobe/model/wardrobe_item.dart';
import '../wardrobe/query.dart';
import '../wardrobe/repository.dart';
import 'merge.dart';

/// Everything one side holds, as of a point in time.
final class SyncPayload {
  const SyncPayload({
    this.items = const [],
    this.events = const [],
    this.serverTime,
  });

  final List<WardrobeItem> items;
  final List<WardrobeEvent> events;

  /// The remote's clock at the moment it gathered this, when it said.
  ///
  /// Only meaningful on a pull, and it is what the cursor has to be recorded
  /// as. The time the remote later *accepts a push* is too late: anything
  /// another device sent in between carries a stamp before it, and a cursor
  /// set there asks for everything after them — skipping them, silently and
  /// for good. See [SyncEngine.sync].
  final DateTime? serverTime;

  bool get isEmpty => items.isEmpty && events.isEmpty;

  int get length => items.length + events.length;

  /// This payload as consecutive pieces of at most [size] records each.
  ///
  /// Items first, then events, each in their existing order. The remote may
  /// receive the pieces in any order and lose any of them — events are a
  /// union and items merge — so a piece landing without the rest is never a
  /// broken state, only an incomplete one that the next run finishes.
  Iterable<SyncPayload> chunked(int size) sync* {
    assert(size > 0, 'a piece must hold something');
    var itemsFrom = 0;
    var eventsFrom = 0;
    while (itemsFrom < items.length || eventsFrom < events.length) {
      final itemsTo = math.min(items.length, itemsFrom + size);
      final room = size - (itemsTo - itemsFrom);
      final eventsTo = math.min(events.length, eventsFrom + room);
      yield SyncPayload(
        items: items.sublist(itemsFrom, itemsTo),
        events: events.sublist(eventsFrom, eventsTo),
      );
      itemsFrom = itemsTo;
      eventsFrom = eventsTo;
    }
  }

  @override
  String toString() =>
      'SyncPayload(${items.length} items, ${events.length} events)';
}

/// The other end of a sync.
///
/// An interface because the transport is genuinely replaceable — a hosted
/// backend, the project's own FastAPI service, a file on a shared drive — and
/// because everything above it can then be tested without any of them.
abstract interface class SyncRemote {
  /// Everything the remote has changed since [since].
  ///
  /// Null means "everything", which is what a fresh install asks for.
  Future<SyncPayload> pull({DateTime? since});

  /// Sends local changes. Returns the remote's time of acceptance.
  Future<DateTime> push(SyncPayload payload);
}

/// A failure that knows whether trying again could ever help.
///
/// Implemented by whatever a [SyncRemote] throws, so the engine can carry the
/// distinction out to the caller without the core having to know what a socket
/// or an HTTP status is. Without it every failure looks alike, and a server
/// that does not offer sync at all gets a "Try again" that will fail
/// identically forever.
abstract interface class RetryableFailure {
  /// Whether trying again later is worth the user's time.
  bool get isRetryable;
}

/// What one sync run did.
final class SyncReport {
  const SyncReport({
    required this.pulled,
    required this.pushed,
    required this.merged,
    required this.at,
    this.failure,
    this.isRetryable = true,
  });

  const SyncReport.failed(
    this.failure, {
    required this.at,
    this.isRetryable = true,
  })  : pulled = 0,
        pushed = 0,
        merged = const {};

  final int pulled;
  final int pushed;

  /// Items that existed on both sides and had to be reconciled, with the
  /// per-field decisions that settled them.
  ///
  /// Reported rather than logged: a sync that silently changes a garment's
  /// fabric is one nobody should trust with their only copy.
  final Map<ItemId, Map<String, MergeOutcome>> merged;

  final DateTime at;

  /// Why the run failed, if it did.
  ///
  /// A failure is a *result*, not an exception to propagate. The network being
  /// down is the expected case for an offline-first app, and a caller should
  /// not have to wrap every sync in a try/catch to handle the ordinary.
  final String? failure;

  /// Whether [failure] is worth retrying.
  ///
  /// Defaults to true because the ordinary failure is a dropped connection.
  /// A rejected token or a server with no sync endpoint sets it false, so the
  /// screen can stop offering an action that cannot work.
  final bool isRetryable;

  bool get succeeded => failure == null;

  bool get hadConflicts => merged.values.any((d) => d.isNotEmpty);

  @override
  String toString() => succeeded
      ? 'SyncReport(+$pulled/-$pushed, ${merged.length} reconciled)'
      : 'SyncReport(failed: $failure)';
}

/// Where the last successful sync got to.
abstract interface class SyncCursor {
  /// The remote's clock, as of the last successful run. Used to ask the remote
  /// what has changed.
  Future<DateTime?> lastSyncedAt();

  /// This device's own clock, as of the last successful push. Used to decide
  /// what to send.
  ///
  /// Two cursors rather than one, and the distinction is not pedantry. The
  /// remote's timestamps and this device's are different clocks, and comparing
  /// across them loses data: a device running a few minutes behind the server
  /// stamps its edits *earlier* than the cursor it was just handed, so those
  /// edits are never selected and never sent. Nothing reports an error —
  /// the changes simply stay on one phone forever.
  ///
  /// Keeping each comparison inside one clock domain removes the whole class
  /// of problem, and costs one extra stored timestamp.
  Future<DateTime?> lastPushedAt();

  /// Records both: [at] from the remote, [localAt] from this device's clock.
  Future<void> record(DateTime at, {DateTime? localAt});
}

/// An in-memory cursor, for tests and for a first run.
final class InMemorySyncCursor implements SyncCursor {
  DateTime? _at;
  DateTime? _localAt;

  @override
  Future<DateTime?> lastSyncedAt() async => _at;

  @override
  Future<DateTime?> lastPushedAt() async => _localAt;

  @override
  Future<void> record(DateTime at, {DateTime? localAt}) async {
    _at = at;
    if (localAt != null) _localAt = localAt;
  }
}

class SyncEngine {
  const SyncEngine({
    required this.items,
    required this.events,
    required this.remote,
    required this.cursor,
    this.clock = const SystemClock(),
    this.pushBatchSize = defaultPushBatchSize,
  });

  /// The most records offered to the remote in one request.
  ///
  /// The project's server refuses a request over 2,000 records, and the first
  /// sync of a wardrobe that has been in use for a while — a few hundred
  /// garments, each worn and washed many times over — is well past that. Sent
  /// as one request it failed on every attempt, with nothing advancing the
  /// cursor, and the device could never sync at all. Comfortably under the
  /// ceiling, so a server configured a little tighter still accepts a piece.
  static const defaultPushBatchSize = 500;

  final WardrobeRepository items;
  final EventLog events;
  final SyncRemote remote;
  final SyncCursor cursor;
  final Clock clock;
  final int pushBatchSize;

  /// Runs one reconciliation.
  ///
  /// Pull before push, so anything the remote knows is folded in before local
  /// state is offered back. The alternative — pushing first — would send a
  /// version of an item that has not yet seen the remote's changes, and the
  /// remote would then have to merge, which puts the merge rule in two places.
  Future<SyncReport> sync() async {
    final since = await cursor.lastSyncedAt();
    final pushedSince = await cursor.lastPushedAt();
    // Read *before* anything is gathered, so a change written while this run is
    // in flight is newer than the mark and is caught by the next run rather
    // than skipped by it.
    final startedAt = clock.now();

    final SyncPayload incoming;
    try {
      incoming = await remote.pull(since: since);
    } on Exception catch (error) {
      return SyncReport.failed(
        '$error',
        at: clock.now(),
        isRetryable: _isRetryable(error),
      );
    }

    // Events first. They are the source of truth for the counters, so folding
    // them in before reconciling items means the merge works from complete
    // history rather than from two partial views of it.
    await events.appendAll(incoming.events);

    final decisions = <ItemId, Map<String, MergeOutcome>>{};
    final touched = <ItemId>{};

    for (final remoteItem in incoming.items) {
      final local = await items.byId(remoteItem.id);
      touched.add(remoteItem.id);

      if (local == null) {
        await items.save(remoteItem);
        decisions[remoteItem.id] = const {};
        continue;
      }

      final result = local.mergedWith(remoteItem);
      var merged = result.item;
      if (merged.lifecycle == LifecycleState.removed &&
          (local.lifecycle != LifecycleState.removed ||
              remoteItem.lifecycle != LifecycleState.removed)) {
        // A deletion just won against a side that had not seen it. The
        // remote keeps one row per item — whichever was pushed last — so if
        // an edit was pushed after the tombstone, the remote's row is the
        // edit and a fresh install would pull the garment back. Re-stamping
        // puts the tombstone in this run's push, where it overwrites that
        // row. Once both sides hold the tombstone nothing here fires again.
        merged = merged.copyWith(updatedAt: clock.now());
      }
      await items.save(merged);
      decisions[remoteItem.id] = result.decisions;
    }

    // Rebuild the counters for everything the incoming events touched, which
    // replaces `mergedWith`'s larger-of-two approximation with the real figure
    // derived from the union of both logs.
    for (final id in {for (final event in incoming.events) event.itemId}) {
      await _rebuildUsage(id);
      touched.add(id);
    }

    final outgoing = await _localChangesSince(pushedSince);

    final DateTime acceptedAt;
    try {
      acceptedAt = await _push(outgoing);
    } on Exception catch (error) {
      // The pull already applied. Not recording the cursor means the next run
      // re-pulls the same events, which is harmless because appending an event
      // already held is a no-op — and far better than recording a cursor for a
      // push that never landed. A push that landed in part is the same case:
      // what reached the remote is offered again next time, at no cost.
      return SyncReport.failed(
        '$error',
        at: clock.now(),
        isRetryable: _isRetryable(error),
      );
    }

    // The remote cursor is the remote's clock at the *pull*, not at the push.
    // Between the two, another device may have pushed. Its records carry a
    // stamp earlier than this push's acceptance, so a cursor set at the
    // acceptance would ask for everything after them and never see them —
    // silently, and for good. A remote that does not say its time gets the
    // acceptance instead, which is at least never wrong for a single device.
    await cursor.record(incoming.serverTime ?? acceptedAt, localAt: startedAt);

    return SyncReport(
      pulled: incoming.length,
      pushed: outgoing.length,
      merged: decisions,
      at: acceptedAt,
    );
  }

  /// Offers [outgoing] to the remote, in pieces it will accept.
  ///
  /// An empty payload is still sent once: the remote's time of acceptance is
  /// the fallback cursor, and a run that had nothing to send still needs one.
  Future<DateTime> _push(SyncPayload outgoing) async {
    if (outgoing.length <= pushBatchSize) return remote.push(outgoing);

    late DateTime acceptedAt;
    for (final piece in outgoing.chunked(pushBatchSize)) {
      acceptedAt = await remote.push(piece);
    }
    return acceptedAt;
  }

  /// Recomputes an item's counters from the whole log.
  Future<void> _rebuildUsage(ItemId id) async {
    final item = await items.byId(id);
    if (item == null) return;

    final rebuilt = UsageProjection.forItem(id, await events.forItem(id));
    if (rebuilt == item.usage) return;
    await items.save(item.copyWith(usage: rebuilt));
  }

  /// Local state the remote has not seen.
  ///
  /// Selected by `updatedAt` rather than by a dirty flag, because a flag is a
  /// second source of truth that can disagree with the data — and after a
  /// crash mid-write, it will.
  /// What this device has changed since it last pushed.
  ///
  /// Both comparisons are against *this device's* clock — `updatedAt` and
  /// `recordedAt` are both stamped locally — which is the point of tracking a
  /// separate local mark. Events are selected by when they were recorded, not
  /// by when they happened, so a wear logged today for last week is still sent.
  ///
  /// Inclusive on both, for the same reason the server's `since` is: sending a
  /// record the remote already has is free, and missing one is not.
  Future<SyncPayload> _localChangesSince(DateTime? since) async {
    // Tombstones included. Every other query hides a deleted garment; this
    // is the one place that must see it, because the deletion is the change
    // most worth telling the other devices about.
    final all = await items.query(const WardrobeQuery(includeRemoved: true));
    return SyncPayload(
      items: [
        for (final item in all)
          if (since == null || !item.updatedAt.isBefore(since)) item,
      ],
      events: await events.all(recordedSince: since),
    );
  }
}

/// Whether a failure from the remote is worth retrying.
///
/// Anything that does not declare itself is assumed retryable, because the
/// failure this engine sees most is a dropped connection and refusing to retry
/// that would strand a device that is merely briefly offline.
bool _isRetryable(Object error) =>
    error is! RetryableFailure || error.isRetryable;
