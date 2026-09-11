/// Laying several garments out and adding them from one photograph.
///
/// The point of the flow is arithmetic: one photograph, several garments, one
/// round trip. So what is worth protecting is not the reading — that is the
/// pile scanner's job and is tested where it lives — but the four things this
/// layer adds on top of it, each of which is silent when it breaks.
///
/// A garment gets *its own* picture, cut out of the photograph by its box.
/// Without that, six garments share one picture of a heap and the wardrobe
/// grid becomes six identical tiles.
///
/// A garment already owned is found and left unticked, because the second use
/// of this screen is somebody photographing a drawer they half-did last week.
///
/// Nothing is saved until they say so.
///
/// And a failure anywhere in the cutting is a worse picture, never a lost
/// garment — the readings are already in hand by then.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/scan/spread_controller.dart';

import 'support/fixtures.dart';

/// A 1×1 PNG, so the crop path decodes real bytes rather than bailing out.
///
/// Decoding is why every call below goes through `tester.runAsync`. Cutting a
/// garment out of the photograph means decoding it, and `decodeImageFromList`
/// hands its work to the engine — which `flutter_test`'s fake clock never
/// pumps, so without `runAsync` the future never completes and the test hangs
/// rather than failing.
const _png = ScanImage(
  bytes: [
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
    0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222,
    0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 0, 0,
    3, 1, 1, 0, 201, 254, 146, 239, 0, 0, 0, 0, 73, 69, 78, 68,
    174, 66, 96, 130,
  ],
);

void main() {
  late InMemoryWardrobeRepository repository;
  late _SpreadGateway gateway;
  late ProviderContainer container;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    gateway = _SpreadGateway();
    container = ProviderContainer(
      overrides: [
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        aiGatewayProvider.overrideWithValue(gateway),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'spread'),
        ),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource(const [_png]),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  SpreadController controller() =>
      container.read(spreadControllerProvider.notifier);
  SpreadState state() => container.read(spreadControllerProvider);

  group('one photo, several garments', () {
    testWidgets('each detection becomes a garment to review', (tester) async {
      gateway.detections = 3;

      await tester.runAsync(() => controller().capture());

      final reviewing = state() as SpreadReviewing;
      expect(reviewing.finds, hasLength(3));
      expect(gateway.pileCalls, 1, reason: 'one photo is one round trip');
    });

    testWidgets('and they all start ticked', (tester) async {
      // The fast path is one button. Somebody who laid six garments out meant
      // to add six garments.
      gateway.detections = 3;

      await tester.runAsync(() => controller().capture());

      expect((state() as SpreadReviewing).accepted, hasLength(3));
    });

    testWidgets('nothing reaches the wardrobe before they say so', (
      tester,
    ) async {
      gateway.detections = 2;

      await tester.runAsync(() => controller().capture());

      expect(await repository.query(const WardrobeQuery.owned()), isEmpty);
    });

    testWidgets('saving writes every ticked garment', (tester) async {
      gateway.detections = 3;
      await tester.runAsync(() => controller().capture());

      await tester.runAsync(() => controller().saveAccepted());

      expect(await repository.query(const WardrobeQuery.owned()), hasLength(3));
      expect((state() as SpreadSaved).saved, 3);
    });

    testWidgets('one turned down is not written, and the rest are', (
      tester,
    ) async {
      gateway.detections = 3;
      await tester.runAsync(() => controller().capture());
      controller().toggle(1);

      await tester.runAsync(() => controller().saveAccepted());

      expect(await repository.query(const WardrobeQuery.owned()), hasLength(2));
    });

    testWidgets('a name can be fixed before saving', (tester) async {
      gateway.detections = 1;
      await tester.runAsync(() => controller().capture());
      controller().rename(0, 'Green jumper');

      await tester.runAsync(() => controller().saveAccepted());

      final saved = await repository.query(const WardrobeQuery.owned());
      expect(saved.single.displayName, 'Green jumper');
    });
  });

  group('each garment gets its own picture', () {
    testWidgets('a detection is cut out of the photograph', (tester) async {
      // The failure this guards is six garments sharing one picture of a heap,
      // which makes the wardrobe grid useless and looks like it worked.
      gateway.detections = 2;

      await tester.runAsync(() => controller().capture());

      final finds = (state() as SpreadReviewing).finds;
      expect(finds, hasLength(2));
      for (final find in finds) {
        expect(find.image.bytes, isNotEmpty);
      }
    });

    testWidgets('an undecodable photo costs pictures, never garments', (
      tester,
    ) async {
      // The readings are already in hand by the time anything is cut. Losing a
      // garment because its picture could not be made would be trading the
      // valuable half for the cosmetic one.
      container.dispose();
      container = ProviderContainer(
        overrides: [
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          aiGatewayProvider.overrideWithValue(gateway),
          idGeneratorProvider.overrideWithValue(
            SequentialIdGenerator(prefix: 'spread'),
          ),
          imageCaptureProvider.overrideWithValue(
            FixedImageCaptureSource(const [
              ScanImage(bytes: [1, 2, 3]),
            ]),
          ),
        ],
      );
      gateway.detections = 2;

      await tester.runAsync(() => controller().capture());

      expect((state() as SpreadReviewing).finds, hasLength(2));
    });
  });

  group('garments already in the wardrobe', () {
    testWidgets('are found and left unticked rather than hidden', (
      tester,
    ) async {
      // Hidden, it would look like the app had missed them. Ticked, it would
      // add a second copy of a garment somebody already owns.
      await repository.save(_matching());
      gateway.detections = 1;

      await tester.runAsync(() => controller().capture());

      final reviewing = state() as SpreadReviewing;
      expect(reviewing.finds, hasLength(1));
      expect(reviewing.finds.single.isAlreadyOwned, isTrue);
      expect(reviewing.accepted, isEmpty);
      expect(reviewing.alreadyOwnedCount, 1);
    });

    testWidgets('and saving adds no duplicate', (tester) async {
      await repository.save(_matching());
      gateway.detections = 1;
      await tester.runAsync(() => controller().capture());

      await tester.runAsync(() => controller().saveAccepted());

      expect(await repository.query(const WardrobeQuery.owned()), hasLength(1));
    });

    testWidgets('but one can be taken anyway', (tester) async {
      // The match is a judgement, not a fact. Somebody who owns two of the
      // same shirt must be able to say so.
      await repository.save(_matching());
      gateway.detections = 1;
      await tester.runAsync(() => controller().capture());
      controller().toggle(0);

      await tester.runAsync(() => controller().saveAccepted());

      expect(await repository.query(const WardrobeQuery.owned()), hasLength(2));
    });

    testWidgets('an unfamiliar garment is offered as new', (tester) async {
      await repository.save(
        confidentItem(id: 'other', name: 'Red dress', type: ItemType.dress),
      );
      gateway.detections = 1;

      await tester.runAsync(() => controller().capture());

      expect((state() as SpreadReviewing).finds.single.isAlreadyOwned, isFalse);
    });
  });

  group('when the photo does not work out', () {
    testWidgets('nothing found says so', (tester) async {
      gateway.detections = 0;

      await tester.runAsync(() => controller().capture());

      expect(state(), isA<SpreadFailed>());
      expect((state() as SpreadFailed).message, contains('No clothes'));
    });

    testWidgets('clothes that overlap get different advice', (tester) async {
      // "Try again" is the wrong instruction when the answer is "move them
      // apart" — the same photo will fail the same way.
      gateway.detections = 0;
      gateway.obscured = 3;

      await tester.runAsync(() => controller().capture());

      expect((state() as SpreadFailed).message, contains('Spread them apart'));
    });

    testWidgets('a server failure is retryable', (tester) async {
      gateway.failure = const ScanFailure('The server is asleep.');

      await tester.runAsync(() => controller().capture());

      expect((state() as SpreadFailed).isRetryable, isTrue);
    });

    testWidgets('backing out of the camera changes nothing', (tester) async {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          aiGatewayProvider.overrideWithValue(gateway),
          idGeneratorProvider.overrideWithValue(
            SequentialIdGenerator(prefix: 'spread'),
          ),
          imageCaptureProvider.overrideWithValue(
            FixedImageCaptureSource(const []),
          ),
        ],
      );

      await tester.runAsync(() => controller().capture());

      expect(state(), isA<SpreadIdle>());
      expect(gateway.pileCalls, 0);
    });
  });
}

