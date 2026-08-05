/// A seeded build of the app, for screenshots and for trying it without a
/// backend.
///
/// Every dependency that would reach outside the process is overridden: an
/// in-memory wardrobe instead of SQLite, prepared bytes instead of a camera,
/// and a canned scan instead of the server. Nothing else changes — the screens,
/// the state machine, the care resolution and the confidence rendering are the
/// ones that ship.
///
/// That is the payoff of putting every boundary behind an interface. The
/// screenshots in the README are of the real app, not a mock-up of it.
///
/// Run with: `flutter run -t lib/main_demo.dart -d chrome`
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'data/api/ai_gateway.dart';
import 'data/api/scan_dto.dart';
import 'data/capture/image_capture_source.dart';
import 'data/images/memory_image_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = InMemoryWardrobeRepository();
  final ids = SequentialIdGenerator(prefix: 'demo');
  final images = MemoryImageStore();

  // Awaited, so the wardrobe stream's first emission already has the seed in
  // it. Without this the list subscribes to an empty repository and the app
  // opens on the empty state before flicking to the real one.
  await repository.saveAll(await _withCutouts(_seed(), images));

  runApp(
    ProviderScope(
      overrides: [
        imageStoreProvider.overrideWithValue(images),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        idGeneratorProvider.overrideWithValue(ids),
        aiGatewayProvider.overrideWithValue(_CannedGateway()),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource([
            const ScanImage(bytes: [0xFF, 0xD8, 0xFF]),
          ]),
        ),
        // The settings screen writes here. Nothing in a demo build should
        // persist, so it is given a store that reads the default and is never
        // asked to save.
        settingsStoreProvider.overrideWith(
          (ref) => throw UnsupportedError('settings are disabled in the demo'),
        ),
        backendUrlProvider.overrideWith((ref) => defaultBackendUrl),
      ],
      child: const _DemoApp(),
    ),
  );
}

class _DemoApp extends StatelessWidget {
  const _DemoApp();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Washing Advice',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    routerConfig: buildRouter(),
  );
}

/// Attaches the prepared cutouts to the seeded items.
///
/// The shapes behind these were drawn rather than photographed — there are no
/// garments in a build container — but the *cutouts* were produced by running
/// the shipping `BorderSampledRemover` over those drawings. What the wardrobe
/// list shows is this project's actual background removal, not an illustration
/// of it. See `server/tools/make_demo_cutouts.py`.
Future<List<WardrobeItem>> _withCutouts(
  List<WardrobeItem> items,
  MemoryImageStore images,
) async {
  final Map<String, Object?> encoded =
      jsonDecode(await rootBundle.loadString('assets/demo/cutouts.json'))
          as Map<String, Object?>;

  final now = DateTime(2026, 8, 5, 9);

  return [
    for (final item in items)
      if (encoded[item.id.value] case final String base64Png)
        item.copyWith(
          photos: PhotoSet([
            ItemPhoto(
              // The source photograph would sit here on a real device. The
              // demo has only the cutout, so both point at it — which is also
              // what a rescan of a lost original would leave behind.
              uri: await images.save(
                base64Decode(base64Png),
                name: '${item.id.value}-front',
              ),
              cutoutUri: await images.save(
                base64Decode(base64Png),
                name: '${item.id.value}-front-cutout',
              ),
              role: PhotoRole.front,
              capturedAt: now,
            ),
          ]),
        )
      else
        item,
  ];
}

/// Answers a scan without a server.
class _CannedGateway extends AiGateway {
  _CannedGateway() : super(baseUrl: Uri.parse('http://demo.invalid/'));

  @override
  Future<GarmentScanResult> scanGarment(List<ScanImage> images) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));

    lastDiagnostics = ScanDiagnostics(
      stagesRun: const ['knowledge-cache', 'gemini'],
      stageAnswered: 'gemini',
      elapsedMs: 486,
    );

    return GarmentScanResult(
      type: Confident(
        ItemType.sweater,
        confidence: 0.93,
        source: Provenance.aiInference,
      ),
      colors: Confident(
        ColorPalette([ItemColor.fromHex('#6E7B8B', name: 'Slate')]),
        confidence: 0.89,
        source: Provenance.aiInference,
      ),
      // Deliberately mid-confidence. This is the case the review screen exists
      // for: the fabric drives the care, and the model is not sure of it.
      composition: Confident(
        FabricComposition(const {Fiber.wool: 70, Fiber.polyester: 30}),
        confidence: 0.58,
        source: Provenance.aiInference,
      ),
      brand: Confident(
        'Uniqlo',
        confidence: 0.71,
        source: Provenance.aiInference,
      ),
      suggestedName: 'Slate wool jumper',
    );
  }

  @override
  Future<Uint8List?> cutout(ScanImage image) async {
    // The demo's capture source hands back three bytes, which no remover could
    // separate. Returning null exercises the honest path: the item saves and
    // the row falls back to its colour swatch.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return null;
  }

  @override
  Future<CareTagScanResult> scanCareTag(ScanImage image) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));

    // A superwash label: it permits things the generic wool rule forbids, which
    // is the case the review screen exists to surface.
    return CareTagScanResult(
      instructions: const CareConstraint(
        method: WashMethod.machine,
        maxTempC: 40,
        agitation: Agitation.mild,
        tumbleDryAllowed: true,
        tumbleDryHeat: TumbleDryHeat.low,
        ironTemperature: IronTemperature.low,
      ),
      confidence: 0.91,
      composition: Confident(
        FabricComposition(const {Fiber.wool: 80, Fiber.nylon: 20}),
        confidence: 0.94,
        source: Provenance.tagScan,
      ),
      symbolsFound: const ['wash_40', 'tumble_low', 'iron_low', 'no_bleach'],
      unreadableSymbolCount: 1,
    );
  }
}

