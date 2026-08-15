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

  /// Photograph once and read it.
  ///
  /// Two calls now: a capture no longer reads on its own, because a label
  /// printed on both sides has to be turned over before anything is worked
  /// out. Wrapped here so the assertions below stay about what the reading
  /// does rather than about how many taps it took.
  Future<void> captureAndRead() async {
    await controller().capture();
    await controller().readCollected();
  }

  test('a label overrides the generic fibre rule', () async {
    // The superwash case. Without a label the wool rule forbids tumble drying;
    // the manufacturer says otherwise and knows this garment better.
    await captureAndRead();

    final reviewing = state() as CareTagReviewing;
    expect(reviewing.updated.effectiveCare.dry.tumbleDryAllowed, isTrue);
    expect(reviewing.updated.effectiveCare.wash.maxTempC, 40);
    expect(reviewing.updated.care.source, Provenance.tagScan);
  });

  test(
    'the overridden fields are reported, because that is the news',
    () async {
      await captureAndRead();

      final reviewing = state() as CareTagReviewing;
      expect(
        reviewing.resolution.fieldsOverriddenByLabel,
        containsAll(['wash.maxTempC', 'dry.tumbleDryAllowed']),
      );
    },
  );

  test('saving stops the app asking for the label again', () async {
    expect((await repository.byId(itemId))!.needsCareTagScan, isTrue);

    await captureAndRead();
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

      await captureAndRead();
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
    await captureAndRead();
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

    await captureAndRead();
    await controller().save();

    final saved = (await repository.byId(itemId))!;
    expect(saved.careLabel, isNotNull);
    expect(saved.needsCareTagScan, isFalse);
    expect(saved.photos.careTagPhoto, isNull);
  });

  test('the label survives a later correction to the fabric', () async {
    // The whole reason the constraint is stored on the item. Re-resolving after
    // an edit must not quietly drop the manufacturer's instruction.
    await captureAndRead();
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
    await captureAndRead();

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

    await captureAndRead();

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

    await captureAndRead();

    final reviewing = state() as CareTagReviewing;
    expect(reviewing.reading.isComplete, isFalse);
    expect(reviewing.updated.effectiveCare.wash.maxTempC, 40);
    // The rule table still covers the symbol that could not be read.
    expect(reviewing.updated.effectiveCare.dry.tumbleDryAllowed, isFalse);
  });

  group('a label printed on more than one side', () {
    /// A controller whose camera hands back [count] distinct photographs.
    CareTagController rolling(int count) {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          aiGatewayProvider.overrideWithValue(gateway),
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
          imageCaptureProvider.overrideWithValue(
            _Roll([
              for (var i = 0; i < count; i++) ScanImage(bytes: [i, i, i]),
            ]),
          ),
        ],
      );
      return container.read(careTagControllerProvider(itemId).notifier);
    }

    test('a photo is held rather than read straight away', () async {
      // The point of the change. Reading the first shot immediately gives a
      // complete-looking answer from half a label, with nothing on it to
      // suggest the other side exists.
      final controller = rolling(2);

      await controller.capture();

      expect(state(), isA<CareTagCollecting>());
      expect((state() as CareTagCollecting).images, hasLength(1));
      expect(gateway.photosSent, 0);
    });

    test('both sides reach the server as one reading', () async {
      final controller = rolling(2);

      await controller.capture();
      await controller.capture();
      await controller.readCollected();

      expect(gateway.photosSent, 2);
      expect(state(), isA<CareTagReviewing>());
    });

    test('and both are filed against the garment', () async {
      // Two sides, two photographs kept, so the label can be re-read later
      // without digging the garment back out of the wardrobe.
      final controller = rolling(2);

      await controller.capture();
      await controller.capture();
      await controller.readCollected();
      await controller.save();

      final saved = (await repository.byId(itemId))!;
      expect(saved.photos.withRole(PhotoRole.careTag), hasLength(2));
    });

    test('the last shot can be dropped without starting over', () async {
      final controller = rolling(3);

      await controller.capture();
      await controller.capture();
      controller.discardLast();

      expect((state() as CareTagCollecting).images, hasLength(1));
    });

    test('dropping the only shot goes back to the start', () async {
      final controller = rolling(1);

      await controller.capture();
      controller.discardLast();

      expect(state(), isA<CareTagIdle>());
    });

    test('backing out of the camera keeps what was already taken', () async {
      // The roll is exhausted after one, so the second capture reports a
      // cancelled camera. Losing side one there would be its own small
      // disaster.
      final controller = rolling(1);

      await controller.capture();
      await controller.capture();

      expect((state() as CareTagCollecting).images, hasLength(1));
    });
  });

  group('a label in another language', () {
    test('the language is carried through to the review', () async {
      // The instructions come from the ISO 3758 symbols, which are identical
      // everywhere. The language only decides what the screen says about it.
      gateway.reading = const CareTagScanResult(
        instructions: CareConstraint(method: WashMethod.machine, maxTempC: 30),
        confidence: 0.9,
        language: 'fr',
        rawText: "LAVER À FROID / LAVER À L'ENVERS",
      );

      await captureAndRead();

      final reviewing = state() as CareTagReviewing;
      expect(reviewing.reading.language, 'fr');
      // And the reading itself is unaffected — a French label is not a worse
      // label.
      expect(reviewing.updated.effectiveCare.wash.maxTempC, 30);
      expect(reviewing.updated.care.source, Provenance.tagScan);
    });

    test('a symbols-only label simply has no language', () async {
      gateway.reading = const CareTagScanResult(
        instructions: CareConstraint(method: WashMethod.machine, maxTempC: 30),
        confidence: 0.9,
      );

      await captureAndRead();

      expect((state() as CareTagReviewing).reading.language, isNull);
    });
  });

  group('scanning the same label again', () {
    /// The item with a label already scanned: 40°C machine wash, tumble dry
    /// low. The state somebody is in when they turn the tag over.
    Future<void> alreadyScanned() async {
      final item = (await repository.byId(itemId))!;
      final labelled = item.copyWith(
        careLabel: Confident(
          const CareConstraint(
            method: WashMethod.machine,
            maxTempC: 40,
            tumbleDryAllowed: true,
            tumbleDryHeat: TumbleDryHeat.low,
            warnings: {CareWarning.washInsideOut},
          ),
          confidence: 0.93,
          source: Provenance.tagScan,
        ),
      );
      await repository.save(
        labelled.copyWith(care: const CareResolver().forItem(labelled).profile),
      );
    }

    test('a second scan does not wipe out the first', () async {
      // The bug this replaces. Scanning the back of a two-sided label used to
      // replace the whole reading, losing the wash symbols already read off
      // the front — and nothing said so.
      await alreadyScanned();
      gateway.reading = const CareTagScanResult(
        instructions: CareConstraint(
          bleach: BleachAllowance.none,
          ironTemperature: IronTemperature.low,
        ),
        confidence: 0.9,
      );

      await captureAndRead();

      final label = (state() as CareTagReviewing).updated.careLabel!.value;
      expect(label.bleach, BleachAllowance.none);
      expect(label.maxTempC, 40, reason: 'the front reading was lost');
      expect(label.tumbleDryAllowed, isTrue);
    });

    test('and what it does state wins', () async {
      // A re-scan is as often a correction as an addition, so the newer
      // direct evidence takes precedence where there is any.
      await alreadyScanned();
      gateway.reading = const CareTagScanResult(
        instructions: CareConstraint(maxTempC: 30),
        confidence: 0.9,
      );

      await captureAndRead();

      expect(
        (state() as CareTagReviewing).updated.careLabel!.value.maxTempC,
        30,
      );
    });

    test('warnings from both readings survive', () async {
      await alreadyScanned();
      gateway.reading = const CareTagScanResult(
        instructions: CareConstraint(
          maxTempC: 30,
          warnings: {CareWarning.doNotUseSoftener},
        ),
        confidence: 0.9,
      );

      await captureAndRead();

      expect((state() as CareTagReviewing).updated.careLabel!.value.warnings, {
        CareWarning.washInsideOut,
        CareWarning.doNotUseSoftener,
      });
    });

    test('the screen is told what was kept rather than read', () async {
      await alreadyScanned();
      gateway.reading = const CareTagScanResult(
        instructions: CareConstraint(maxTempC: 30),
        confidence: 0.9,
      );

      await captureAndRead();

      final reviewing = state() as CareTagReviewing;
      expect(reviewing.keptFromEarlier, contains('wash.method'));
      expect(reviewing.keptFromEarlier, contains('dry.tumbleDryAllowed'));
      expect(reviewing.keptFromEarlier, isNot(contains('wash.maxTempC')));
      expect(reviewing.hadEarlierLabel, isTrue);
    });

    test('a merged label is no more trusted than its weaker half', () async {
      // Some of its fields genuinely come from the older reading, so the
      // whole cannot claim the newer one's confidence.
      await alreadyScanned();
      gateway.reading = const CareTagScanResult(
        instructions: CareConstraint(maxTempC: 30),
        confidence: 0.55,
      );

      await captureAndRead();

      expect((state() as CareTagReviewing).updated.careLabel!.confidence, 0.55);
    });

    test('replacing outright drops the earlier reading', () async {
      // The escape hatch. Merging keeps a field the earlier scan read wrong
      // whenever the new one is silent about it, and re-scanning cannot shift
      // it while that symbol stays illegible.
      await alreadyScanned();
      gateway.reading = const CareTagScanResult(
        instructions: CareConstraint(maxTempC: 30),
        confidence: 0.9,
      );

      await captureAndRead();
      await controller().replaceEarlierLabel();

      final reviewing = state() as CareTagReviewing;
      expect(reviewing.updated.careLabel!.value.maxTempC, 30);
      expect(reviewing.updated.careLabel!.value.tumbleDryAllowed, isNull);
      expect(reviewing.keptFromEarlier, isEmpty);
    });

    test('a first scan has nothing to merge with', () async {
      // No earlier label at all: nothing kept, and nothing to offer replacing.
      gateway.reading = const CareTagScanResult(
        instructions: CareConstraint(maxTempC: 30),
        confidence: 0.9,
      );

      await captureAndRead();

      final reviewing = state() as CareTagReviewing;
      expect(reviewing.keptFromEarlier, isEmpty);
      expect(reviewing.hadEarlierLabel, isFalse);
    });
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

  /// How many photographs the last read was given, so a test can check that
  /// both sides actually reached the server rather than only the first.
  int photosSent = 0;

  @override
  Future<CareTagScanResult> scanCareTag(List<ScanImage> images) async {
    photosSent = images.length;
    return reading ??
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

/// Hands back a different photograph on each capture, so a test can tell one
/// side of a label from the other. Returns null once exhausted, which is how
/// `ImageCaptureSource` reports a cancelled camera.
class _Roll implements ImageCaptureSource {
  _Roll(this._images);

  final List<ScanImage> _images;
  int _taken = 0;

  @override
  Future<ScanImage?> capture() async =>
      _taken < _images.length ? _images[_taken++] : null;

  @override
  Future<List<ScanImage>> pickMultiple() async => _images;
}
