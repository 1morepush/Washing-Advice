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
import 'package:shared_preferences/shared_preferences.dart';

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

  // A real settings store. The sync section reads it while building — which is
  // correct, it needs to know whether sync is configured — and the previous
  // override threw on every read, so the section rendered as an error box in
  // the demo build and nowhere else. Making the controller tolerate a missing
  // store would have hidden a genuine wiring mistake rather than fixed one.
  //
  // On web this is backed by local storage, so a machine picked in the demo
  // survives a reload. That is what the real app does, which is the point.
  final settings = SettingsStore(await SharedPreferences.getInstance());

  runApp(
    ProviderScope(
      overrides: [
        imageStoreProvider.overrideWithValue(images),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        // Two saved outfits, one already worn a few times, so the Saved tab
        // shows what it looks like in use rather than its empty state.
        outfitRepositoryProvider.overrideWithValue(
          InMemoryOutfitRepository(_demoOutfits()),
        ),
        idGeneratorProvider.overrideWithValue(ids),
        aiGatewayProvider.overrideWithValue(_CannedGateway()),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource([
            const ScanImage(bytes: [0xFF, 0xD8, 0xFF]),
          ]),
        ),
        settingsStoreProvider.overrideWithValue(settings),
        backendUrlProvider.overrideWith((ref) => defaultBackendUrl),
        // A machine, so the plan names real programmes rather than stating
        // abstract requirements. Both paths ship; this is the interesting one.
        washerBrandProvider.overrideWith((ref) => 'Bosch'),
        dryerBrandProvider.overrideWith((ref) => 'Bosch'),
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
  Future<PileScanResult> scanPile(ScanImage image) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));

    lastDiagnostics = ScanDiagnostics(
      stagesRun: const ['knowledge-cache', 'gemini'],
      stageAnswered: 'gemini',
      elapsedMs: 1240,
    );

    // Readings of garments the demo wardrobe already holds, so the matcher
    // recognises them and the plan is built from their *stored* care rather
    // than from these crumpled-in-a-heap readings. That is the whole argument
    // for building this on a wardrobe.
    DetectedItem seen(
      ItemType type,
      String hex,
      String colourName,
      Map<Fiber, int> composition, {
      String? brand,
      required double left,
      required double top,
    }) => DetectedItem(
      scan: GarmentScanResult(
        type: Confident(type, confidence: 0.88, source: Provenance.aiInference),
        colors: Confident(
          ColorPalette([ItemColor.fromHex(hex, name: colourName)]),
          confidence: 0.84,
          source: Provenance.aiInference,
        ),
        composition: Confident(
          FabricComposition(composition),
          // Low on purpose: a garment lying twisted in a pile is a poor
          // subject, which is exactly why the wardrobe's record wins.
          confidence: 0.45,
          source: Provenance.aiInference,
        ),
        brand: brand == null
            ? null
            : Confident(brand, confidence: 0.6, source: Provenance.aiInference),
      ),
      boundingBox: BoundingBox(left: left, top: top, width: 0.3, height: 0.3),
      detectionConfidence: 0.9,
    );

    return PileScanResult(
      items: [
        seen(
          ItemType.hoodie,
          '#1F2A44',
          'Navy',
          const {Fiber.cotton: 78, Fiber.polyester: 20, Fiber.elastane: 2},
          brand: 'Nike',
          left: 0.05,
          top: 0.10,
        ),
        seen(
          ItemType.tShirt,
          '#F4F4F2',
          'White',
          const {Fiber.cotton: 100},
          brand: 'Everlane',
          left: 0.40,
          top: 0.08,
        ),
        seen(
          ItemType.jeans,
          '#2B3A55',
          'Indigo',
          const {Fiber.cotton: 98, Fiber.elastane: 2},
          left: 0.10,
          top: 0.52,
        ),
        seen(
          ItemType.sweater,
          '#3C3F44',
          'Charcoal',
          const {Fiber.wool: 100},
          left: 0.48,
          top: 0.48,
        ),
        seen(
          ItemType.dressShirt,
          '#B3322C',
          'Red',
          const {Fiber.linen: 100},
          left: 0.70,
          top: 0.20,
        ),
      ],
      // One garment visible and unidentifiable, so the screenshot shows the
      // honest "reshuffle and rescan" path rather than a tidy fiction.
      partiallyObscuredCount: 1,
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
      usage: UsageStats(
        timesWorn: 12,
        timesWashed: 4,
        lastWornAt: now.subtract(const Duration(days: 130)),
      ),
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
      usage: UsageStats(
        timesWorn: 31,
        timesWashed: 22,
        lastWornAt: now.subtract(const Duration(days: 3)),
      ),
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
      usage: UsageStats(
        timesWorn: 24,
        timesWashed: 9,
        lastWornAt: now.subtract(const Duration(days: 6)),
      ),
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
      usage: UsageStats(
        timesWorn: 46,
        timesWashed: 6,
        lastWornAt: now.subtract(const Duration(days: 4)),
      ),
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
      purchase: PurchaseInfo(
        priceMinorUnits: 12000,
        currencyCode: 'EUR',
        purchasedAt: now.subtract(const Duration(days: 8)),
      ),
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
      usage: UsageStats(
        timesWorn: 1,
        timesWashed: 0,
        lastWornAt: now.subtract(const Duration(days: 1)),
      ),
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
    build(
      id: 'demo-chinos',
      name: 'Stone chinos',
      type: ItemType.chinos,
      composition: const {Fiber.cotton: 97, Fiber.elastane: 3},
      hex: '#C9BFA8',
      colorName: 'Stone',
      brand: 'Uniqlo',
      usage: UsageStats(
        timesWorn: 18,
        timesWashed: 7,
        lastWornAt: now.subtract(const Duration(days: 11)),
      ),
      addedDaysAgo: 300,
    ),
    build(
      id: 'demo-jacket',
      name: 'Olive field jacket',
      type: ItemType.jacket,
      composition: const {Fiber.cotton: 100},
      hex: '#6B7A3A',
      colorName: 'Olive',
      usage: UsageStats(
        timesWorn: 9,
        timesWashed: 1,
        lastWornAt: now.subtract(const Duration(days: 20)),
      ),
      addedDaysAgo: 500,
    ),
    build(
      id: 'demo-sneakers',
      name: 'White trainers',
      type: ItemType.sneakers,
      composition: const {Fiber.cotton: 60, Fiber.polyester: 40},
      hex: '#EDEDE8',
      colorName: 'White',
      usage: UsageStats(
        timesWorn: 60,
        timesWashed: 1,
        lastWornAt: now.subtract(const Duration(days: 2)),
      ),
      addedDaysAgo: 420,
    ),
    for (var i = 0; i < 6; i++)
      build(
        id: 'demo-socks-$i',
        name: 'Black socks',
        type: ItemType.socks,
        composition: const {
          Fiber.cotton: 80,
          Fiber.polyester: 18,
          Fiber.elastane: 2,
        },
        hex: '#1B1B1F',
        colorName: 'Black',
        usage: UsageStats(
          timesWorn: 30 + i,
          timesWashed: 28 + i,
          lastWornAt: now.subtract(Duration(days: i + 1)),
        ),
        addedDaysAgo: 260,
      ),
    for (var i = 0; i < 6; i++)
      build(
        id: 'demo-pants-$i',
        name: 'Grey shorts',
        type: ItemType.underwear,
        composition: const {Fiber.cotton: 95, Fiber.elastane: 5},
        hex: '#5A5A60',
        colorName: 'Grey',
        usage: UsageStats(
          timesWorn: 34 + i,
          timesWashed: 33 + i,
          lastWornAt: now.subtract(Duration(days: i + 1)),
        ),
        addedDaysAgo: 260,
      ),
    build(
      id: 'demo-pyjamas',
      name: 'Striped pyjamas',
      type: ItemType.pajamas,
      composition: const {Fiber.cotton: 100},
      hex: '#8C9BB5',
      colorName: 'Faded blue',
      usage: UsageStats(
        timesWorn: 90,
        timesWashed: 40,
        lastWornAt: now.subtract(const Duration(days: 1)),
      ),
      addedDaysAgo: 700,
    ),
  ];
}

/// A couple of outfits someone would plausibly have kept.
List<Outfit> _demoOutfits() {
  final now = DateTime.now();
  return [
    Outfit(
      id: const OutfitId('demo-outfit-weekend'),
      name: 'Weekend',
      itemIds: const [
        ItemId('demo-hoodie'),
        ItemId('demo-jeans'),
        ItemId('demo-sneakers'),
      ],
      usage: UsageStats(
        timesWorn: 9,
        lastWornAt: now.subtract(const Duration(days: 4)),
      ),
      createdAt: now.subtract(const Duration(days: 90)),
      updatedAt: now.subtract(const Duration(days: 4)),
    ),
    Outfit(
      id: const OutfitId('demo-outfit-office'),
      name: 'Monday office',
      occasion: Occasion.work,
      itemIds: const [
        ItemId('demo-tee'),
        ItemId('demo-chinos'),
        ItemId('demo-jacket'),
      ],
      usage: UsageStats(
        timesWorn: 3,
        lastWornAt: now.subtract(const Duration(days: 11)),
      ),
      createdAt: now.subtract(const Duration(days: 40)),
      updatedAt: now.subtract(const Duration(days: 11)),
    ),
  ];
}
