/// Writing to the event log.
///
/// The property under test is the one the whole event-sourcing design rests
/// on: the log is the truth and the counters on an item are a cache of it, so
/// after any write the two must agree. A test that only checked the counter
/// would pass against an implementation that never wrote an event — and the
/// history, which is the part that cannot be recomputed, would be silently
/// empty.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/features/history/wear_recorder.dart';

void main() {
  const id = ItemId('hoodie');

  late InMemoryWardrobeRepository repository;
  late InMemoryEventLog events;
  late ProviderContainer container;

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    events = InMemoryEventLog();
    await repository.save(_hoodie());

    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(events),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'ev'),
        ),
        washerBrandProvider.overrideWith((ref) => 'Bosch'),
        dryerBrandProvider.overrideWith((ref) => null),
        // washerProvider/dryerProvider also read these now, and there is no
        // settingsStoreProvider override here for them to fall back to.
        customWasherProvider.overrideWith((ref) => null),
        customDryerProvider.overrideWith((ref) => null),
      ],
    );
  });

  tearDown(() => container.dispose());

  WearRecorder recorder() => container.read(wearRecorderProvider);

  Future<WardrobeItem> stored() async => (await repository.byId(id))!;

  group('wearing', () {
    test('appends an event and refreshes the counters together', () async {
      await recorder().recordWear(id);

      expect(await events.all(), hasLength(1));
      expect((await events.all()).single, isA<ItemWorn>());
      expect((await stored()).usage.timesWorn, 1);
      expect((await stored()).usage.lastWornAt, isNotNull);
    });

    test('counts each wear', () async {
      await recorder().recordWear(id);
      await recorder().recordWear(id);
      await recorder().recordWear(id);

      expect((await stored()).usage.timesWorn, 3);
      expect((await stored()).usage.wearsSinceWash, 3);
    });

    test('makes cost per wear computable', () async {
      // Dead until now: the divisor was always zero, so the headline wardrobe
      // statistic could never be shown for anything.
      await repository.save(
        (await stored()).copyWith(
          purchase: PurchaseInfo(
            priceMinorUnits: 6000,
            currencyCode: 'EUR',
            purchasedAt: DateTime.utc(2025, 1, 1),
          ),
        ),
      );

      expect((await stored()).costPerWear, isNull);
      await recorder().recordWear(id);
      await recorder().recordWear(id);

      expect((await stored()).costPerWear, 30.0);
    });
  });

  group('washing', () {
    LaundryLoad load(List<WardrobeItem> items) => LaundryLoad(
      id: const LoadId('load-1'),
      items: items,
      effectiveCare: const CareInstructions.conservative(),
      washSpec: const WashSpec(
        method: WashMethod.machine,
        agitation: Agitation.normal,
        fabricClass: FabricClass.normal,
      ),
      drySpec: const DrySpec(
        tumbleDryAllowed: false,
        maxHeat: TumbleDryHeat.noHeat,
        fabricClass: FabricClass.normal,
      ),
      label: 'Darks',
      totalWeightKg: 1.2,
      washerSetting: const WasherSetting(
        programName: 'Easy-Care',
        temperatureC: 30,
        spinRpm: 1200,
      ),
    );

    test('records one event per item, not one per load', () async {
      // The log is keyed by item. One event per load would make "how many
      // times have I washed this?" unanswerable without knowing every load the
      // garment was ever in.
      await repository.save(_tee());
      await recorder().recordWash(load([await stored(), _tee()]));

      final washes = (await events.all()).whereType<ItemWashed>();
      expect(washes, hasLength(2));
      expect(washes.map((e) => e.itemId.value), containsAll(['hoodie', 'tee']));
    });

    test('resets wears-since-wash and counts the wash', () async {
      await recorder().recordWear(id);
      await recorder().recordWear(id);
      await recorder().recordWash(load([await stored()]));

      final after = await stored();
      expect(after.usage.timesWashed, 1);
      expect(after.usage.wearsSinceWash, 0);
      // The wear history survives the wash: they are different counters
      // answering different questions.
      expect(after.usage.timesWorn, 2);
    });

    test('keeps the settings that were actually used', () async {
      await recorder().recordWash(load([await stored()]));

      final washed = (await events.all()).whereType<ItemWashed>().single;
      expect(washed.record.programName, 'Easy-Care');
      expect(washed.record.temperatureC, 30);
      expect(washed.record.spinRpm, 1200);
      expect(washed.record.followedRecommendation, isTrue);
    });

    test("stores the machine's name, not only its id", () async {
      // So the history stays readable after the user replaces or deletes a
      // machine profile. A wash that happened is a fact.
      await recorder().recordWash(load([await stored()]));

      final washed = (await events.all()).whereType<ItemWashed>().single;
      expect(washed.record.washerName, isNotEmpty);
    });

    test('a garment not in the wardrobe is skipped, not an error', () async {
      // Pile scans produce drafts for garments the app has never met. They can
      // be in a load without being in the wardrobe, and washing one must not
      // fail the whole recording.
      await recorder().recordWash(load([_draft()]));

      expect(await repository.byId(const ItemId('draft')), isNull);
      expect((await events.all()).whereType<ItemWashed>(), hasLength(1));
    });

    test('a new red shirt stops being treated as a bleeding risk', () async {
      // `isLikelyToBleed` is `timesWashed < 3`, and `timesWashed` never left
      // zero before this existed — so every saturated garment was isolated
      // into its own load forever.
      await repository.save(_redShirt());
      final red = (await repository.byId(const ItemId('red')))!;
      expect(red.isLikelyToBleed, isTrue);

      for (var i = 0; i < 3; i++) {
        await recorder().recordWash(
          load([(await repository.byId(const ItemId('red')))!]),
        );
      }

      expect(
        (await repository.byId(const ItemId('red')))!.isLikelyToBleed,
        isFalse,
      );
    });
  });

  test('the counters can be rebuilt from the log alone', () async {
    // The guarantee that makes the log worth keeping: the counters are a
    // cache, and a cache that cannot be regenerated is just data waiting to
    // go wrong.
    await recorder().recordWear(id);
    await recorder().recordWear(id);

    final replayed = UsageProjection.forItem(id, await events.all());
    expect(replayed.timesWorn, (await stored()).usage.timesWorn);
    expect(replayed.lastWornAt, (await stored()).usage.lastWornAt);
  });
}

