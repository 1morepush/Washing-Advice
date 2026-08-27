/// Adding a whole wardrobe in one sitting.
///
/// What is protected is the shape of the flow: nothing leaves the phone until
/// the user submits, one garment's photographs never bleed into the next, and
/// a batch of forty survives the two or three that go wrong.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/scan/bulk_controller.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late _BatchGateway gateway;
  late ProviderContainer container;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    gateway = _BatchGateway();
    container = _containerWith(gateway, repository);
  });

  tearDown(() => container.dispose());

  BulkController controller() =>
      container.read(bulkControllerProvider.notifier);
  BulkState state() => container.read(bulkControllerProvider);

  /// Photograph [count] garments, one shot each.
  Future<void> photograph(int count) async {
    for (var i = 0; i < count; i++) {
      await controller().capture();
      if (i < count - 1) controller().nextGarment();
    }
  }

  group('photographing the pile', () {
    test('nothing is sent while you are still taking photos', () async {
      // The whole reason this screen exists. Forty round trips you have to
      // stand through is the thing being replaced.
      await photograph(3);

      expect(gateway.garmentCalls, 0);
      expect(state(), isA<BulkCollecting>());
      expect((state() as BulkCollecting).garmentCount, 3);
    });

    test('one garment does not bleed into the next', () async {
      // Two merged into one loses a garment outright.
      await controller().capture();
      await controller().capture();
      controller().nextGarment();
      await controller().capture();

      final collecting = state() as BulkCollecting;
      expect(collecting.garmentCount, 2);
      expect(collecting.all.first.shots, hasLength(2));
      expect(collecting.all.last.shots, hasLength(1));
    });

    test('a garment boundary with no garment is not created', () async {
      // An empty garment is one more thing to explain in the review list.
      controller().nextGarment();
      controller().nextGarment();

      expect((state() as BulkCollecting).garmentCount, 0);
    });

    test('an accidental Next garment can be walked back', () async {
      // Otherwise the finished set is stranded and its photos unreachable.
      await controller().capture();
      controller().nextGarment();
      controller().discardLast();

      final collecting = state() as BulkCollecting;
      expect(collecting.done, isEmpty);
      expect(collecting.current.shots, hasLength(1));
    });

    test('the care label rides along with its own garment', () async {
      await controller().capture();
      await controller().capture();
      controller().setRole(1, PhotoRole.careTag);

      expect((state() as BulkCollecting).current.hasCareTag, isTrue);
    });
  });

  group('submitting the batch', () {
    test('each garment is read on its own', () async {
      await photograph(3);
      await controller().submit();

      expect(gateway.garmentCalls, 3);
      expect(state(), isA<BulkReviewing>());
      expect((state() as BulkReviewing).readable, hasLength(3));
    });

    test('the label goes to the label reader, per garment', () async {
      await controller().capture();
      await controller().capture();
      controller().setRole(1, PhotoRole.careTag);
      await controller().submit();

      expect(gateway.labelCalls, 1);
      final read = (state() as BulkReviewing).readable.single.read!;
      expect(read.draft.careLabel, isNotNull);
      expect(read.draft.effectiveCare.wash.maxTempC, 30);
    });

    test('one bad garment does not take the batch with it', () async {
      // The most important one here: a batch this size will hit a blurred
      // photo somewhere.
      gateway.failOnCall = 2;
      await photograph(3);
      await controller().submit();

      final reviewing = state() as BulkReviewing;
      expect(reviewing.readable, hasLength(2));
      expect(reviewing.failed, hasLength(1));
    });

    test('the one that failed is named, not silently dropped', () async {
      // Otherwise somebody counts hangers to work out which to redo.
      gateway.failOnCall = 2;
      await photograph(3);
      await controller().submit();

      final failed = (state() as BulkReviewing).failed.single;
      expect(failed.index, 1);
      expect(failed.failure, isNotNull);
    });

    test('and keeps the photographs that were sent for it', () async {
      // A number names nothing somebody can point at. Standing over a pile of
      // forty, the photograph they took is the only handle they have on which
      // garment "number 2" was.
      gateway.failOnCall = 2;
      await photograph(3);
      await controller().submit();

      final failed = (state() as BulkReviewing).failed.single;
      expect(failed.shots, isNotEmpty);
      expect(failed.identifyingShot, isNotNull);
    });

    test('the photographs kept are that garment\'s own', () async {
      // The failure worth guarding: an off-by-one here shows the user a
      // picture of the wrong garment, which is worse than showing none.
      container.dispose();
      container = _containerWith(
        gateway,
        repository,
        capture: _SequenceCapture(const [
          ScanImage(bytes: [10]),
          ScanImage(bytes: [20]),
          ScanImage(bytes: [30]),
        ]),
      );
      gateway.failOnCall = 2;
      await photograph(3);
      await controller().submit();

      final failed = (state() as BulkReviewing).failed.single;
      expect(failed.shots.single.image.bytes, [20]);
    });

    test('nothing has reached the wardrobe yet', () async {
      // Reviewing is batched, not skipped.
      await photograph(2);
      await controller().submit();

      expect(await repository.query(const WardrobeQuery.owned()), isEmpty);
    });
  });

  group('finding a failure again', () {
    test('the identifying shot is not the care label', () async {
      // A photograph of a tag looks like every other photograph of a tag,
      // which is the opposite of what this picture is for.
      gateway.failOnCall = 1;
      await controller().capture();
      await controller().capture();
      controller().setRole(0, PhotoRole.careTag);
      await controller().submit();

      final failed = (state() as BulkReviewing).failed.single;
      expect(failed.identifyingShot!.role, isNot(PhotoRole.careTag));
      expect(failed.labelShot, isNotNull);
    });

    test('a garment photographed only from its tag still shows that', () async {
      // It cannot be read — a label identifies nothing — and the tag is then
      // the only picture there is. Showing nothing at all would be worse.
      await controller().capture();
      controller().setRole(0, PhotoRole.careTag);
      await controller().submit();

      final failed = (state() as BulkReviewing).failed.single;
      expect(failed.identifyingShot, isNotNull);
      expect(failed.identifyingShot!.role, PhotoRole.careTag);
    });

    test('a label that said nothing is counted, not just noted', () async {
      // The garment is fine and goes in the wardrobe. What needs doing again
      // is the tag, and in a list of forty it goes unseen unless counted.
      gateway.labelSaysNothing = true;
      await controller().capture();
      await controller().capture();
      controller().setRole(1, PhotoRole.careTag);
      await controller().submit();

      final reviewing = state() as BulkReviewing;
      expect(reviewing.failed, isEmpty);
      expect(reviewing.labelUnread, hasLength(1));
      expect(reviewing.labelUnread.single.labelShot, isNotNull);
    });

    test('a label that read fine is not counted', () async {
      await controller().capture();
      await controller().capture();
      controller().setRole(1, PhotoRole.careTag);
      await controller().submit();

      expect((state() as BulkReviewing).labelUnread, isEmpty);
    });

    test('renaming a garment does not lose its photographs', () async {
      // The revision path rebuilds the outcome, and rebuilding it is where a
      // field quietly goes missing.
      await photograph(1);
      await controller().submit();
      controller().revise(0, (draft) => draft.copyWith(name: 'Green jumper'));

      final outcome = (state() as BulkReviewing).readable.single;
      expect(outcome.read!.draft.name, 'Green jumper');
      expect(outcome.shots, isNotEmpty);
    });
  });

  group('reviewing and saving', () {
    test(
      'everything arrives accepted, so the fast path is one button',
      () async {
        await photograph(3);
        await controller().submit();

        expect((state() as BulkReviewing).accepted, hasLength(3));
      },
    );

    test('saving writes them all, with their photos', () async {
      await photograph(2);
      await controller().submit();
      await controller().saveAccepted();

      final owned = await repository.query(const WardrobeQuery.owned());
      expect(owned, hasLength(2));
      expect(owned.first.photos.photos, isNotEmpty);
      expect(state(), isA<BulkSaved>());
      expect((state() as BulkSaved).saved, 2);
    });

    test('one turned down is not saved, and the rest are', () async {
      await photograph(3);
      await controller().submit();
      controller().toggle(1);
      await controller().saveAccepted();

      expect(await repository.query(const WardrobeQuery.owned()), hasLength(2));
    });

    test('turning one down can be taken back', () async {
      // A garment that vanished on a mistaken tap is a photo session you
      // cannot get back.
      await photograph(2);
      await controller().submit();
      controller().toggle(0);
      controller().toggle(0);

      expect((state() as BulkReviewing).accepted, hasLength(2));
    });

    test('a name can be fixed before saving', () async {
      await photograph(1);
      await controller().submit();
      controller().revise(0, (draft) => draft.copyWith(name: 'My good jumper'));
      await controller().saveAccepted();

      final owned = await repository.query(const WardrobeQuery.owned());
      expect(owned.single.displayName, 'My good jumper');
    });

    test('correcting one garment leaves the others alone', () async {
      await photograph(3);
      await controller().submit();
      controller().revise(1, (draft) => draft.copyWith(name: 'Only this one'));

      final names = (state() as BulkReviewing).readable
          .map((o) => o.read!.draft.displayName)
          .toList();
      expect(names[1], 'Only this one');
      expect(names[0], isNot('Only this one'));
    });

    test('an event is logged for every garment saved', () async {
      // The history is only replayable if bulk keeps row and event in step,
      // as the single flow does.
      await photograph(2);
      await controller().submit();
      await controller().saveAccepted();

      final events = await container.read(eventLogProvider).all();
      expect(events.whereType<ItemAdded>(), hasLength(2));
    });
  });
}

