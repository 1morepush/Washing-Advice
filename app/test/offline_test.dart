/// The app with no network at all.
///
/// "Local mode must work without internet" has been an architectural claim
/// since M1 and was never actually checked. It is easy to believe and easy to
/// get wrong: one provider that eagerly resolves a gateway, one screen that
/// awaits a health check before rendering, and a wardrobe becomes unusable on
/// a train.
///
/// So these tests use a gateway whose every method throws, which is a harsher
/// environment than a real outage — a socket timeout at least fails slowly.
/// Everything that does not inherently need a server must still work, and the
/// things that do need one must fail with something a person can act on.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/history/wear_recorder.dart';
import 'package:washing_advice/features/pile/pile_controller.dart';
import 'package:washing_advice/features/scan/scan_controller.dart';
import 'package:washing_advice/features/wardrobe/cutout_controller.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late InMemoryEventLog events;
  late ProviderContainer container;

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    events = InMemoryEventLog();
    await repository.saveAll([_jumper(), _tee()]);

    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(events),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        aiGatewayProvider.overrideWithValue(_OfflineGateway()),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'off'),
        ),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource([
            const ScanImage(bytes: [1, 2, 3]),
          ]),
        ),
        washerBrandProvider.overrideWith((ref) => 'Bosch'),
        dryerBrandProvider.overrideWith((ref) => null),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('works with no network', () {
    test('the wardrobe loads', () async {
      final items = await container
          .read(wardrobeRepositoryProvider)
          .query(const WardrobeQuery.owned());

      expect(items, hasLength(2));
    });

    test('filtering and search', () async {
      final repo = container.read(wardrobeRepositoryProvider);

      expect(
        await repo.query(const WardrobeQuery(fibers: {Fiber.wool})),
        hasLength(1),
      );
      expect(await repo.query(const WardrobeQuery(text: 'tee')), hasLength(1));
    });

    test('care advice, because no model is ever consulted for it', () async {
      // The point of keeping every laundry decision in the core. Care is
      // derived from the rule table, which is a table — not a service.
      final jumper = (await repository.byId(const ItemId('jumper')))!;
      final resolved = container.read(careResolverProvider).forItem(jumper);

      expect(resolved.profile.source, Provenance.careRule);
      expect(resolved.instructions.dry.tumbleDryAllowed, isFalse);
      expect(resolved.rationales, isNotEmpty);
    });

    test('sorting a known wardrobe into loads', () async {
      // The headline feature works offline for anything already catalogued,
      // because the sorter and the machine profiles are both local.
      final plan = container
          .read(laundrySorterProvider)
          .sort(
            await repository.query(const WardrobeQuery.launderable()),
            washer: container.read(washerProvider),
          );

      expect(plan.loads, isNotEmpty);
      expect(plan.loads.first.washerSetting?.programName, isNotEmpty);
    });

    test('recording a wear', () async {
      await container
          .read(wearRecorderProvider)
          .recordWear(const ItemId('jumper'));

      expect(await events.all(), hasLength(1));
      expect(
        (await repository.byId(const ItemId('jumper')))!.usage.timesWorn,
        1,
      );
    });

    test('editing an item and re-deriving its care', () async {
      final jumper = (await repository.byId(const ItemId('jumper')))!;
      final edited = jumper.copyWith(
        composition: Confident.fromUser(
          FabricComposition(const {Fiber.cotton: 100}),
        ),
      );

      await repository.save(
        edited.copyWith(
          care: container.read(careResolverProvider).forItem(edited).profile,
        ),
      );

      final stored = (await repository.byId(const ItemId('jumper')))!;
      expect(stored.composition.source, Provenance.userEdited);
      expect(
        stored.effectiveCare.warnings,
        isNot(contains(CareWarning.reshapeWhileDamp)),
      );
    });
  });

  group('degrades honestly where a server is genuinely needed', () {
    test('a garment scan says the server is unreachable', () async {
      await container.read(scanControllerProvider.notifier).captureAndScan();

      final state = container.read(scanControllerProvider);
      expect(state, isA<ScanError>());
      // Retryable, because reconnecting is exactly what fixes it.
      expect((state as ScanError).isRetryable, isTrue);
    });

    test('a pile scan fails without taking the app down', () async {
      await container.read(pileControllerProvider.notifier).captureAndPlan();

      expect(container.read(pileControllerProvider), isA<PileFailed>());
      // And the wardrobe is untouched by the failure.
      expect(await repository.query(const WardrobeQuery()), hasLength(2));
    });

    test('a cutout request fails without corrupting the item', () async {
      final withPhoto = (await repository.byId(const ItemId('jumper')))!
          .copyWith(
            photos: PhotoSet([
              ItemPhoto(
                uri: await container
                    .read(imageStoreProvider)
                    .save(Uint8List.fromList([1, 2, 3]), name: 'jumper-front'),
                role: PhotoRole.front,
                capturedAt: DateTime.utc(2026, 1, 1),
              ),
            ]),
          );
      await repository.save(withPhoto);

      await container
          .read(cutoutControllerProvider.notifier)
          .generate(const ItemId('jumper'));

      expect(container.read(cutoutControllerProvider), CutoutStatus.failed);
      // The photograph is still there; only the cutout is missing.
      expect((await repository.byId(const ItemId('jumper')))!.photos.length, 1);
    });
  });
}

WardrobeItem _item({
  required String id,
  required String name,
  required ItemType type,
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
      ColorPalette([ItemColor.fromHex('#3C3F44', name: 'Charcoal')]),
      confidence: 0.9,
      source: Provenance.aiInference,
    ),
    care: const CareProfile.unknown(),
    addedAt: now,
    updatedAt: now,
  );
  return item.copyWith(care: const CareResolver().forItem(item).profile);
}

WardrobeItem _jumper() => _item(
  id: 'jumper',
  name: 'Wool jumper',
  type: ItemType.sweater,
  composition: const {Fiber.wool: 100},
);

WardrobeItem _tee() =>
    _item(id: 'tee', name: 'White tee', type: ItemType.tShirt);

/// A gateway with no network behind it.
///
/// Every method throws rather than hanging, which is harsher than a real
/// outage and therefore a stricter test: nothing here gets to succeed by
/// accident on a slow timeout.
class _OfflineGateway extends AiGateway {
  _OfflineGateway() : super(baseUrl: Uri.parse('http://offline.invalid/'));

  Never _offline() => throw const ScanFailure('Could not reach the server.');

  @override
  Future<GarmentScanResult> scanGarment(List<ScanImage> images) async =>
      _offline();

  @override
  Future<CareTagScanResult> scanCareTag(ScanImage image) async => _offline();

  @override
  Future<PileScanResult> scanPile(ScanImage image) async => _offline();

  @override
  Future<Uint8List?> cutout(ScanImage image) async => null;
}
