/// How well a garment answers the day's [DressingNeeds].
///
/// Only attributes the wardrobe really records are used: the item's type, its
/// stated sleeve length, its dominant fibre, and its tags. Where the model
/// cannot tell — whether a jacket is waterproof, whether a shoe is suede,
/// whether a blouse has long sleeves — the answer is "no opinion", never a
/// guess. The one user-supplied escape hatch is tags, as for occasions:
/// tagging a jacket `waterproof` or a shoe `suede` is how the person tells the
/// app what it cannot see.
library;

import '../wardrobe/model/fabric.dart';
import '../wardrobe/model/item_attributes.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'model/outfit.dart';
import 'weather.dart';

/// Tags that mark a layer as rain-proof.
const Set<String> waterproofTags = {
  'waterproof',
  'raincoat',
  'rainproof',
  'water-resistant',
};

/// Tag that marks a shoe as one that rain ruins.
const String suedeTag = 'suede';

/// Facts about an item that matter for weather, each null/false when unknown.
extension WeatherTraits on WardrobeItem {
  bool get isWaterproof => tags.any((t) => waterproofTags.contains(t));

  bool get isSuede => tags.contains(suedeTag);

  /// Knitwear, fleece and wool: the pieces that are wrong in the heat.
  bool get isHeavyLayer {
    final fibre = composition.value.dominantFiber;
    if (fibre == Fiber.wool || fibre == Fiber.cashmere || fibre == Fiber.down) {
      return true;
    }
    return switch (type.value) {
      ItemType.sweater ||
      ItemType.cardigan ||
      ItemType.hoodie ||
      ItemType.sweatshirt ||
      ItemType.coat =>
        true,
      _ => false,
    };
  }

  /// The sleeve length, from the recorded value or the type when the type
  /// settles it; null when neither does (a blouse, an activewear top).
  SleeveLength? get effectiveSleeve {
    if (sleeveLength != null) return sleeveLength;
    return switch (type.value) {
      ItemType.tankTop => SleeveLength.sleeveless,
      ItemType.tShirt || ItemType.poloShirt => SleeveLength.shortSleeve,
      ItemType.longSleeveShirt ||
      ItemType.dressShirt ||
      ItemType.sweater ||
      ItemType.cardigan ||
      ItemType.hoodie ||
      ItemType.sweatshirt =>
        SleeveLength.longSleeve,
      _ => null,
    };
  }

  bool get isShortSleeved =>
      effectiveSleeve == SleeveLength.shortSleeve ||
      effectiveSleeve == SleeveLength.sleeveless;

  bool get isLongSleeved => effectiveSleeve == SleeveLength.longSleeve;

  /// Shoes that keep feet covered. Sandals are the only open type.
  bool get isClosedShoe =>
      OutfitSlot.ofType(type.value) == OutfitSlot.footwear &&
      type.value != ItemType.sandals;

  /// A jacket or coat that is a real outer layer, as opposed to a vest or
  /// blazer, which add little against rain or cold.
  bool get isProperOuterLayer =>
      type.value == ItemType.jacket || type.value == ItemType.coat;
}

/// How much to move an item's score for [needs], in `-0.6..0.6`.
///
/// Positive is "good for today", negative "poor for today"; zero is no
/// opinion. It is an adjustment, never a filter, so a small wardrobe still
/// gets something to wear (and a note about what is missing).
double weatherAdjustment(WardrobeItem item, DressingNeeds needs) {
  final type = item.type.value;
  var delta = 0.0;

  final isTop = OutfitSlot.ofType(type) == OutfitSlot.top;
  final isOuter = OutfitSlot.ofType(type) == OutfitSlot.outerwear;
  final isShoe = OutfitSlot.ofType(type) == OutfitSlot.footwear;
  final isShorts = type == ItemType.shorts || type == ItemType.skirt;

  switch (needs.band) {
    case WarmthBand.hot:
    case WarmthBand.warm:
      final hot = needs.band == WarmthBand.hot;
      if (item.isHeavyLayer) delta -= hot ? 0.4 : 0.25;
      if (isTop && item.isLongSleeved && !item.isHeavyLayer) {
        delta -= hot ? 0.2 : 0.05;
      }
      if (isTop && item.isShortSleeved) delta += hot ? 0.15 : 0.1;
      if (isShorts) delta += hot ? 0.15 : 0.1;
      if (isShoe && type == ItemType.sandals) delta += 0.1;
      if (isShoe && type == ItemType.boots) delta -= hot ? 0.3 : 0.15;
      if (isOuter && !item.isWaterproof) delta -= hot ? 0.3 : 0.15;
    case WarmthBand.mild:
      if (type == ItemType.coat) delta -= 0.2;
    case WarmthBand.cool:
      if (item.isHeavyLayer && !isOuter) delta += 0.1;
      if (isTop && type == ItemType.tankTop) delta -= 0.2;
      if (type == ItemType.shorts) delta -= 0.2;
      if (type == ItemType.sandals) delta -= 0.2;
    case WarmthBand.cold:
    case WarmthBand.freezing:
      final freezing = needs.band == WarmthBand.freezing;
      if (item.isHeavyLayer) delta += freezing ? 0.2 : 0.15;
      if (isTop && item.isLongSleeved) delta += 0.1;
      if (isTop && item.isShortSleeved) delta -= freezing ? 0.3 : 0.15;
      if (type == ItemType.shorts) delta -= freezing ? 0.5 : 0.4;
      if (type == ItemType.sandals) delta -= freezing ? 0.6 : 0.5;
      if (type == ItemType.boots) delta += 0.15;
      if (type == ItemType.coat) delta += freezing ? 0.4 : 0.3;
      if (type == ItemType.jacket) delta += 0.15;
      if (type == ItemType.vest || type == ItemType.blazer) delta -= 0.05;
  }

  if (needs.wet) {
    if (isShoe) {
      if (type == ItemType.sandals) delta -= 0.4;
      if (item.isSuede) delta -= 0.4;
      if (type == ItemType.boots) delta += 0.2;
    }
    if (isOuter) {
      if (item.isWaterproof) {
        delta += 0.4;
      } else if (item.isProperOuterLayer) {
        delta += 0.1;
      } else {
        delta -= 0.1;
      }
    }
  }

  if (needs.windy && item.isProperOuterLayer) delta += 0.05;

  return delta.clamp(-0.6, 0.6);
}