/// A backend that answers every garment, and can be told to fail one.
/// A container wired for the bulk flow.
///
/// Built by a function rather than inline so a test needing a different
/// camera — one handing back a *different* photograph each time, to tell the
/// garments apart — can ask for one without restating the other six overrides.
ProviderContainer _containerWith(
  AiGateway gateway,
  InMemoryWardrobeRepository repository, {
  ImageCaptureSource? capture,
}) => ProviderContainer(
  overrides: [
    imageStoreProvider.overrideWithValue(MemoryImageStore()),
    wardrobeRepositoryProvider.overrideWithValue(repository),
    eventLogProvider.overrideWithValue(InMemoryEventLog()),
    aiGatewayProvider.overrideWithValue(gateway),
    idGeneratorProvider.overrideWithValue(
      SequentialIdGenerator(prefix: 'bulk'),
    ),
    imageCaptureProvider.overrideWithValue(
      capture ??
          FixedImageCaptureSource([
            const ScanImage(bytes: [1, 2, 3]),
          ]),
    ),
  ],
);

/// A camera that hands back a different photograph on each shot.
class _SequenceCapture implements ImageCaptureSource {
  _SequenceCapture(this.images);

  final List<ScanImage> images;
  int taken = 0;

  @override
  Future<ScanImage?> capture() async =>
      taken < images.length ? images[taken++] : null;