/// A small wardrobe covering the cases the UI has to handle.
///
/// Chosen so the screenshots show real behaviour rather than a uniform list:
/// something with a scanned label and something without, a garment that needs
/// its label read, a favourite, a never-worn item and a bleeding red.
List<WardrobeItem> _seed() {
  final now = DateTime(2026, 8, 5, 9);

  WardrobeItem build({
    required String id,
    required String name,
    required ItemType type,
    required Map<Fiber, int> composition,
    required String hex,
    required String colorName,
    String? brand,
    double typeConfidence = 0.94,
    double compositionConfidence = 0.9,
    Provenance compositionSource = Provenance.tagScan,
    CareProfile? care,
    Confident<CareConstraint>? careLabel,
    UsageStats usage = const UsageStats.none(),
    bool isFavorite = false,
    int addedDaysAgo = 0,
    PurchaseInfo? purchase,
  }) {
    final item = WardrobeItem(
      id: ItemId(id),
      name: name,
      type: Confident(
        type,
        confidence: typeConfidence,
        source: Provenance.aiInference,
      ),
      composition: Confident(
        FabricComposition(composition),
        confidence: compositionConfidence,
        source: compositionSource,
      ),
      colors: Confident(
        ColorPalette([ItemColor.fromHex(hex, name: colorName)]),
        confidence: 0.91,
        source: Provenance.aiInference,
      ),
      brand: brand == null ? null : Confident.fromUser(brand),
      careLabel: careLabel,
      care: const CareProfile.unknown(),
      usage: usage,
      isFavorite: isFavorite,
      purchase: purchase,
      addedAt: now.subtract(Duration(days: addedDaysAgo)),
      updatedAt: now,
    );

    // Care is resolved the same way the scan flow resolves it, so the demo
    // shows what the rule table actually concludes rather than hand-written
    // instructions that could quietly disagree with it.
    return item.copyWith(
      care: care ?? const CareResolver().forItem(item).profile,
    );
  }

  return [
    build(
      id: 'demo-jumper',
      name: 'Charcoal merino jumper',
      type: ItemType.sweater,
      composition: const {Fiber.wool: 100},
      hex: '#3C3F44',
      colorName: 'Charcoal',
      brand: 'Uniqlo',
      // Read from a photo, not a label — so this one asks to be scanned.
      compositionSource: Provenance.aiInference,
      compositionConfidence: 0.61,
      usage: const UsageStats(timesWorn: 12, timesWashed: 4),
      addedDaysAgo: 40,
      purchase: PurchaseInfo(
        priceMinorUnits: 5990,
        currencyCode: 'EUR',
        purchasedAt: now.subtract(const Duration(days: 400)),
      ),
    ),
    build(
      id: 'demo-tee',
      name: 'White cotton tee',
      type: ItemType.tShirt,
      composition: const {Fiber.cotton: 100},
      hex: '#F4F4F2',
      colorName: 'White',
      brand: 'Everlane',
      // Its label has been read, so this one is advice from the manufacturer
      // rather than from a rule — and the app stops asking to scan it.
      careLabel: Confident(
        const CareConstraint(
          method: WashMethod.machine,
          maxTempC: 40,
          agitation: Agitation.normal,
          tumbleDryAllowed: true,
          tumbleDryHeat: TumbleDryHeat.medium,
        ),
        confidence: 0.95,
        source: Provenance.tagScan,
      ),
      usage: const UsageStats(timesWorn: 31, timesWashed: 22),
      addedDaysAgo: 120,
    ),
    build(
      id: 'demo-hoodie',
      name: 'Navy Nike hoodie',
      type: ItemType.hoodie,
      composition: const {
        Fiber.cotton: 78,
        Fiber.polyester: 20,
        Fiber.elastane: 2,
      },
      hex: '#1F2A44',
      colorName: 'Navy',
      brand: 'Nike',
      isFavorite: true,
      usage: const UsageStats(timesWorn: 24, timesWashed: 9),
      addedDaysAgo: 15,
    ),
    build(
      id: 'demo-jeans',
      name: 'Selvedge jeans',
      type: ItemType.jeans,
      composition: const {Fiber.cotton: 98, Fiber.elastane: 2},
      hex: '#2B3A55',
      colorName: 'Indigo',
      brand: "Levi's",
      usage: const UsageStats(timesWorn: 46, timesWashed: 6),
      addedDaysAgo: 200,
    ),
    build(
      id: 'demo-silk',
      name: 'Cream silk blouse',
      type: ItemType.blouse,
      composition: const {Fiber.silk: 100},
      hex: '#EFE3CE',
      colorName: 'Cream',
      addedDaysAgo: 8,
    ),
    build(
      id: 'demo-red',
      name: 'Red linen shirt',
      type: ItemType.dressShirt,
      composition: const {Fiber.linen: 100},
      hex: '#B3322C',
      colorName: 'Red',
      brand: 'Uniqlo',
      // New and saturated, so the app isolates it from a shared load.
      usage: const UsageStats(timesWorn: 1, timesWashed: 0),
      addedDaysAgo: 2,
    ),
    build(
      id: 'demo-towel',
      name: 'Bath towel',
      type: ItemType.bathTowel,
      composition: const {Fiber.cotton: 100},
      hex: '#8FB3C7',
      colorName: 'Pale blue',
      usage: const UsageStats(timesWorn: 0, timesWashed: 3),
      addedDaysAgo: 60,
    ),
  ];
}