/// What is missing from [wardrobe] for [needs], as plain sentences.
///
/// Empty when the wardrobe can answer the day. Only wearable items count, and
/// the messages say what the *wardrobe* lacks, so they are shown once above
/// the ideas rather than repeated on every card.
List<String> weatherGaps(List<WardrobeItem> wardrobe, DressingNeeds needs) {
  final owned = [
    for (final item in wardrobe)
      if (item.lifecycle.isWearable) item,
  ];
  bool any(bool Function(WardrobeItem) test) => owned.any(test);
  bool slot(WardrobeItem i, OutfitSlot s) =>
      OutfitSlot.ofType(i.type.value) == s;

  final gaps = <String>[];

  final hasOuter = any((i) => i.isProperOuterLayer);
  if (needs.wet &&
      !any((i) => slot(i, OutfitSlot.outerwear) && i.isWaterproof)) {
    gaps.add(
      hasOuter
          ? 'No waterproof layer in your wardrobe (tag a jacket '
              '"waterproof" and it will be picked for rain)'
          : 'No waterproof layer in your wardrobe',
    );
  } else if (needs.outerLayer && !hasOuter) {
    gaps.add(
        'No jacket or coat in your wardrobe for a ${needs.band.label} day');
  }

  if (needs.wet && !any((i) => i.isClosedShoe)) {
    gaps.add('No closed shoes in your wardrobe for the rain');
  } else if (needs.isCold && !any((i) => i.isClosedShoe)) {
    gaps.add('No boots or closed shoes in your wardrobe for the cold');
  }

  if (needs.isCold &&
      !any((i) =>
          slot(i, OutfitSlot.top) && (i.isLongSleeved || i.isHeavyLayer))) {
    gaps.add('Nothing warm to wear on top: no sweater or long sleeves');
  }

  if (needs.band == WarmthBand.hot &&
      !any((i) =>
          (slot(i, OutfitSlot.top) && i.isShortSleeved) ||
          i.type.value == ItemType.shorts ||
          i.type.value == ItemType.dress)) {
    gaps.add('Nothing light for the heat: no short sleeves, shorts or dress');
  }

  return gaps;
}

/// The weather reasons for one outfit: a lead sentence naming the day and the
/// pieces that answer it, then any caveat the outfit itself carries.
List<String> weatherReasons(List<WardrobeItem> items, DressingNeeds needs) {
  final answers = <String>[];

  final layer = items
      .where((i) => OutfitSlot.ofType(i.type.value) == OutfitSlot.outerwear)
      .firstOrNull;
  if (layer != null && needs.outerLayer) {
    final name = layer.type.value.label.toLowerCase();
    answers.add(
      needs.wet && layer.isWaterproof ? 'a waterproof $name' : 'a $name',
    );
  }

  final shoes = items.where((i) => i.isClosedShoe).firstOrNull;
  if (shoes != null && (needs.wet || needs.isCold)) {
    answers.add('closed shoes');
  }

  final tops =
      items.where((i) => OutfitSlot.ofType(i.type.value) == OutfitSlot.top);
  if (needs.isCold && tops.any((i) => i.isLongSleeved || i.isHeavyLayer)) {
    answers.add('something warm on top');
  }
  if (needs.isHot &&
      (tops.any((i) => i.isShortSleeved) ||
          items.any((i) => i.type.value == ItemType.shorts))) {
    answers.add('light, short-sleeved pieces');
  }

  final reasons = <String>[];
  if (answers.isNotEmpty) {
    reasons.add('${needs.headline}: ${_join(answers)}');
  } else if (needs.wet || needs.isCold || needs.isHot) {
    // The day is worth naming even when the outfit has nothing special to
    // answer it with; the card is more honest saying so than staying silent.
    reasons.add('${needs.headline}, and nothing here is specially for it');
  }

  if (needs.wet &&
      layer != null &&
      !layer.isWaterproof &&
      !items.any((i) => i.isWaterproof)) {
    reasons.add('The layer is not marked waterproof, so take an umbrella');
  }
  return reasons;
}

String _join(List<String> parts) => parts.length <= 1
    ? parts.join()
    : '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