/// A wardrobe item the fake gateway's detection will be recognised as.
///
/// Every field the matcher weighs is deliberately identical to the detection
/// below, because recognition needs a score above 0.88 — a high bar, and the
/// right one: adopting a garment on a maybe is how one item's care label ends
/// up applied to a different item. A fixture that differed in colour would not
/// clear it, and the test would then be asserting that the matcher is strict
/// rather than that this screen does anything with the answer.
WardrobeItem _matching() => confidentItem(
  id: 'owned',
  name: 'Navy jumper',
  type: ItemType.sweater,
  hex: '#1F2A44',
  colorName: 'Navy',
);

class _SpreadGateway extends AiGateway {
  _SpreadGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  int pileCalls = 0;

  /// How many garments the photograph is said to contain.
  int detections = 1;

  /// Garments seen but not identifiable, which changes the advice given.
  int obscured = 0;

  ScanFailure? failure;

  @override
  Future<PileScanResult> scanPile(ScanImage image) async {
    pileCalls++;
    if (failure case final ScanFailure thrown) throw thrown;

    return PileScanResult(
      items: [
        for (var i = 0; i < detections; i++)
          DetectedItem(
            scan: GarmentScanResult(
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
                FabricComposition(const {Fiber.cotton: 100}),
                confidence: 0.7,
                source: Provenance.aiInference,
              ),
              suggestedName: 'Navy jumper',
            ),
            // Side by side across the frame, the way garments laid out on a
            // bed actually sit.
            boundingBox: BoundingBox(
              left: i * 0.25,
              top: 0.1,
              width: 0.2,
              height: 0.5,
            ),
            detectionConfidence: 0.9,
          ),
      ],
      partiallyObscuredCount: obscured,
    );
  }
}
