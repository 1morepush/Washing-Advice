/// What kind of thing an item is, and the descriptive attributes that follow.
///
/// Modelled as [ItemKind] + [ItemType] rather than a flat "garment type" so the
/// wardrobe can hold shoes, bags and bed linen without reshaping the schema
/// later. Laundry-relevant physical facts — typical weight, bulk, whether it
/// sheds lint — live on the type itself, because that is knowledge about the
/// world rather than about any one user's shirt.
library;

import 'fabric.dart';

/// The broad class of possession.
enum ItemKind {
  garment('Clothing'),
  footwear('Footwear'),
  bag('Bags'),
  accessory('Accessories'),
  jewelry('Jewelry'),
  linen('Household linen');

  const ItemKind(this.label);

  final String label;
}

/// Where an item sits in the wardrobe, for browsing and outfit building.
enum ItemCategory {
  top('Tops'),
  bottom('Bottoms'),
  outerwear('Outerwear'),
  fullBody('Full body'),
  underwear('Underwear'),
  legwear('Legwear'),
  sleepwear('Sleepwear'),
  activewear('Activewear'),
  swimwear('Swimwear'),
  footwear('Footwear'),
  accessory('Accessories'),
  household('Household');

  const ItemCategory(this.label);

  final String label;
}

/// A specific type of item, carrying the physical facts the laundry engine
/// needs.
///
/// [typicalWeightGrams] is a dry-weight estimate used to fill a drum to its
/// rated capacity. [bulkFactor] captures that a duvet fills far more drum than
/// its weight suggests, which matters because an overpacked machine simply does
/// not clean.
enum ItemType {
  // Tops
  tShirt('T-shirt', ItemCategory.top, weight: 150),
  longSleeveShirt('Long-sleeve shirt', ItemCategory.top, weight: 220),
  dressShirt('Dress shirt', ItemCategory.top, weight: 200),
  poloShirt('Polo shirt', ItemCategory.top, weight: 200),
  blouse('Blouse', ItemCategory.top, weight: 150),
  tankTop('Tank top', ItemCategory.top, weight: 100),
  sweater('Sweater', ItemCategory.top, weight: 400, bulk: 1.3),
  cardigan('Cardigan', ItemCategory.top, weight: 400, bulk: 1.3),
  hoodie('Hoodie', ItemCategory.top,
      weight: 550, bulk: 1.4, attractsLint: true),
  sweatshirt('Sweatshirt', ItemCategory.top, weight: 500, bulk: 1.3),

  // Bottoms
  jeans(
    'Jeans',
    ItemCategory.bottom,
    weight: 650,
    bulk: 1.2,
    construction: FabricClass.heavy,
  ),
  trousers('Trousers', ItemCategory.bottom, weight: 450),
  chinos('Chinos', ItemCategory.bottom, weight: 500),
  shorts('Shorts', ItemCategory.bottom, weight: 250),
  skirt('Skirt', ItemCategory.bottom, weight: 250),
  leggings('Leggings', ItemCategory.bottom, weight: 180),

  // Full body
  dress('Dress', ItemCategory.fullBody, weight: 350),
  jumpsuit('Jumpsuit', ItemCategory.fullBody, weight: 450),

  // Outerwear
  jacket('Jacket', ItemCategory.outerwear, weight: 800, bulk: 1.5),
  blazer('Blazer', ItemCategory.outerwear, weight: 600, bulk: 1.3),
  coat(
    'Coat',
    ItemCategory.outerwear,
    weight: 1400,
    bulk: 2.0,
    construction: FabricClass.heavy,
  ),
  vest('Vest', ItemCategory.outerwear, weight: 400, bulk: 1.2),

  // Underwear and legwear
  underwear('Underwear', ItemCategory.underwear, weight: 50),
  bra('Bra', ItemCategory.underwear, weight: 80),
  socks('Socks', ItemCategory.legwear, weight: 50, producesLint: true),
  tights('Tights', ItemCategory.legwear, weight: 80),

  // Sleep, active, swim
  pajamas('Pajamas', ItemCategory.sleepwear, weight: 350),
  robe(
    'Robe',
    ItemCategory.sleepwear,
    weight: 700,
    bulk: 1.4,
    producesLint: true,
    construction: FabricClass.heavy,
  ),
  activewearTop('Activewear top', ItemCategory.activewear, weight: 150),
  activewearBottom('Activewear bottom', ItemCategory.activewear, weight: 200),
  swimwear('Swimwear', ItemCategory.swimwear, weight: 120),

  // Accessories
  scarf('Scarf', ItemCategory.accessory, weight: 150, kind: ItemKind.accessory),
  hat('Hat', ItemCategory.accessory, weight: 100, kind: ItemKind.accessory),
  gloves('Gloves', ItemCategory.accessory,
      weight: 80, kind: ItemKind.accessory),
  belt('Belt', ItemCategory.accessory, weight: 200, kind: ItemKind.accessory),
  tie('Tie', ItemCategory.accessory, weight: 60, kind: ItemKind.accessory),

