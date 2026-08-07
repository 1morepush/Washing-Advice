/// One sync run.
///
/// Every test here uses a fake remote, which is the whole point of `SyncRemote`
/// being an interface: the reconciliation rules are worth testing exhaustively,
/// and none of them are about HTTP.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final monday = DateTime.utc(2026, 8, 3);
  final tuesday = DateTime.utc(2026, 8, 4);

  late InMemoryWardrobeRepository items;
  late InMemoryEventLog events;
  late _FakeRemote remote;
  late InMemorySyncCursor cursor;
  late SyncEngine engine;

  setUp(() {
    items = InMemoryWardrobeRepository();
    events = InMemoryEventLog();
    remote = _FakeRemote();
    cursor = InMemorySyncCursor();
    engine = SyncEngine(
      items: items,
      events: events,
      remote: remote,
      cursor: cursor,
      clock: FixedClock(tuesday),
    );
  });

  group('pulling', () {
    test('an item the device has never seen is adopted', () {
      remote.available = SyncPayload(items: [_jumper(updatedAt: monday)]);

      return engine.sync().then((report) async {
        expect(report.succeeded, isTrue);
        expect(await items.byId(const ItemId('jumper')), isNotNull);
        // Nothing to reconcile: there was no local version to conflict with.
        expect(report.hadConflicts, isFalse);
      });
    });

    test('an item held on both sides is merged, not overwritten', () async {
      await items.save(
        _jumper(
          updatedAt: monday,
          composition: Confident(
            FabricComposition(const {Fiber.wool: 80, Fiber.nylon: 20}),
            confidence: 0.95,
            source: Provenance.tagScan,
          ),
        ),
      );
      remote.available = SyncPayload(items: [_jumper(updatedAt: tuesday)]);

      final report = await engine.sync();

      // The local label reading outranks the remote's later photo guess, which
      // is the behaviour a plain overwrite would destroy.
      final stored = (await items.byId(const ItemId('jumper')))!;
      expect(stored.composition.source, Provenance.tagScan);
      expect(report.merged[const ItemId('jumper')], isNotEmpty);
      expect(report.hadConflicts, isTrue);
    });

    test('remote events are folded into the log', () async {
      await items.save(_jumper(updatedAt: monday));
      remote.available = SyncPayload(
        events: [_worn('e1', monday), _worn('e2', tuesday)],
      );

      await engine.sync();
      expect(await events.all(), hasLength(2));
    });
  });

  group('counters', () {
    test('are rebuilt from the union of both logs, not approximated', () async {
      // `mergedWith` takes the larger of two counts because it has nothing
      // better. Once the events themselves arrive there *is* something better,
      // and using it is the reason events are pulled before items reconcile.
      await items.save(_jumper(updatedAt: monday));
      await events.append(_worn('local-1', monday));

      remote.available = SyncPayload(
        events: [_worn('remote-1', monday), _worn('remote-2', tuesday)],
      );

      await engine.sync();

      // Three distinct wears happened across two devices; neither device's
      // count alone is right, and taking the larger would give 2.
      expect((await items.byId(const ItemId('jumper')))!.usage.timesWorn, 3);
    });

    test('an event already held is not counted twice', () async {
      // What makes a retry after a dropped connection safe. Without it, every
      // failed sync would inflate the wear count on the next attempt.
      await items.save(_jumper(updatedAt: monday));
      await events.append(_worn('shared', monday));

      remote.available = SyncPayload(events: [_worn('shared', monday)]);

      await engine.sync();
      expect((await items.byId(const ItemId('jumper')))!.usage.timesWorn, 1);
    });
  });

  group('pushing', () {
    test('local changes are offered to the remote', () async {
      await items.save(_jumper(updatedAt: monday));
      await events.append(_worn('e1', monday));

      final report = await engine.sync();

      expect(report.pushed, 2);
      expect(remote.received.single.items, hasLength(1));
      expect(remote.received.single.events, hasLength(1));
    });

    test('only what has changed since the last run', () async {
      await items.save(_jumper(updatedAt: monday));
      await engine.sync();
      remote.received.clear();

      await engine.sync();
      expect(remote.received.single.items, isEmpty);
    });
  });

  group('failure', () {
    test('a pull failure is a result, not an exception', () async {
      // The network being down is the expected case for an offline-first app.
      // A caller should not have to wrap every sync in a try/catch.
      remote.failPull = true;

      final report = await engine.sync();
      expect(report.succeeded, isFalse);
      expect(report.failure, isNotNull);
    });

    test('a failed push does not advance the cursor', () async {
      // Otherwise the next run would skip changes that never landed, and the
      // two sides would stay silently divergent.
      await items.save(_jumper(updatedAt: monday));
      remote.failPush = true;

      await engine.sync();
      expect(await cursor.lastSyncedAt(), isNull);
    });

    test('an ordinary failure is reported as worth retrying', () async {
      // A dropped connection is the failure this engine sees most, and a
      // device that is briefly offline must not be told to give up.
      remote.failPull = true;

      final report = await engine.sync();

      expect(report.succeeded, isFalse);
      expect(report.isRetryable, isTrue);
    });

    test('a failure that says not to retry is carried out intact', () async {
      // A server with no sync endpoint, or a rejected token, will fail
      // identically forever. The flag is set carefully at the transport and
      // used to decide whether a screen offers "Try again" — so losing it
      // here would put a button on screen that cannot ever work.
      remote.failPullWith = const _NotOffered();

      final report = await engine.sync();

      expect(report.succeeded, isFalse);
      expect(report.isRetryable, isFalse);
      expect(report.failure, contains('does not offer sync'));
    });

    test('a pull that already applied is kept when the push fails', () async {
      // Re-pulling costs nothing — appending a held event is a no-op — and
      // discarding work that succeeded to punish a later failure would be
      // worse than keeping it.
      remote
        ..available = SyncPayload(items: [_jumper(updatedAt: monday)])
        ..failPush = true;

      await engine.sync();
      expect(await items.byId(const ItemId('jumper')), isNotNull);
    });
  });

  group('what gets selected to send', () {
    // Both of these were found by running the engine against the real server
    // rather than against a fake, and both were silent: no error, no report,
    // just changes that stayed on one device forever.

    test('a wear logged today for last week is still sent', () async {
      // Events are selected by when they were *recorded*, not by when they
      // happened. Selecting by `occurredAt` strands every retrospective entry,
      // which is a feature the event model explicitly supports.
      await items.save(_jumper(updatedAt: monday));
      await engine.sync();
      remote.received.clear();

      final lastMonth = DateTime.utc(2026, 7, 1);
      await events.append(
        ItemWorn(
          id: const EventId('retro'),
          itemId: const ItemId('jumper'),
          occurredAt: lastMonth,
          recordedAt: tuesday.add(const Duration(hours: 1)),
        ),
      );

      await engine.sync();
      expect(remote.received.single.events, hasLength(1));
    });

    test('an edit on a device whose clock trails the server is still sent',
        () async {
      // The cursor the remote hands back is in the remote's clock. Comparing a
      // locally stamped `updatedAt` against it means a device running a few
      // minutes slow never selects its own edits.
      await items.save(_jumper(updatedAt: monday));
      await engine.sync();
      remote.received.clear();

      // The remote accepted at a time well ahead of this device's clock.
      remote.acceptAt = DateTime.utc(2026, 8, 4, 12);
      await engine.sync();
      remote.received.clear();

      // A local edit stamped by the trailing local clock.
      await items.save(_jumper(updatedAt: tuesday, name: 'Renamed'));

      await engine.sync();
      expect(remote.received.single.items, hasLength(1));
    });
  });

  test('syncing twice changes nothing the second time', () async {
    // Idempotence at the level of a whole run: a device that reconnects
    // repeatedly must not drift.
    await items.save(_jumper(updatedAt: monday));
    remote.available = SyncPayload(
      items: [_jumper(updatedAt: tuesday, name: 'Renamed')],
      events: [_worn('e1', monday)],
    );

    await engine.sync();
    final afterFirst = (await items.byId(const ItemId('jumper')))!.toJson();

    await engine.sync();
    expect((await items.byId(const ItemId('jumper')))!.toJson(), afterFirst);
  });
}

