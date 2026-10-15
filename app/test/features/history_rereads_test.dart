/// How often the event log is read back after something is written to it.
///
/// The co-wear graph is a fold over the log, so anything watching it rereads
/// the log whenever it is invalidated. It used to be invalidated once per
/// event appended, which meant a load of twenty garments, or an outfit of five,
/// read the whole history twenty or five times to learn the same thing once.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/features/history/wear_recorder.dart';
import 'package:washing_advice/features/laundry/laundry_controller.dart';

import '../support/fixtures.dart';

/// An event log that remembers how it was read.
class _CountingEventLog implements EventLog {
  final InMemoryEventLog _inner = InMemoryEventLog();

  /// The `types` of each `all()` call, in order.
  final List<Set<String>?> reads = [];

  @override
  Future<List<WardrobeEvent>> all({
    DateTime? since,
    DateTime? until,
    DateTime? recordedSince,
    Set<String>? types,
  }) {
    reads.add(types);
    return _inner.all(
      since: since,
      until: until,
      recordedSince: recordedSince,
      types: types,
    );
  }

  /// A turn of the event loop, as a real database takes. Without it the whole
  /// write runs inside one microtask burst and any rebuild is coalesced for
  /// free, which hides exactly the per-event rereads being tested for.
  Future<void> _io() => Future<void>.delayed(Duration.zero);

  @override
  Future<void> append(WardrobeEvent event) async {
    await _io();
    await _inner.append(event);
  }

  @override
  Future<void> appendAll(Iterable<WardrobeEvent> events) =>
      _inner.appendAll(events);

  @override
  Future<List<WardrobeEvent>> forItem(ItemId itemId) => _inner.forItem(itemId);
}

void main() {
  late InMemoryWardrobeRepository repository;
  late _CountingEventLog log;
  late ProviderContainer container;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    log = _CountingEventLog();
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(log),
        washerBrandProvider.overrideWith((ref) => null),
        dryerBrandProvider.overrideWith((ref) => null),
        customWasherProvider.overrideWith((ref) => null),
        customDryerProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(container.dispose);

    // Something on screen that depends on the graph, as the stylist does.
    // Without a watcher an invalidated provider is simply dropped and never
    // rereads anything, which would make every count here zero.
    container.listen(outfitBuilderProvider, (_, _) {});
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<List<ItemId>> garments(int count, {required LifecycleState to}) async {
    final ids = <ItemId>[];
    for (var i = 0; i < count; i++) {
      final item = confidentItem(id: 'g$i', name: 'Tee $i');
      await repository.save(item);
      ids.add(item.id);
    }
    await container.read(laundryControllerProvider).move(ids, to);
    return ids;
  }

  test('an outfit of five rereads the log once, not five times', () async {
    final ids = await garments(5, to: LifecycleState.active);
    await container.read(coWearGraphProvider.future);
    log.reads.clear();

    await container.read(wearRecorderProvider).recordOutfit(ids);
    await settle();
    await container.read(coWearGraphProvider.future);

    expect(log.reads, hasLength(1));
  });

  test('starting a load of five does not reread the log per garment', () async {
    await garments(5, to: LifecycleState.inLaundry);
    await container.read(ownedItemsProvider.future);
    final load = container.read(laundryPlanProvider).valueOrNull!.loads.first;
    expect(load.items, hasLength(5));
    await container.read(coWearGraphProvider.future);
    log.reads.clear();

    await container.read(laundryControllerProvider).start(load);
    await settle();
    await container.read(coWearGraphProvider.future);

    // A wash is not a wear, so the graph has nothing new to learn from it:
    // the right number is none, and the bound is one for the action.
    expect(log.reads.length, lessThanOrEqualTo(1));
  });

  test('only wears are read for the graph', () async {
    await container.read(coWearGraphProvider.future);
    await container.read(wearRecorderProvider).recordOutfit([
      (await garments(2, to: LifecycleState.active)).first,
    ]);
    await settle();
    await container.read(coWearGraphProvider.future);

    expect(log.reads, isNotEmpty);
    expect(log.reads, everyElement({wornEventType}));
  });
}