  // Footwear and bags
  sneakers('Sneakers', ItemCategory.footwear,
      weight: 800, bulk: 2.0, kind: ItemKind.footwear),
  boots('Boots', ItemCategory.footwear,
      weight: 1200, bulk: 2.5, kind: ItemKind.footwear),
  dressShoes('Dress shoes', ItemCategory.footwear,
      weight: 900, bulk: 2.0, kind: ItemKind.footwear),
  sandals('Sandals', ItemCategory.footwear,
      weight: 400, bulk: 1.5, kind: ItemKind.footwear),
  handbag('Handbag', ItemCategory.accessory,
      weight: 700, bulk: 2.0, kind: ItemKind.bag),
  backpack('Backpack', ItemCategory.accessory,
      weight: 900, bulk: 2.5, kind: ItemKind.bag),

  // Household linen
  handTowel(
    'Hand towel',
    ItemCategory.household,
    weight: 200,
    kind: ItemKind.linen,
    producesLint: true,
    construction: FabricClass.heavy,
  ),
  bathTowel(
    'Bath towel',
    ItemCategory.household,
    weight: 700,
    bulk: 1.3,
    kind: ItemKind.linen,
    producesLint: true,
    construction: FabricClass.heavy,
  ),
  bedSheet(
    'Bed sheet',
    ItemCategory.household,
    weight: 800,
    bulk: 1.4,
    kind: ItemKind.linen,
  ),
  pillowcase(
    'Pillowcase',
    ItemCategory.household,
    weight: 150,
    kind: ItemKind.linen,
  ),
  duvetCover(
    'Duvet cover',
    ItemCategory.household,
    weight: 1500,
    bulk: 2.2,
    kind: ItemKind.linen,
    construction: FabricClass.heavy,
  ),
  blanket(
    'Blanket',
    ItemCategory.household,
    weight: 2000,
    bulk: 2.5,
    kind: ItemKind.linen,
    producesLint: true,
    construction: FabricClass.heavy,
  ),

  other('Other', ItemCategory.accessory, weight: 300);

  const ItemType(
    this.label,
    this.category, {
    required int weight,
    double bulk = 1.0,
    this.kind = ItemKind.garment,
    this.producesLint = false,
    this.attractsLint = false,
    this.construction = FabricClass.normal,
  })  : typicalWeightGrams = weight,
        bulkFactor = bulk;

  final String label;
  final ItemCategory category;
  final ItemKind kind;

  /// How robust the garment is by virtue of how it is *made*, independent of
  /// what it is made of.
  ///
  /// Denim and terry towelling are heavy because of their weave, not their
  /// fibre — both are cotton, which on its own is unremarkable. Without this,
  /// a pair of jeans is classified identically to a cotton t-shirt and the
  /// sorter happily puts them in with silk.
  final FabricClass construction;

  /// Dry weight estimate in grams, for filling a drum to its rated capacity.
  final int typicalWeightGrams;

  /// How much more drum space this occupies than its weight implies.
  final double bulkFactor;

  /// Sheds fibres onto everything else in the load.
  final bool producesLint;

  /// Shows other fabrics' lint badly.
  final bool attractsLint;

  /// Effective drum space consumed, in grams-equivalent.
  double get drumLoadGrams => typicalWeightGrams * bulkFactor;

  /// Whether this is something that normally goes through a washing machine.
  ///
  /// Shoes, bags and jewellery are wardrobe items but not laundry, and the
  /// sorter must leave them out rather than proposing a cycle for them.
  bool get isWashable => kind == ItemKind.garment || kind == ItemKind.linen;
}

/// Sleeve length, where it applies.
enum SleeveLength {
  sleeveless('Sleeveless'),
  shortSleeve('Short sleeve'),
  threeQuarter('Three-quarter sleeve'),
  longSleeve('Long sleeve');

  const SleeveLength(this.label);

  final String label;
}

/// Surface pattern. Relevant to search, outfit matching, and dye-bleed risk.
enum Pattern {
  solid('Solid'),
  striped('Striped'),
  checked('Checked'),
  plaid('Plaid'),
  floral('Floral'),
  polkaDot('Polka dot'),
  graphic('Graphic print'),
  camouflage('Camouflage'),
  animalPrint('Animal print'),
  colorBlock('Color block'),
  heathered('Heathered'),
  other('Other');

  const Pattern(this.label);

  final String label;
}

/// When an item is worn. An item may suit several seasons.
enum Season {
  spring('Spring'),
  summer('Summer'),
  autumn('Autumn'),
  winter('Winter'),
  allSeason('All season');

  const Season(this.label);

  final String label;
}

/// How an item is cut. Recorded when it is evident, never inferred about the
/// person wearing it.
enum StyleCut {
  mens("Men's"),
  womens("Women's"),
  unisex('Unisex'),
  kids('Kids');

  const StyleCut(this.label);

  final String label;
}

/// How closely an item fits.
enum Fit {
  slim('Slim'),
  regular('Regular'),
  relaxed('Relaxed'),
  oversized('Oversized');

  const Fit(this.label);

  final String label;
}