  @override
  Future<List<ScanImage>> pickMultiple() async => images;
}

class _BatchGateway extends AiGateway {
  _BatchGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  int garmentCalls = 0;
  int labelCalls = 0;

  /// Whether the label reader comes back stating nothing usable.
  ///
  /// Not an exception: a blank reading is the commoner shape of a label that
  /// did not come out, and the one the intake turns into `labelUnread`.
  bool labelSaysNothing = false;

  /// Which call number to fail, counting from one. Null never fails.
  int? failOnCall;

  @override
  Future<Uint8List?> cutout(ScanImage image) async =>
      Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

  @override
  Future<GarmentScanResult> scanGarment(List<ScanImage> images) async {
    garmentCalls++;
    if (garmentCalls == failOnCall) {
      throw const ScanFailure('That photo was too blurred to read.');
    }

    return GarmentScanResult(
      type: Confident(
        ItemType.sweater,
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      colors: Confident(
        ColorPalette([ItemColor.fromHex('#1F2A44', name: 'Navy')]),
        confidence: 0.88,
        source: Provenance.aiInference,
      ),
      composition: Confident(
        FabricComposition(const {Fiber.wool: 100}),
        confidence: 0.6,
        source: Provenance.aiInference,
      ),
      suggestedName: 'Navy jumper $garmentCalls',
    );
  }

  @override
  Future<CareTagScanResult> scanCareTag(List<ScanImage> images) async {
    labelCalls++;
    if (labelSaysNothing) {
      return const CareTagScanResult(
        instructions: CareConstraint(),
        confidence: 0.1,
      );
    }
    return const CareTagScanResult(
      instructions: CareConstraint(maxTempC: 30),
      confidence: 0.93,
    );
  }
}
