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

  bool failPull = false;
  bool failPush = false;

  @override
  Future<SyncPayload> pull({DateTime? since}) async {
    if (failPull) throw const _Offline();
    return available;
  }

  @override
  Future<DateTime> push(SyncPayload payload) async {
    if (failPush) throw const _Offline();
    received.add(payload);
    return DateTime.utc(2026, 8, 4);
  }
}

class _Offline implements Exception {
  const _Offline();

  @override
  String toString() => 'the network is unavailable';
}
