/// Scanning a pile into a plan, end to end without a camera or a server.
///
/// The behaviour worth pinning is not "a plan comes back". It is that
/// recognising a garment brings its **stored care profile** into the plan
/// instead of what a photograph of a crumpled sleeve suggested — which is the
/// entire reason this is built on a wardrobe rather than as a standalone
/// "photograph your laundry" tool.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/features/pile/pile_controller.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late _FakeGateway gateway;
  late ProviderContainer container;

  /// Builds the graph the pile flow needs.
  ///
  /// The machine brands are overridden rather than left to resolve, because
  /// unoverridden they read the settings store — which `main()` is required to
  /// provide and a test is not. Stating the machine explicitly also makes each
  /// test say which one it assumes, rather than inheriting whatever the last
  /// one set.
  ProviderContainer build({
    String? washer,
    List<ScanImage> captured = const [ScanImage(bytes: [1, 2, 3])],
  }) => ProviderContainer(
    overrides: [
      wardrobeRepositoryProvider.overrideWithValue(repository),
      aiGatewayProvider.overrideWithValue(gateway),
      idGeneratorProvider.overrideWithValue(
        SequentialIdGenerator(prefix: 'pile'),
      ),
      imageCaptureProvider.overrideWithValue(
        FixedImageCaptureSource(captured),
      ),
      washerBrandProvider.overrideWith((ref) => washer),
      dryerBrandProvider.overrideWith((ref) => null),
    ],
  );

  setUp(() {
    repository = InMemoryWardrobeRepository();
    gateway = _FakeGateway();
    container = build();
  });

  tearDown(() => container.dispose());

  PileController controller() =>
      container.read(pileControllerProvider.notifier);

  PileState state() => container.read(pileControllerProvider);

  test('garments the app is only guessing at are not sorted', () async {
    // Not a limitation — the thesis, enforced at the last possible step.
    // `LaundrySorter` refuses to place an item whose care rests on a guess,
    // and a garment seen once in a heap is exactly that. Sorting it anyway
    // would put a 60°C cotton cycle under something that might be wool.
    await controller().captureAndPlan();

    final planned = state() as PilePlanned;
    expect(planned.plan.loads, isEmpty);
    expect(planned.plan.unassigned, hasLength(3));
    // And every one of them is fixable by the user, which is what makes the
    // refusal useful rather than merely safe.
    expect(planned.plan.actionable, hasLength(3));
  });

  test('a wardrobe garment is sorted, because its care is known', () async {
    // The payoff for cataloguing: the same photograph produces a real load
    // once the app knows what the garment is.
    await repository.save(_hoodie());

    await controller().captureAndPlan();
    final planned = state() as PilePlanned;

    expect(planned.plan.loads, hasLength(1));
    expect(planned.plan.itemsSorted, 1);
    expect(planned.plan.loads.single.items.single.id.value, 'hoodie');
  });

  test('a garment already owned is recognised, not treated as new', () async {
    await repository.save(_hoodie());

    await controller().captureAndPlan();
    final planned = state() as PilePlanned;

    expect(planned.recognisedCount, 1);
    expect(planned.unrecognisedCount, 2);
  });

  test('a recognised garment brings its scanned care label with it', () async {
    // The point of the whole feature. The pile photo shows a crumpled hoodie
    // and says nothing about washing it; the wardrobe knows its label permits
    // 40° because that label was scanned properly, once, months ago.
    await repository.save(
      _hoodie().copyWith(
        careLabel: Confident(
          const CareConstraint(
            method: WashMethod.machine,
            maxTempC: 40,
            tumbleDryAllowed: true,
            tumbleDryHeat: TumbleDryHeat.low,
          ),
          confidence: 0.95,
          source: Provenance.tagScan,
        ),
        care: const CareProfile(
          instructions: CareInstructions(
            wash: WashCare(method: WashMethod.machine, maxTempC: 40),
            bleach: BleachAllowance.none,
            dry: DryCare(
              tumbleDryAllowed: true,
              tumbleDryHeat: TumbleDryHeat.low,
            ),
            iron: IronCare(temperature: IronTemperature.medium),
            professional: ProfessionalCare.unspecified(),
          ),
          source: Provenance.tagScan,
          confidence: 0.95,
        ),
      ),
    );

    await controller().captureAndPlan();
    final planned = state() as PilePlanned;

    final recognised = planned.detections.firstWhere((d) => d.isRecognised);
    expect(recognised.item.care.source, Provenance.tagScan);
    expect(recognised.item.effectiveCare.wash.maxTempC, 40);
  });

  test('two detections cannot claim the same wardrobe item', () async {
    // A heap with two near-identical garments must not plan one and wash two.
    await repository.save(_hoodie());
    gateway.result = PileScanResult(
      items: [_detection(_hoodieScan()), _detection(_hoodieScan())],
    );

    await controller().captureAndPlan();
    final planned = state() as PilePlanned;

    final ids = [for (final d in planned.detections) d.item.id.value];
    expect(ids.toSet(), hasLength(2));
  });

  test('an unrecognised garment is accounted for, not dropped', () async {
    // It does not reach a load, but it does reach the plan — with a reason.
    // An item silently missing is one the user finds still dirty later.
    await controller().captureAndPlan();
    final planned = state() as PilePlanned;

    expect(planned.unrecognisedCount, 3);
    expect(
      planned.plan.unassigned.map((u) => u.reason),
      everyElement(contains('care label')),
    );
  });

  test('buried garments are reported rather than ignored', () async {
    gateway.result = PileScanResult(
      items: [_detection(_hoodieScan())],
      partiallyObscuredCount: 2,
    );

    await controller().captureAndPlan();
    expect((state() as PilePlanned).obscuredCount, 2);
  });

  test('an empty pile is a failure with something to act on', () async {
    gateway.result = const PileScanResult(items: []);

    await controller().captureAndPlan();

    expect(state(), isA<PileFailed>());
    expect((state() as PileFailed).message, contains('No clothes'));
  });

  test('nothing identifiable but things visible says so differently', () async {
    // Distinct from an empty frame: there *are* clothes, and the fix is to
    // spread them out rather than to point the camera somewhere else.
    gateway.result = const PileScanResult(
      items: [],
      partiallyObscuredCount: 4,
    );

    await controller().captureAndPlan();
    expect((state() as PileFailed).message, contains('Spread'));
  });

  test('without a machine the plan still states requirements', () async {
    await repository.save(_hoodie());

    await controller().captureAndPlan();
    final load = (state() as PilePlanned).plan.loads.first;

    expect(load.washerSetting, isNull);
    // The abstract requirement survives, which is what the card falls back to.
    expect(load.washSpec.method, isNotNull);
  });

  test('with a machine the plan names a programme', () async {
    await repository.save(_hoodie());
    container.dispose();
    container = build(washer: 'Bosch');

    await controller().captureAndPlan();
    final load = (state() as PilePlanned).plan.loads.first;

    expect(load.washerSetting, isNotNull);
    expect(load.washerSetting!.programName, isNotEmpty);
  });

  test('backing out of the camera is not an error', () async {
    container.dispose();
    container = build(captured: const []);

    await controller().captureAndPlan();
    expect(state(), isA<PileIdle>());
  });
}

