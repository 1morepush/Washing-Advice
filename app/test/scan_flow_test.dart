/// The scan flow, driven end to end without a camera or a server.
///
/// This is what the capture interface and the [VisionPort] abstraction are for.
/// Both ends are substituted, so everything in between — the state machine, the
/// draft the reading turns into, the care the rule table derives from it, and
/// the write to storage — runs exactly as it does in the app.
///
/// A widget test, because the flow is a Riverpod graph and testing the
/// controller with a hand-built container would be testing a different wiring
/// from the one that ships.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/api/scan_dto.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/scan/scan_controller.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late _FakeGateway gateway;
  late MemoryImageStore images;
  late ProviderContainer container;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    gateway = _FakeGateway();
    images = MemoryImageStore();
    container = ProviderContainer(
      overrides: [
        imageStoreProvider.overrideWithValue(images),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        aiGatewayProvider.overrideWithValue(gateway),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'scan'),
        ),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource([
            const ScanImage(bytes: [1, 2, 3]),
          ]),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  ScanController controller() =>
      container.read(scanControllerProvider.notifier);

  ScanState state() => container.read(scanControllerProvider);

  /// Photograph once and identify it.
  ///
  /// Two calls now: a capture no longer scans on its own, because a shirt with
  /// a print across the back has to be turned around before the app decides
  /// what it is. Wrapped here so the assertions below stay about what the scan
  /// produces rather than about how many taps it took.
  Future<void> captureAndScan({bool fromGallery = false}) async {
    await controller().capture(fromGallery: fromGallery);
    await controller().scanCollected();
  }

  test('a capture runs through to a saved item', () async {
    await captureAndScan();

    final reviewing = container.read(scanControllerProvider);
    expect(reviewing, isA<ScanReviewing>());

    await controller().save();

    final saved = container.read(scanControllerProvider);
    expect(saved, isA<ScanSaved>());

    // The point of the whole flow: the item is actually in the wardrobe.
    final stored = await repository.query(const WardrobeQuery());
    expect(stored, hasLength(1));
    expect(stored.single.displayName, 'Navy Nike hoodie');
  });

  test('care is derived from the fabric, not taken from the model', () async {
    await captureAndScan();
    final draft =
        (container.read(scanControllerProvider) as ScanReviewing).draft;

    // The fake returns a wool jumper. Nothing in the response mentions washing,
    // so a care profile at all is proof the rule table ran — and it must be the
    // rules' provenance, not the photo's, or the app would be presenting a
    // guess with a derivation's authority.
    expect(draft.care.source, Provenance.careRule);
    expect(draft.effectiveCare.wash.maxTempC, lessThanOrEqualTo(30));
    expect(draft.effectiveCare.dry.tumbleDryAllowed, isFalse);
  });

  test('a wool garment still asks for its care label', () async {
    await captureAndScan();
    final draft =
        (container.read(scanControllerProvider) as ScanReviewing).draft;

    // A rule-derived profile is a good default and not a manufacturer's word.
    // Superwash wool exists, and the label is the only way to know.
    expect(draft.needsCareTagScan, isTrue);
  });

  test('backing out of the camera is not an error', () async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        imageStoreProvider.overrideWithValue(images),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        aiGatewayProvider.overrideWithValue(gateway),
        imageCaptureProvider.overrideWithValue(FixedImageCaptureSource([])),
      ],
    );

    await captureAndScan();

    expect(container.read(scanControllerProvider), isA<ScanIdle>());
  });

  test('an unreadable photo is not offered as retryable', () async {
    gateway.failure = const ScanFailure(
      'That photo could not be read.',
      isRetryable: false,
    );

    await captureAndScan();

    final state = container.read(scanControllerProvider);
    expect(state, isA<ScanError>());
    expect((state as ScanError).isRetryable, isFalse);
  });

  test('saving keeps the photo and its cutout', () async {
    await captureAndScan();
    await controller().save();

    final saved = (await repository.query(const WardrobeQuery())).single;
    final photo = saved.photos.displayPhoto!;

    expect(photo.role, PhotoRole.front);
    expect(photo.hasCutout, isTrue);
    // The list renders the cutout, which is the whole point of making one.
    expect(saved.photos.displayImageUri, photo.cutoutUri);
  });

  test('a refused cutout still saves the item', () async {
    // A missing picture is cosmetic. Losing a scan the user has already
    // reviewed and approved, over a background that would not separate, is
    // not — so the failure must not propagate.
    gateway.cutoutBytes = null;

    await captureAndScan();
    await controller().save();

    final saved = (await repository.query(const WardrobeQuery())).single;
    expect(saved.photos.displayPhoto?.hasCutout, isFalse);
    expect(saved.photos.displayImageUri, isNotNull);
  });

  test('the stored bytes can be read back for rendering', () async {
    await captureAndScan();
    await controller().save();

    final saved = (await repository.query(const WardrobeQuery())).single;
    final bytes = await images.read(saved.photos.displayImageUri!);

    expect(bytes, isNotNull);
    expect(bytes, isNotEmpty);
  });

  test('saving records an event, so the history is replayable', () async {
    await captureAndScan();
    await controller().save();

    final events = await container.read(eventLogProvider).all();
    expect(events, hasLength(1));
    expect(events.single, isA<ItemAdded>());
  });

  group('a garment that needs more than one photo', () {
    /// A controller whose camera hands back [count] distinct photographs.
    ScanController rolling(int count) {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          imageStoreProvider.overrideWithValue(images),
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          aiGatewayProvider.overrideWithValue(gateway),
          idGeneratorProvider.overrideWithValue(
            SequentialIdGenerator(prefix: 'scan'),
          ),
          imageCaptureProvider.overrideWithValue(
            _Roll([
              for (var i = 0; i < count; i++) ScanImage(bytes: [i, i, i]),
            ]),
          ),
        ],
      );
      return container.read(scanControllerProvider.notifier);
    }

    test('a photo is held rather than identified straight away', () async {
      // The shirt with a print across the back is identical to a plain one
      // from the front. Identifying the first shot would confidently call it
      // plain, with nothing on the result to say otherwise.
      final scan = rolling(2);

      await scan.capture();

      expect(state(), isA<ScanCollecting>());
      expect(gateway.imagesSent, 0);
    });

    test('every photo reaches the server as one garment', () async {
      final scan = rolling(3);

      await scan.capture();
      await scan.capture();
      await scan.capture();
      await scan.scanCollected();

      expect(gateway.imagesSent, 3);
      expect(state(), isA<ScanReviewing>());
    });

    test('the roles are guessed front, back, then detail', () async {
      final scan = rolling(3);

      await scan.capture();
      await scan.capture();
      await scan.capture();

      expect((state() as ScanCollecting).shots.map((s) => s.role), [
        PhotoRole.front,
        PhotoRole.back,
        PhotoRole.detail,
      ]);
    });

    test('and a guess can be corrected', () async {
      // People photograph the back first, and the app should not insist.
      final scan = rolling(2);

      await scan.capture();
      await scan.capture();
      scan.setRole(0, PhotoRole.back);
      scan.setRole(1, PhotoRole.front);

      expect((state() as ScanCollecting).shots.first.role, PhotoRole.back);
    });

    test('two photos of the same part get their own names', () async {
      // The bug this replaces, and it needed four photographs to show: names
      // were derived from the role alone, and the third and fourth shots are
      // both details. The second one took the first one's name, so the file
      // was overwritten and the set kept two records pointing at one image,
      // one of them carrying the wrong dimensions.
      final scan = rolling(4);

      await scan.capture();
      await scan.capture();
      await scan.capture();
      await scan.capture();
      await scan.scanCollected();
      await scan.save();

      final saved = (await repository.query(const WardrobeQuery())).single;
      final uris = [for (final photo in saved.photos.photos) photo.uri];
      expect(uris.toSet(), hasLength(uris.length));
      expect(saved.photos.photos, hasLength(4));
    });

    test('two photos marked front produce one cutout, not two', () async {
      // The user is free to mark both, and a second cutout would be a wasted
      // upload writing over the first.
      final scan = rolling(2);

      await scan.capture();
      await scan.capture();
      scan.setRole(1, PhotoRole.front);
      await scan.scanCollected();
      await scan.save();

      expect(gateway.cutoutsRequested, 1);
    });

    test('the last shot can be dropped without starting over', () async {
      final scan = rolling(2);

      await scan.capture();
      await scan.capture();
      scan.discardLast();

      expect((state() as ScanCollecting).shots, hasLength(1));
    });

    test('backing out of the camera keeps what was already taken', () async {
      final scan = rolling(1);

      await scan.capture();
      await scan.capture();

      expect((state() as ScanCollecting).shots, hasLength(1));
    });
  });

  group('the care label in the same handful of photos', () {
    /// Photograph the garment, then its tag, and identify the lot.
    Future<void> captureBoth() async {
      await controller().capture();
      await controller().capture();
      controller().setRole(1, PhotoRole.careTag);
      await controller().scanCollected();
    }

    setUp(() {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          imageStoreProvider.overrideWithValue(images),
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          aiGatewayProvider.overrideWithValue(gateway),
          idGeneratorProvider.overrideWithValue(
            SequentialIdGenerator(prefix: 'scan'),
          ),
          imageCaptureProvider.overrideWithValue(
            _Roll(const [
              ScanImage(bytes: [1, 2, 3]),
              ScanImage(bytes: [4, 5, 6]),
            ]),
          ),
        ],
      );
    });

    test('the tag goes to the label reader, not the garment one', () async {
      // A photograph of a care tag tells the garment reader almost nothing.
      await captureBoth();

      expect(gateway.imagesSent, 1);
      expect(gateway.labelImagesSent, 1);
    });

    test('the manufacturer instruction wins over the fabric guess', () async {
      // Without the label, care comes from the rule table reasoning about
      // wool; with it, from whoever made the garment.
      await captureBoth();

      final reviewing = state() as ScanReviewing;
      expect(reviewing.draft.careLabel, isNotNull);
      expect(reviewing.draft.careLabel!.source, Provenance.tagScan);
      expect(reviewing.draft.effectiveCare.wash.maxTempC, 30);
    });

    test('the saved item carries it, so no second trip is needed', () async {
      await captureBoth();
      await controller().save();

      final saved = await repository.byId((state() as ScanSaved).item.id);
      expect(saved!.careLabel, isNotNull);
      expect(saved.needsCareTagScan, isFalse);
    });

    test('the label photo is filed as a label, and never cut out', () async {
      // A cutout of a care tag is meaningless, and the front is the only shot
      // that gets one.
      await captureBoth();
      await controller().save();

      final saved = await repository.byId((state() as ScanSaved).item.id);
      expect(
        saved!.photos.photos.map((p) => p.role),
        containsAll([PhotoRole.front, PhotoRole.careTag]),
      );
      expect(gateway.cutoutsRequested, 1);
    });

    test('a garment photographed without a tag is unchanged', () async {
      // The ordinary path has to stay exactly as it was: no label reader call
      // at all, and care still derived by the rule table.
      await controller().capture();
      await controller().scanCollected();

      expect(gateway.labelImagesSent, 0);
      final reviewing = state() as ScanReviewing;
      expect(reviewing.draft.careLabel, isNull);
      expect(reviewing.label, isNull);
      expect(reviewing.labelUnread, isFalse);
    });

    test('an unreadable tag does not cost you the garment', () async {
      // The garment is identified and worth saving regardless.
      gateway.labelReading = null;
      await captureBoth();

      final reviewing = state() as ScanReviewing;
      expect(reviewing.draft.type.value, ItemType.sweater);
      expect(reviewing.draft.careLabel, isNull);
      // Said rather than silent, so nobody believes the manufacturer's
      // instructions are in hand when what is showing is a guess.
      expect(reviewing.labelUnread, isTrue);
    });

    test('a label request that fails outright is the same story', () async {
      gateway.labelFailure = const ScanFailure('The label reader is down.');
      await captureBoth();

      expect(state(), isA<ScanReviewing>());
      expect((state() as ScanReviewing).labelUnread, isTrue);
    });

    test('a tag with no garment identifies nothing, and says so', () async {
      // Better than handing a photo of a tag to the garment reader.
      await controller().capture();
      controller().setRole(0, PhotoRole.careTag);
      await controller().scanCollected();

      expect(state(), isA<ScanError>());
      expect((state() as ScanError).message, contains('only its label'));
      expect(gateway.imagesSent, 0);
    });

    test('editing the draft does not lose the label that was read', () async {
      // withDraft rebuilds the reviewing state; dropping the label there would
      // lose the reading the moment somebody corrected the name.
      await captureBoth();
      controller().reviseDraft((draft) => draft.copyWith(name: 'My jumper'));

      final reviewing = state() as ScanReviewing;
      expect(reviewing.label, isNotNull);
      expect(reviewing.draft.careLabel, isNotNull);
    });
  });
}