// --- Fixtures ---------------------------------------------------------------

WardrobeItem _jumper({
  required DateTime updatedAt,
  String name = 'Wool jumper',
  Confident<FabricComposition>? composition,
}) =>
    WardrobeItem(
      id: const ItemId('jumper'),
      name: name,
      type: Confident(
        ItemType.sweater,
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      composition: composition ??
          Confident(
            FabricComposition(const {Fiber.wool: 100}),
            confidence: 0.6,
            source: Provenance.aiInference,
          ),
      colors: Confident(
        ColorPalette.empty(),
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      care: const CareProfile.unknown(),
      addedAt: DateTime.utc(2026, 8, 3),
      updatedAt: updatedAt,
    );

ItemWorn _worn(String id, DateTime at) =>
    ItemWorn(id: EventId(id), itemId: const ItemId('jumper'), occurredAt: at);

class _FakeRemote implements SyncRemote {
  SyncPayload available = const SyncPayload();
  final List<SyncPayload> received = [];

  /// The remote's clock, which is deliberately not the device's.
  DateTime acceptAt = DateTime.utc(2026, 8, 4);

  bool failPull = false;
  bool failPush = false;

  /// A specific failure to throw from `pull`, for cases where *which* failure
  /// it is changes the outcome rather than merely that one happened.
  Exception? failPullWith;

  @override
  Future<SyncPayload> pull({DateTime? since}) async {
    if (failPullWith case final failure?) throw failure;
    if (failPull) throw const _Offline();
    return available;
  }

  @override
  Future<DateTime> push(SyncPayload payload) async {
    if (failPush) throw const _Offline();
    received.add(payload);
    return acceptAt;
  }
}

class _Offline implements Exception {
  const _Offline();

  @override
  String toString() => 'the network is unavailable';
}

/// Stands in for what the HTTP remote throws on a 404 from `/v1/sync`.
class _NotOffered implements Exception, RetryableFailure {
  const _NotOffered();

  @override
  bool get isRetryable => false;

  @override
  String toString() => 'This server does not offer sync.';
}