// --- Fixtures ---------------------------------------------------------------

GarmentScanResult _hoodieScan() => GarmentScanResult(
  type: Confident(
    ItemType.hoodie,
    confidence: 0.93,
    source: Provenance.aiInference,
  ),
  colors: Confident(
    ColorPalette([ItemColor.fromHex('#1F2A44', name: 'Navy')]),
    confidence: 0.9,
    source: Provenance.aiInference,
  ),
  composition: Confident(
    FabricComposition(const {Fiber.cotton: 80, Fiber.polyester: 20}),
    confidence: 0.55,
    source: Provenance.aiInference,
  ),
  brand: Confident('Nike', confidence: 0.8, source: Provenance.aiInference),
  suggestedName: 'Navy Nike hoodie',
);

GarmentScanResult _scan(ItemType type, String hex, String name) =>
    GarmentScanResult(
      type: Confident(type, confidence: 0.9, source: Provenance.aiInference),
      colors: Confident(
        ColorPalette([ItemColor.fromHex(hex, name: name)]),
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      composition: Confident(
        FabricComposition(const {Fiber.cotton: 100}),
        confidence: 0.6,
        source: Provenance.aiInference,
      ),
    );

DetectedItem _detection(GarmentScanResult scan) => DetectedItem(
  scan: scan,
  boundingBox: const BoundingBox(left: 0.1, top: 0.1, width: 0.3, height: 0.3),
  detectionConfidence: 0.9,
);

WardrobeItem _hoodie() {
  final now = DateTime.utc(2026, 8, 5);
  final item = WardrobeItem(
    id: const ItemId('hoodie'),
    name: 'Navy Nike hoodie',
    type: Confident(
      ItemType.hoodie,
      confidence: 0.95,
      source: Provenance.aiInference,
    ),
    composition: Confident(
      FabricComposition(const {Fiber.cotton: 80, Fiber.polyester: 20}),
      confidence: 0.95,
      source: Provenance.tagScan,
    ),
    colors: Confident(
      ColorPalette([ItemColor.fromHex('#1F2A44', name: 'Navy')]),
      confidence: 0.95,
      source: Provenance.aiInference,
    ),
    brand: Confident.fromUser('Nike'),
    care: const CareProfile.unknown(),
    addedAt: now,
    updatedAt: now,
  );

  // Resolved, the way the scan flow resolves it before saving. An item stored
  // with `CareProfile.unknown()` is not something the app ever produces, and a
  // fixture that carried one would be testing a state that cannot occur.
  return item.copyWith(care: const CareResolver().forItem(item).profile);
}

class _FakeGateway extends AiGateway {
  _FakeGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  PileScanResult? result;

  @override
  Future<PileScanResult> scanPile(ScanImage image) async =>
      result ??
      PileScanResult(
        items: [
          _detection(_hoodieScan()),
          _detection(_scan(ItemType.tShirt, '#F4F4F2', 'White')),
          _detection(_scan(ItemType.jeans, '#2B3A55', 'Indigo')),
        ],
      );
}
