/// Wardrobe items for widget tests.
///
/// Shared because the same three or four garments were being rebuilt in every
/// test file, and each copy drifted: one set `care` and another left it
/// unknown, which quietly changed what the sorter and the readiness figure had
/// to say about otherwise identical fixtures.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

final _now = DateTime.utc(2026, 8, 5);

/// An item whose care comes from a scanned label, so the app can act on it.
WardrobeItem confidentItem({
  required String id,
  required String name,
  ItemType type = ItemType.tShirt,
  Map<Fiber, int> composition = const {Fiber.cotton: 100},
  String hex = '#3C3F44',
  UsageStats usage = const UsageStats(timesWorn: 3),
  PurchaseInfo? purchase,
  Set<Season> seasons = const {},
  Set<String> tags = const {},
  LifecycleState lifecycle = LifecycleState.active,
}) => _base(
  id: id,
  name: name,
  type: type,
  composition: composition,
  hex: hex,
  usage: usage,
  purchase: purchase,
  seasons: seasons,
  tags: tags,
  lifecycle: lifecycle,
  care: const CareProfile(
    instructions: CareInstructions.conservative(),
    source: Provenance.tagScan,
    confidence: 0.95,
  ),
);

/// An item the app is still guessing about — one label scan away from useful.
WardrobeItem guessedItem({
  required String id,
  required String name,
  ItemType type = ItemType.tShirt,
  Map<Fiber, int> composition = const {Fiber.cotton: 100},
  String hex = '#3C3F44',
}) => _base(
  id: id,
  name: name,
  type: type,
  composition: composition,
  hex: hex,
  care: const CareProfile.unknown(),
);

WardrobeItem _base({
  required String id,
  required String name,
  required ItemType type,
  required Map<Fiber, int> composition,
  required String hex,
  required CareProfile care,
  UsageStats usage = const UsageStats(timesWorn: 3),
  PurchaseInfo? purchase,
  Set<Season> seasons = const {},
  Set<String> tags = const {},
  LifecycleState lifecycle = LifecycleState.active,
}) => WardrobeItem(
  id: ItemId(id),
  name: name,
  type: Confident(type, confidence: 0.95, source: Provenance.aiInference),
  composition: Confident(
    FabricComposition(composition),
    confidence: 0.95,
    source: Provenance.tagScan,
  ),
  colors: Confident(
    ColorPalette([ItemColor.fromHex(hex)]),
    confidence: 0.9,
    source: Provenance.aiInference,
  ),
  care: care,
  usage: usage,
  purchase: purchase,
  seasons: seasons,
  tags: tags,
  lifecycle: lifecycle,
  addedAt: _now,
  updatedAt: _now,
);
