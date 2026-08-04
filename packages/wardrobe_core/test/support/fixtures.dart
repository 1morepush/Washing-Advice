/// Builders for readable tests.
///
/// A [WardrobeItem] has a lot of fields, and spelling them all out in every
/// test buries the one detail that matters. These helpers default everything
/// sensibly so a test can say "a white cotton t-shirt" and nothing else.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

/// A fixed instant, so date assertions are exact.
final testNow = DateTime.utc(2026, 3, 15, 10, 30);

/// Common colours, as they would be perceived from a photo.
abstract final class Colors {
  static ItemColor get white => ItemColor.fromHex('#FAFAFA', name: 'White');
  static ItemColor get offWhite => ItemColor.fromHex('#F0EDE5', name: 'Cream');
  static ItemColor get black => ItemColor.fromHex('#1A1A1A', name: 'Black');
  static ItemColor get navy => ItemColor.fromHex('#1F2A44', name: 'Navy');
  static ItemColor get charcoal =>
      ItemColor.fromHex('#3B3B3B', name: 'Charcoal');
  static ItemColor get grey => ItemColor.fromHex('#9A9A9A', name: 'Grey');
  static ItemColor get red => ItemColor.fromHex('#C81E1E', name: 'Red');
  static ItemColor get royalBlue => ItemColor.fromHex('#1E45C8', name: 'Blue');
  static ItemColor get pastelPink => ItemColor.fromHex('#F2C6D0', name: 'Pink');
  static ItemColor get khaki => ItemColor.fromHex('#C3B091', name: 'Khaki');
}

/// Builds a [WardrobeItem] with sensible defaults.
///
/// Every parameter is optional; supply only what the test is actually about.
WardrobeItem buildItem({
  String id = 'item-1',
  String? name,
  ItemType type = ItemType.tShirt,
  Map<Fiber, int> composition = const {Fiber.cotton: 100},
  List<ItemColor>? colors,
  String? brand,
  Pattern? pattern,
  CareProfile? care,
  CareInstructions? careInstructions,
  Provenance careSource = Provenance.tagScan,
  double careConfidence = 0.95,
  LifecycleState lifecycle = LifecycleState.active,
  ConditionAssessment? condition,
  UsageStats usage = const UsageStats(timesWashed: 10, timesWorn: 20),
  PurchaseInfo? purchase,
  String? sizeLabel,
  String? distinguishingText,
  bool isFavorite = false,
}) {
  final palette = ColorPalette(colors ?? [Colors.grey]);
  return WardrobeItem(
    id: ItemId(id),
    name: name ?? '${palette.dominant?.name ?? "Plain"} ${type.label}',
    type: Confident(type, confidence: 0.95, source: Provenance.aiInference),
    composition: Confident(
      FabricComposition(composition),
      confidence: 0.9,
      source: Provenance.tagScan,
    ),
    colors: Confident(
      palette,
      confidence: 0.9,
      source: Provenance.aiInference,
    ),
    brand: brand == null ? null : Confident.fromUser(brand),
    pattern: pattern == null
        ? null
        : Confident(pattern, confidence: 0.8, source: Provenance.aiInference),
    care: care ??
        CareProfile(
          instructions: careInstructions ?? cottonCare,
          source: careSource,
          confidence: careConfidence,
        ),
    lifecycle: lifecycle,
    condition: condition ?? ConditionAssessment.pristine,
    usage: usage,
    purchase: purchase,
    sizeLabel: sizeLabel,
    distinguishingText: distinguishingText,
    isFavorite: isFavorite,
    addedAt: testNow,
    updatedAt: testNow,
  );
}

/// Ordinary cotton: warm machine wash, tumble dry medium.
const cottonCare = CareInstructions(
  wash: WashCare(method: WashMethod.machine, maxTempC: 40),
  bleach: BleachAllowance.nonChlorineOnly,
  dry: DryCare(
    tumbleDryAllowed: true,
    tumbleDryHeat: TumbleDryHeat.medium,
  ),
  iron: IronCare(temperature: IronTemperature.high),
  professional: ProfessionalCare.unspecified(),
);

/// A robust cycle for denim and towels.
const heavyCare = CareInstructions(
  wash: WashCare(method: WashMethod.machine, maxTempC: 60),
  bleach: BleachAllowance.any,
  dry: DryCare(tumbleDryAllowed: true, tumbleDryHeat: TumbleDryHeat.high),
  iron: IronCare(temperature: IronTemperature.high),
  professional: ProfessionalCare.unspecified(),
);

/// Cold, gentle, no dryer.
const delicateCare = CareInstructions(
  wash: WashCare(
    method: WashMethod.machine,
    maxTempC: 30,
    agitation: Agitation.veryMild,
  ),
  bleach: BleachAllowance.none,
  dry: DryCare(
    tumbleDryAllowed: false,
    tumbleDryHeat: TumbleDryHeat.noHeat,
    naturalDry: NaturalDryMethod.flatDry,
  ),
  iron: IronCare(temperature: IronTemperature.low, steamAllowed: false),
  professional: ProfessionalCare.unspecified(),
);

/// Hand wash only.
const handWashCare = CareInstructions(
  wash: WashCare(
    method: WashMethod.hand,
    maxTempC: 30,
    agitation: Agitation.veryMild,
  ),
  bleach: BleachAllowance.none,
  dry: DryCare(
    tumbleDryAllowed: false,
    tumbleDryHeat: TumbleDryHeat.noHeat,
    naturalDry: NaturalDryMethod.flatDry,
    doNotWring: true,
  ),
  iron: IronCare(temperature: IronTemperature.low, steamAllowed: false),
  professional: ProfessionalCare.unspecified(),
);

/// Facts for rule-table tests.
ItemFacts buildFacts({
  ItemType type = ItemType.tShirt,
  Map<Fiber, int> composition = const {Fiber.cotton: 100},
  List<ItemColor>? colors,
  ConditionGrade condition = ConditionGrade.pristine,
  int timesWashed = 10,
}) =>
    ItemFacts(
      type: type,
      composition: FabricComposition(composition),
      colors: colors == null ? null : ColorPalette(colors),
      conditionGrade: condition,
      timesWashed: timesWashed,
    );

/// A wear event, for projection tests.
ItemWorn wornEvent(String itemId, DateTime at, {String? id}) => ItemWorn(
      id: EventId(id ?? 'worn-${at.microsecondsSinceEpoch}'),
      itemId: ItemId(itemId),
      occurredAt: at,
    );

/// A wash event, for projection tests.
ItemWashed washedEvent(
  String itemId,
  DateTime at, {
  String? id,
  int? temperatureC,
  String? programName,
}) =>
    ItemWashed(
      id: EventId(id ?? 'washed-${at.microsecondsSinceEpoch}'),
      itemId: ItemId(itemId),
      occurredAt: at,
      record: LaundryRecord(
        washedAt: at,
        temperatureC: temperatureC,
        programName: programName,
      ),
    );
