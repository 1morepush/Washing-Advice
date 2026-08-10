/// Scanning a care label, end to end without a camera or a server.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/data/images/image_store.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/scan/care_tag_controller.dart';

void main() {
  const itemId = ItemId('jumper');

  late InMemoryWardrobeRepository repository;
  late _FakeGateway gateway;
  late ProviderContainer container;

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    gateway = _FakeGateway();
    await repository.save(_woolJumper());

    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        aiGatewayProvider.overrideWithValue(gateway),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource([
            const ScanImage(bytes: [1, 2, 3]),
          ]),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  CareTagController controller() =>
      container.read(careTagControllerProvider(itemId).notifier);

  CareTagState state() => container.read(careTagControllerProvider(itemId));

  test('a label overrides the generic fibre rule', () async {
    // The superwash case. Without a label the wool rule forbids tumble drying;
    // the manufacturer says otherwise and knows this garment better.
    await controller().captureAndRead();

    final reviewing = state() as CareTagReviewing;
    expect(reviewing.updated.effectiveCare.dry.tumbleDryAllowed, isTrue);
    expect(reviewing.updated.effectiveCare.wash.maxTempC, 40);
    expect(reviewing.updated.care.source, Provenance.tagScan);
  });

  test(
    'the overridden fields are reported, because that is the news',
    () async {
      await controller().captureAndRead();

      final reviewing = state() as CareTagReviewing;
      expect(
        reviewing.resolution.fieldsOverriddenByLabel,
        containsAll(['wash.maxTempC', 'dry.tumbleDryAllowed']),
      );
    },
  );

  test('saving stops the app asking for the label again', () async {
    expect((await repository.byId(itemId))!.needsCareTagScan, isTrue);

    await controller().captureAndRead();
    await controller().save();

    final saved = (await repository.byId(itemId))!;
    expect(saved.needsCareTagScan, isFalse);
    expect(saved.careLabel, isNotNull);
  });

  test(
    'what the detail screen will read is the scanned item, not the old one',
    () async {
      // Everything above asserts against the repository, and all of it passed
      // while the app was visibly broken: the detail screen reads `itemProvider`,
      // a cached future that no repository write pushes to. Someone scanned a
      // label, tapped Done, and got back the garment as it was before — the old
      // care, "Unknown composition", and a banner asking for the label they had
      // just scanned. Reading through the provider is the only assertion that
      // could have caught it, so this test does.
      await container.read(itemProvider(itemId).future);

      await controller().captureAndRead();
      await controller().save();

      final shown = (await container.read(itemProvider(itemId).future))!;
      expect(shown.needsCareTagScan, isFalse);
      expect(shown.careLabel, isNotNull);
      expect(shown.effectiveCare.wash.maxTempC, 40);
      expect(shown.composition.value.percentOf(Fiber.wool), 80);
    },
  );

  test('the label photograph is kept, so it can be re-read later', () async {
    // `PhotoSet.careTagPhoto` exists to let someone check the instructions
    // without digging the garment back out of the wardrobe, and nothing had
    // ever filed a photo under that role — the accessor and the role were
    // both dead code.
    await controller().captureAndRead();
    await controller().save();

    final saved = (await repository.byId(itemId))!;
    final label = saved.photos.careTagPhoto;

    expect(label, isNotNull);
    expect(label!.role, PhotoRole.careTag);
    // A label is text to re-read, not a garment to lift off its background.
    expect(label.hasCutout, isFalse);
  });

  test('a label photo that will not store still saves the reading', () async {
    // The reading is the thing the user reviewed and approved. Losing it
    // because a browser is out of quota would be trading the valuable half of
    // this flow for the convenient half.
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        aiGatewayProvider.overrideWithValue(gateway),
        imageStoreProvider.overrideWithValue(const _FullImageStore()),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource([
            const ScanImage(bytes: [1, 2, 3]),
          ]),
        ),
      ],
    );

    await controller().captureAndRead();
    await controller().save();

    final saved = (await repository.byId(itemId))!;
    expect(saved.careLabel, isNotNull);
    expect(saved.needsCareTagScan, isFalse);
    expect(saved.photos.careTagPhoto, isNull);
  });

  test('the label survives a later correction to the fabric', () async {
    // The whole reason the constraint is stored on the item. Re-resolving after
    // an edit must not quietly drop the manufacturer's instruction.
    await controller().captureAndRead();
    await controller().save();

    final saved = (await repository.byId(itemId))!;
    final edited = saved.copyWith(
      composition: Confident(
        FabricComposition(const {Fiber.wool: 60, Fiber.nylon: 40}),
        confidence: 1,
        source: Provenance.userEdited,
      ),
    );

    final reresolved = container.read(careResolverProvider).forItem(edited);
    expect(reresolved.instructions.dry.tumbleDryAllowed, isTrue);
    expect(reresolved.profile.source, Provenance.tagScan);
  });

  test('a label printing its composition outranks the photo guess', () async {
    await controller().captureAndRead();

    final reviewing = state() as CareTagReviewing;
    expect(reviewing.updated.composition.source, Provenance.tagScan);
    expect(reviewing.updated.composition.value.percentOf(Fiber.wool), 80);
  });

  test('an illegible label is refused rather than saved as knowledge', () async {
    // A constraint stating nothing would still be recorded at `tagScan`
    // provenance, making the app *more* confident about care it learned nothing
    // new about — and it would stop prompting for the scan that is still needed.
    gateway.reading = const CareTagScanResult(
      instructions: CareConstraint(),
      confidence: 0.2,
      unreadableSymbolCount: 5,
    );

    await controller().captureAndRead();

    expect(state(), isA<CareTagFailed>());
    expect((await repository.byId(itemId))!.careLabel, isNull);
  });

  test('a partial reading is kept, and says what it could not read', () async {
    // Different from the case above: this label did state something, so it is
    // worth having even though part of it defeated the OCR.
    gateway.reading = const CareTagScanResult(
      instructions: CareConstraint(maxTempC: 40),
      confidence: 0.7,
      unreadableSymbolCount: 1,
    );

    await controller().captureAndRead();

    final reviewing = state() as CareTagReviewing;
    expect(reviewing.reading.isComplete, isFalse);
    expect(reviewing.updated.effectiveCare.wash.maxTempC, 40);
    // The rule table still covers the symbol that could not be read.
    expect(reviewing.updated.effectiveCare.dry.tumbleDryAllowed, isFalse);
  });
}

