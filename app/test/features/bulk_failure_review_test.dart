/// What the batch review says about the ones that did not work.
///
/// The batch flow exists to be walked away from: photograph forty garments,
/// hand them over, come back later. That is exactly why a failure buried in
/// it is worse than a failure in the single flow — nobody is watching when it
/// happens, and by the time they look, the pile may be back in the wardrobe.
///
/// So two things are asserted here rather than left to the eye: that a failure
/// is said *before* the Save button rather than after forty cards, and that it
/// arrives with the photograph that was taken, which is the only thing that
/// identifies which garment in the pile it was.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/scan/bulk_controller.dart';
import 'package:washing_advice/features/scan/bulk_screen.dart';

/// A 1×1 PNG.
///
/// Real bytes rather than `[1, 2, 3]` on purpose: `Image.memory` falls back to
/// an `errorBuilder` placeholder for anything it cannot decode, and that
/// placeholder is still an `Image` in the tree. A test looking only for the
/// widget would pass while the user saw a grey square, which is the whole
/// failure being guarded against.
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
  late _Gateway gateway;
  late ProviderContainer container;

  setUp(() {
    gateway = _Gateway();
    container = ProviderContainer(
      overrides: [
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        wardrobeRepositoryProvider.overrideWithValue(
          InMemoryWardrobeRepository(),
        ),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        aiGatewayProvider.overrideWithValue(gateway),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'bulk'),
        ),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource(const [_png]),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  BulkController controller() =>
      container.read(bulkControllerProvider.notifier);

  Future<void> photograph(int count) async {
    for (var i = 0; i < count; i++) {
      await controller().capture();
      if (i < count - 1) controller().nextGarment();
    }
  }

  Future<void> open(WidgetTester tester) async {
    // Tall, because what is being asserted is partly about order: the failure
    // has to be reachable above the fold rather than under a list of cards.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BulkScanScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a garment that could not be read', () {
    testWidgets('is announced, not left at the bottom of the list', (
      tester,
    ) async {
      gateway.failOnCall = 2;
      await photograph(3);
      await controller().submit();
      await open(tester);

      expect(find.text('1 garment could not be read'), findsOneWidget);
      expect(find.text('1 could not be read'), findsOneWidget);
    });

    testWidgets('says which one, and why', (tester) async {
      gateway.failOnCall = 2;
      await photograph(3);
      await controller().submit();
      await open(tester);

      expect(find.text('Garment 2'), findsOneWidget);
      expect(find.text('That photo was too blurred to read.'), findsOneWidget);
    });

    testWidgets('and shows the photograph that was taken of it', (
      tester,
    ) async {
      // The point of the whole change. Without this the user has a number and
      // a pile, and no way to connect them.
      gateway.failOnCall = 1;
      await photograph(1);
      await controller().submit();
      await open(tester);

      final card = find.ancestor(
        of: find.text('Garment 1'),
        matching: find.byType(Card),
      );
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byType(Image)),
        findsAtLeastNWidgets(1),
      );
      // And it decoded. `Image.memory` swaps in the errorBuilder placeholder
      // for bytes it cannot read, and that placeholder is still an `Image` in
      // the tree — so the check above passes just as happily on a grey square.
      expect(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.image_not_supported_outlined),
        ),
        findsNothing,
      );
    });

    testWidgets('appears before the Save button in the list', (tester) async {
      // Order is the fix. "38 read" and a Save button, with the two failures
      // forty cards below, is how a garment goes missing unnoticed.
      gateway.failOnCall = 3;
      await photograph(3);
      await controller().submit();
      await open(tester);

      final failure = tester.getTopLeft(find.text('Garment 3')).dy;
      final firstSuccess = tester.getTopLeft(find.text('Navy jumper 1')).dy;
      expect(failure, lessThan(firstSuccess));
    });
  });

  group('when every one of them failed', () {
    testWidgets('the photos are still shown rather than one message', (
      tester,
    ) async {
      // The old screen collapsed to a single sentence here, which is the case
      // where the user needs the pictures most: nothing was saved at all.
      gateway.failEverything = true;
      await photograph(2);
      await controller().submit();
      await open(tester);

      expect(find.text('None of them could be read'), findsOneWidget);
      expect(find.text('Garment 1'), findsOneWidget);
      expect(find.text('Garment 2'), findsOneWidget);
      expect(find.text('Start again'), findsOneWidget);
    });
  });

  group('a care label that did not come out', () {
    testWidgets('is counted at the top, and shown with its photo', (
      tester,
    ) async {
      // The garment is fine and is going into the wardrobe. What needs doing
      // again is the tag, and it is one line on one card in a list of forty.
      gateway.labelSaysNothing = true;
      await controller().capture();
      await controller().capture();
      controller().setRole(1, PhotoRole.careTag);
      await controller().submit();
      await open(tester);

      expect(find.text('1 care label did not come out'), findsOneWidget);
      expect(
        find.text('This is the photo that could not be read.'),
        findsOneWidget,
      );
    });

    testWidgets('and nothing is announced when everything worked', (
      tester,
    ) async {
      await photograph(2);
      await controller().submit();
      await open(tester);

      expect(find.textContaining('could not be read'), findsNothing);
      expect(find.textContaining('did not come out'), findsNothing);
    });
  });
}

class _Gateway extends AiGateway {
  _Gateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  int garmentCalls = 0;
  int? failOnCall;
  bool failEverything = false;
  bool labelSaysNothing = false;

  @override
  Future<GarmentScanResult> scanGarment(List<ScanImage> images) async {
    garmentCalls++;
    if (failEverything || garmentCalls == failOnCall) {
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
  Future<CareTagScanResult> scanCareTag(List<ScanImage> images) async =>
      labelSaysNothing
      ? const CareTagScanResult(instructions: CareConstraint(), confidence: 0.1)
      : const CareTagScanResult(
          instructions: CareConstraint(maxTempC: 30),
          confidence: 0.93,
        );
}
