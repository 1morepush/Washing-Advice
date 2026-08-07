/// What an outfit is *for*.
///
/// Occasion suitability lives in this context rather than on [ItemType]
/// because it is a styling judgement, not a physical fact. Weight, bulk and
/// lint belong on the type — they are true of the garment wherever it is used,
/// and the laundry engine depends on them. Whether a hoodie is acceptable at
/// work is a matter of taste that varies by person and by workplace, so it is
/// modelled here as a *default* the user can override with tags rather than as
/// an intrinsic property.
library;

import '../../wardrobe/model/item_attributes.dart';

/// The kind of day an outfit has to survive.
enum Occasion {
  everyday('Everyday'),
  work('Work'),
  formal('Formal'),
  active('Active'),
  outdoors('Outdoors'),
  lounge('Lounge');

  const Occasion(this.label);

  final String label;

  /// A free-text tag that opts an item into this occasion regardless of type.
  ///
  /// The escape hatch for the paragraph above: someone whose office is a
  /// workshop tags their hoodie `work` and the defaults stop arguing.
  String get tag => name;

  /// Whether [type] is a plausible choice for this occasion by default.
  bool suits(ItemType type) => _defaults[this]!.contains(type);

  /// Occasions this type suits by default.
  static Set<Occasion> forType(ItemType type) => {
        for (final occasion in Occasion.values)
          if (occasion.suits(type)) occasion,
      };
}

// The tables are written out per occasion rather than derived from a
// "formality" number on each type. A single ordinal would claim that active
// wear and formal wear sit on one axis with lounge wear between them, which is
// not how anyone dresses: a running top is not a slightly-less-formal blazer.
const Map<Occasion, Set<ItemType>> _defaults = {
  Occasion.everyday: {
    ItemType.tShirt,
    ItemType.longSleeveShirt,
    ItemType.poloShirt,
    ItemType.blouse,
    ItemType.tankTop,
    ItemType.sweater,
    ItemType.cardigan,
    ItemType.hoodie,
    ItemType.sweatshirt,
    ItemType.jeans,
    ItemType.trousers,
    ItemType.chinos,
    ItemType.shorts,
    ItemType.skirt,
    ItemType.leggings,
    ItemType.dress,
    ItemType.jumpsuit,
    ItemType.jacket,
    ItemType.vest,
    ItemType.sneakers,
    ItemType.boots,
    ItemType.sandals,
    ItemType.scarf,
    ItemType.hat,
    ItemType.belt,
    ItemType.handbag,
    ItemType.backpack,
  },
  Occasion.work: {
    ItemType.dressShirt,
    ItemType.longSleeveShirt,
    ItemType.blouse,
    ItemType.poloShirt,
    ItemType.sweater,
    ItemType.cardigan,
    ItemType.trousers,
    ItemType.chinos,
    ItemType.skirt,
    ItemType.dress,
    ItemType.jumpsuit,
    ItemType.blazer,
    ItemType.jacket,
    ItemType.coat,
    ItemType.vest,
    ItemType.dressShoes,
    ItemType.boots,
    ItemType.belt,
    ItemType.tie,
    ItemType.handbag,
  },
  Occasion.formal: {
    ItemType.dressShirt,
    ItemType.blouse,
    ItemType.trousers,
    ItemType.skirt,
    ItemType.dress,
    ItemType.jumpsuit,
    ItemType.blazer,
    ItemType.coat,
    ItemType.dressShoes,
    ItemType.belt,
    ItemType.tie,
    ItemType.handbag,
  },
  Occasion.active: {
    ItemType.activewearTop,
    ItemType.activewearBottom,
    ItemType.tankTop,
    ItemType.tShirt,
    ItemType.shorts,
    ItemType.leggings,
    ItemType.hoodie,
    ItemType.sweatshirt,
    ItemType.vest,
    ItemType.sneakers,
    ItemType.hat,
    ItemType.backpack,
  },
  Occasion.outdoors: {
    ItemType.longSleeveShirt,
    ItemType.sweater,
    ItemType.hoodie,
    ItemType.sweatshirt,
    ItemType.jeans,
    ItemType.trousers,
    ItemType.shorts,
    ItemType.jacket,
    ItemType.coat,
    ItemType.vest,
    ItemType.boots,
    ItemType.sneakers,
    ItemType.hat,
    ItemType.gloves,
    ItemType.scarf,
    ItemType.backpack,
  },
  Occasion.lounge: {
    ItemType.tShirt,
    ItemType.tankTop,
    ItemType.hoodie,
    ItemType.sweatshirt,
    ItemType.sweater,
    ItemType.cardigan,
    ItemType.leggings,
    ItemType.shorts,
    ItemType.pajamas,
    ItemType.robe,
    ItemType.sandals,
  },
};
