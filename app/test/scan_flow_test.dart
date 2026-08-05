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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/api/scan_dto.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/features/scan/scan_controller.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late _FakeGateway gateway;
  late ProviderContainer container;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    gateway = _FakeGateway();
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        aiGatewayProvider.overrideWithValue(gateway),
        idGeneratorProvider
            .overrideWithValue(SequentialIdGenerator(prefix: 'scan')),
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

  test('a capture runs through to a saved item', () async {
    await controller().captureAndScan();

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
    await controller().captureAndScan();
    final draft = (container.read(scanControllerProvider) as ScanReviewing).draft;

    // The fake returns a wool jumper. Nothing in the response mentions washing,
    // so a care profile at all is proof the rule table ran — and it must be the
    // rules' provenance, not the photo's, or the app would be presenting a
    // guess with a derivation's authority.
    expect(draft.care.source, Provenance.careRule);
    expect(draft.effectiveCare.wash.maxTempC, lessThanOrEqualTo(30));
    expect(draft.effectiveCare.dry.tumbleDryAllowed, isFalse);
  });

  test('a wool garment still asks for its care label', () async {
    await controller().captureAndScan();
    final draft = (container.read(scanControllerProvider) as ScanReviewing).draft;

    // A rule-derived profile is a good default and not a manufacturer's word.
    // Superwash wool exists, and the label is the only way to know.
    expect(draft.needsCareTagScan, isTrue);
  });

  test('backing out of the camera is not an error', () async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        aiGatewayProvider.overrideWithValue(gateway),
        imageCaptureProvider.overrideWithValue(FixedImageCaptureSource([])),
      ],
    );

    await controller().captureAndScan();

    expect(container.read(scanControllerProvider), isA<ScanIdle>());
  });

  test('an unreadable photo is not offered as retryable', () async {
    gateway.failure = const ScanFailure(
      'That photo could not be read.',
      isRetryable: false,
    );

    await controller().captureAndScan();

    final state = container.read(scanControllerProvider);
    expect(state, isA<ScanError>());
    expect((state as ScanError).isRetryable, isFalse);
  });

  test('saving records an event, so the history is replayable', () async {
    await controller().captureAndScan();
    await controller().save();

    final events = await container.read(eventLogProvider).all();
    expect(events, hasLength(1));
    expect(events.single, isA<ItemAdded>());
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

  @override
  Future<GarmentScanResult> scanGarment(List<ScanImage> images) async {
    if (failure case final ScanFailure failure) throw failure;

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