WardrobeItem _item({
  required String id,
  required String name,
  required ItemType type,
  required String hex,
  required String colourName,
  Map<Fiber, int> composition = const {Fiber.cotton: 100},
}) {
  final now = DateTime.utc(2026, 8, 5);
  final item = WardrobeItem(
    id: ItemId(id),
    name: name,
    type: Confident(type, confidence: 0.95, source: Provenance.aiInference),
    composition: Confident(
      FabricComposition(composition),
      confidence: 0.95,
      source: Provenance.tagScan,
    ),
    colors: Confident(
      ColorPalette([ItemColor.fromHex(hex, name: colourName)]),
      confidence: 0.95,
      source: Provenance.aiInference,
    ),
    care: const CareProfile.unknown(),
    addedAt: now,
    updatedAt: now,
  );
  return item.copyWith(care: const CareResolver().forItem(item).profile);
}

WardrobeItem _hoodie() => _item(
  id: 'hoodie',
  name: 'Navy Nike hoodie',
  type: ItemType.hoodie,
  hex: '#1F2A44',
  colourName: 'Navy',
);

WardrobeItem _tee() => _item(
  id: 'tee',
  name: 'White tee',
  type: ItemType.tShirt,
  hex: '#F4F4F2',
  colourName: 'White',
);

WardrobeItem _redShirt() => _item(
  id: 'red',
  name: 'Red linen shirt',
  type: ItemType.dressShirt,
  hex: '#B3322C',
  colourName: 'Red',
  composition: const {Fiber.linen: 100},
);

WardrobeItem _draft() => _item(
  id: 'draft',
  name: 'Unknown garment',
  type: ItemType.tShirt,
  hex: '#888888',
  colourName: 'Grey',
);