WardrobeItem _woolJumper() {
  final now = DateTime.utc(2026, 8, 5);
  return WardrobeItem(
    id: const ItemId('jumper'),
    name: 'Charcoal merino jumper',
    type: Confident(
      ItemType.sweater,
      confidence: 0.9,
      source: Provenance.aiInference,
    ),
    // Guessed from a photo and not very confidently, which is what makes this
    // item ask for its label in the first place.
    composition: Confident(
      FabricComposition(const {Fiber.wool: 100}),
      confidence: 0.45,
      source: Provenance.aiInference,
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
}

class _FakeGateway extends AiGateway {
  _FakeGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  CareTagScanResult? reading;

  @override
  Future<CareTagScanResult> scanCareTag(ScanImage image) async =>
      reading ??
      CareTagScanResult(
        instructions: const CareConstraint(
          method: WashMethod.machine,
          maxTempC: 40,
          agitation: Agitation.mild,
          tumbleDryAllowed: true,
          tumbleDryHeat: TumbleDryHeat.low,
        ),
        confidence: 0.93,
        composition: Confident(
          FabricComposition(const {Fiber.wool: 80, Fiber.nylon: 20}),
          confidence: 0.95,
          source: Provenance.tagScan,
        ),
        symbolsFound: const ['wash_40', 'tumble_low', 'iron_low'],
      );
}

/// Reads fine, refuses every write — a browser origin out of quota.
class _FullImageStore implements ImageStore {
  const _FullImageStore();

  @override
  Future<Uint8List?> read(String uri) async => null;

  @override
  Future<String> save(List<int> bytes, {required String name}) async =>
      throw const _QuotaExceeded();

  @override
  Future<void> delete(String uri) async {}
}

class _QuotaExceeded implements Exception {
  const _QuotaExceeded();

  @override
  String toString() => 'QuotaExceededError';
}