/// Stands in for the backend.
///
/// Extends [AiGateway] rather than implementing [VisionPort] because the scan
/// controller reads `lastDiagnostics`. The base constructor never opens a
/// socket, so nothing here touches the network.
class _FakeGateway extends AiGateway {
  _FakeGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  ScanFailure? failure;

  /// Null stands for a server that refused to separate the garment.
  Uint8List? cutoutBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

  /// How many photographs the last identification was given, so a test can
  /// check that the back actually reached the server rather than only the
  /// front.
  int imagesSent = 0;

  /// How many cutouts were asked for. One garment needs exactly one.
  int cutoutsRequested = 0;

  /// How many photographs the label reader was given, so a test can prove the
  /// tag went to the label endpoint rather than to the garment one.
  int labelImagesSent = 0;

  /// What the label reader answers with. Null stands for a server that could
  /// not make anything of the photograph.
  CareTagScanResult? labelReading = const CareTagScanResult(
    instructions: CareConstraint(maxTempC: 30),
    confidence: 0.93,
  );

  ScanFailure? labelFailure;

  @override
  Future<CareTagScanResult> scanCareTag(List<ScanImage> images) async {
    labelImagesSent = images.length;
    if (labelFailure case final ScanFailure failure) throw failure;
    // Null stands for a label that stated nothing legible, which is a
    // different outcome from the request failing.
    return labelReading ??
        const CareTagScanResult(
          instructions: CareConstraint(),
          confidence: 0.1,
          unreadableSymbolCount: 4,
        );
  }

