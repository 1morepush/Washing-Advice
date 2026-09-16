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

  group('documenting a wardrobe rather than adding a garment', () {
    // The two jobs this screen serves are far apart: adding one shirt
    // properly, against getting a hundred garments recorded at all. The
    // second is what these cover, and the cost that matters there is taps.

    test('one photo per garment finishes each on its own', () async {
      // Shoot, shoot, shoot. Without this it is shoot, tap, shoot, tap.
      controller().setOnePerGarment(true);
      await controller().capture();
      await controller().capture();
      await controller().capture();

      final collecting = state() as BulkCollecting;
      expect(collecting.garmentCount, 3);
      expect(collecting.current.isEmpty, isTrue);
    });

    test('and it is off unless asked for', () async {
      // Off is the default because it is the one that cannot lose anything: a
      // wrong tap here costs a tap, and the other way silently splits a
      // garment in two.
      await controller().capture();
      await controller().capture();

      expect((state() as BulkCollecting).garmentCount, 1);
    });

    test('turning it on puts away what is already in hand', () async {
      // A half-photographed garment left in `current` while every later shot
      // becomes its own garment is a state nothing else expects, and the next
      // photograph would silently join it.
      await controller().capture();
      controller().setOnePerGarment(true);

      final collecting = state() as BulkCollecting;
      expect(collecting.done, hasLength(1));
      expect(collecting.current.isEmpty, isTrue);
    });

    test('turning it on with nothing in hand adds no phantom', () async {
      controller().setOnePerGarment(true);

      expect((state() as BulkCollecting).garmentCount, 0);
    });

    test('turning it back off keeps everything photographed so far', () async {
      controller().setOnePerGarment(true);
      await controller().capture();
      await controller().capture();
      controller().setOnePerGarment(false);

      final collecting = state() as BulkCollecting;
      expect(collecting.garmentCount, 2);
      expect(collecting.onePerGarment, isFalse);
    });

    test('the mode survives the other things the screen does', () async {
      // Every rebuild of the collecting state has to carry it, and a rebuild
      // is exactly where a field goes quietly missing.
      controller().setOnePerGarment(true);
      await controller().capture();
      controller().discardLast();

      expect((state() as BulkCollecting).onePerGarment, isTrue);
    });
  });

  group('importing a camera roll', () {
    // The point of the whole thing: a phone's own camera is faster than any
    // in-app one, so somebody can photograph forty garments elsewhere and
    // hand the lot over in a single tap.

    test('each photo becomes its own garment', () async {
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

      await controller().importAsGarments();

      final collecting = state() as BulkCollecting;
      expect(collecting.garmentCount, 3);
      expect(collecting.photoCount, 3);
    });

    test('and each is its own photograph, in order', () async {
      // The failure worth guarding: an import that put every picked image on
      // one garment, which is what `capture(fromGallery: true)` does and is
      // the opposite reading of the same gesture.
      container.dispose();
      container = _containerWith(
        gateway,
        repository,
        capture: _SequenceCapture(const [
          ScanImage(bytes: [10]),
          ScanImage(bytes: [20]),
        ]),
      );

      await controller().importAsGarments();

      final garments = (state() as BulkCollecting).all;
      expect(garments.first.shots.single.image.bytes, [10]);
      expect(garments.last.shots.single.image.bytes, [20]);
    });

    test('an imported photo is the front of its garment', () async {
      await controller().importAsGarments();

      final garment = (state() as BulkCollecting).all.first;
      expect(garment.shots.single.role, PhotoRole.front);
    });

    test('a garment in hand is finished rather than merged into', () async {
      // Absorbing an import into a half-photographed garment would put
      // somebody else's front photo on its back.
      await controller().capture();
      await controller().importAsGarments();

      final collecting = state() as BulkCollecting;
      expect(collecting.garmentCount, 2);
      expect(collecting.current.isEmpty, isTrue);
    });

    test('backing out of the picker changes nothing', () async {
      container.dispose();
      container = _containerWith(
        gateway,
        repository,
        capture: FixedImageCaptureSource(const []),
      );
      await controller().importAsGarments();

      expect(state(), isA<BulkCollecting>());
      expect((state() as BulkCollecting).isEmpty, isTrue);
    });

    test('imported garments go to the server like any other', () async {
      container.dispose();
      container = _containerWith(
        gateway,
        repository,
        capture: _SequenceCapture(const [
          ScanImage(bytes: [10]),
          ScanImage(bytes: [20]),
        ]),
      );
      await controller().importAsGarments();
      await controller().submit();

      expect(gateway.garmentCalls, 2);
      expect((state() as BulkReviewing).readable, hasLength(2));
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

  group('when the service is rate-limited mid-batch', () {
    test('the batch waits it out and carries on', () async {
      // The free tier meters by the minute, and a rate limit is the one
      // failure the next photograph makes worse: sending straight on used to
      // fail every garment after the first refusal the same way.
      await photograph(3);
      gateway.busyOnCall = 2;

      await controller().submit();

      final reviewing = state() as BulkReviewing;
      expect(reviewing.outcomes.where((o) => o.succeeded), hasLength(3));
      // Three garments, one of them read twice.
      expect(gateway.garmentCalls, 4);
    });

    test('a refusal with no wait attached is an ordinary failure', () async {
      await photograph(3);
      gateway.failOnCall = 2;

      await controller().submit();

      expect(gateway.garmentCalls, 3);
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

  /// Which call number the server is too busy for, counting from one.
  ///
  /// Fails that one call with a wait attached, the way a 429 does; the next
  /// call goes through. What a batch does with the wait is the behaviour.
  int? busyOnCall;

  @override
  Future<Uint8List?> cutout(ScanImage image) async =>
      Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

  @override
  Future<GarmentScanResult> scanGarment(List<ScanImage> images) async {
    garmentCalls++;
    if (garmentCalls == failOnCall) {
      throw const ScanFailure('That photo was too blurred to read.');
    }
    if (garmentCalls == busyOnCall) {
      throw const ScanFailure(
        'The AI service is busy right now.',
        retryAfter: Duration(milliseconds: 20),
      );
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