  @override
  Future<Uint8List?> cutout(ScanImage image) async {
    cutoutsRequested++;
    return cutoutBytes;
  }

  @override
  Future<GarmentScanResult> scanGarment(List<ScanImage> images) async {
    if (failure case final ScanFailure failure) throw failure;
    imagesSent = images.length;

    lastDiagnostics = ScanDiagnostics(
      stagesRun: const ['knowledge-cache', 'gemini'],
      stageAnswered: 'gemini',
      elapsedMs: 412,
    );

    return GarmentScanResult(
      type: Confident(
        ItemType.sweater,
        confidence: 0.91,
        source: Provenance.aiInference,
      ),
      colors: Confident(
        ColorPalette([ItemColor.fromHex('#1F2A44', name: 'Navy')]),
        confidence: 0.88,
        source: Provenance.aiInference,
      ),
      composition: Confident(
        FabricComposition(const {Fiber.wool: 100}),
        confidence: 0.62,
        source: Provenance.aiInference,
      ),
      brand: Confident(
        'Nike',
        confidence: 0.77,
        source: Provenance.aiInference,
      ),
      suggestedName: 'Navy Nike hoodie',
    );
  }
}

/// Hands back a different photograph on each capture, so a test can tell one
/// side of a garment from the other. Returns null once exhausted, which is how
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
