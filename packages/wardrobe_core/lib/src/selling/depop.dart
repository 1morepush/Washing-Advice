/// Depop's own vocabulary, mirrored in one place.
///
/// These follow Depop's pickers as they stood in October 2026. Depop does not
/// publish them and nothing here reads them from Depop: they are copied by hand
/// from what its "Sell an item" form offers. So when Depop renames a condition
/// or adds a colour, the app is wrong in exactly one file, and a mismatch is a
/// one-line fix here rather than a hunt through the screens.
///
/// The app suggests these words and copies them to the clipboard; the person
/// still chooses them in Depop's own form, so a stale entry costs a tap and not
/// a wrong listing.
library;

import '../wardrobe/model/item_attributes.dart';

/// Depop's most photographs on one listing.
const int depopPhotoLimit = 8;

/// The longest description Depop takes, in characters.
const int depopDescriptionLimit = 1000;

/// The most hashtags Depop counts in a description.
const int depopHashtagLimit = 5;

/// The most colours Depop lets a listing carry.
const int depopColourLimit = 2;

/// How worn something is, in Depop's five words.
///
/// Declared best to worst, so [index] is a usable ordering.
enum DepopCondition {
  brandNew('Brand new', 'Unworn, may have tags'),
  likeNew('Like new', 'Worn, no signs of wear'),
  usedExcellent('Used - Excellent', 'Minimal signs of wear'),
  usedGood('Used - Good', 'Some signs of wear'),
  usedFair('Used - Fair', 'Noticeable flaws, all described');

  const DepopCondition(this.label, this.meaning);

  /// As Depop's picker spells it — hyphen and all, because this is the string
  /// pasted into a listing and compared by eye with the one on screen.
  final String label;

  /// What Depop says the choice means, short enough for beneath the label.
  final String meaning;
}

/// Which side of the shop a listing is filed under.
///
/// Depop's categories start here, and the same sweatshirt is found in a
/// different place depending on the answer.
enum DepopDepartment {
  men('Men'),
  women('Women');

  const DepopDepartment(this.label);

  final String label;
}

/// Depop's colour filter.
///
/// A short list on purpose: it is a search filter and not a paint chart, so
/// "charcoal" has to become [grey] and "olive" has to become [green] for a
/// buyer filtering by colour to find the garment at all. [depopColoursFor]
/// does that translation.
enum DepopColour {
  black('Black'),
  grey('Grey'),
  white('White'),
  brown('Brown'),
  tan('Tan'),
  cream('Cream'),
  yellow('Yellow'),
  red('Red'),
  burgundy('Burgundy'),
  orange('Orange'),
  pink('Pink'),
  purple('Purple'),
  blue('Blue'),
  navy('Navy'),
  green('Green'),
  khaki('Khaki'),
  multi('Multi'),
  silver('Silver'),
  gold('Gold');

  const DepopColour(this.label);

  final String label;
}

/// Where a [type] is filed on Depop, as the path its pickers walk:
/// `Tops › Sweatshirts`.
///
/// In American English, since that is the shop the prices come from — sweaters
/// and pants, not jumpers and trousers.
///
/// The [department] matters for the few things Depop files differently for
/// each. Blouses, bras and tights are women's categories, and a man selling one
/// is still told something he can use rather than a path that does not exist on
/// his side of the shop. Nothing here refuses: a category is a suggestion for
/// filling in a form, and an unhelpful answer is worse than an approximate one.
///
/// Exhaustive over [ItemType], with no default, so a new type cannot reach a
/// listing without somebody deciding where it is sold.
String depopCategoryFor(ItemType type, DepopDepartment department) {
  final isWomen = department == DepopDepartment.women;

  return switch (type) {
    ItemType.tShirt => 'Tops › T-shirts',
    ItemType.longSleeveShirt => 'Tops › Long sleeve tops',
    ItemType.dressShirt => 'Tops › Shirts',
    ItemType.poloShirt => 'Tops › Polo shirts',
    ItemType.blouse => isWomen ? 'Tops › Blouses' : 'Tops › Shirts',
    ItemType.tankTop => 'Tops › Tank tops',
    ItemType.sweater => 'Tops › Sweaters',
    ItemType.cardigan => 'Tops › Cardigans',
    ItemType.hoodie => 'Tops › Hoodies',
    ItemType.sweatshirt => 'Tops › Sweatshirts',
    ItemType.jeans => 'Bottoms › Jeans',
    ItemType.trousers || ItemType.chinos => 'Bottoms › Pants',
    ItemType.shorts => 'Bottoms › Shorts',
    ItemType.skirt => 'Bottoms › Skirts',
    ItemType.leggings => 'Bottoms › Leggings',
    ItemType.dress => 'Dresses',
    ItemType.jumpsuit => 'Jumpsuits & rompers',
    ItemType.jacket => 'Coats & jackets › Jackets',
    ItemType.blazer => 'Coats & jackets › Blazers',
    ItemType.coat => 'Coats & jackets › Coats',
    ItemType.vest => 'Coats & jackets › Vests',
    ItemType.underwear => 'Underwear',
    ItemType.bra => isWomen ? 'Underwear › Bras' : 'Underwear',
    ItemType.socks => 'Underwear › Socks',
    ItemType.tights => isWomen ? 'Underwear › Tights' : 'Underwear',
    ItemType.pajamas => 'Loungewear › Pajamas',
    ItemType.robe => 'Loungewear › Robes',
    ItemType.activewearTop => 'Activewear › Tops',
    ItemType.activewearBottom => 'Activewear › Bottoms',
    ItemType.swimwear => 'Swimwear',
    ItemType.scarf => 'Accessories › Scarves',
    ItemType.hat => 'Accessories › Hats',
    ItemType.gloves => 'Accessories › Gloves',
    ItemType.belt => 'Accessories › Belts',
    ItemType.tie => 'Accessories › Ties',
    ItemType.sneakers => 'Footwear › Sneakers',
    ItemType.boots => 'Footwear › Boots',
    ItemType.dressShoes => 'Footwear › Dress shoes',
    ItemType.sandals => 'Footwear › Sandals',
    ItemType.handbag => 'Bags › Handbags',
    ItemType.backpack => 'Bags › Backpacks',
    // Towels and bedding are not clothing, and Depop files them under one
    // heading rather than by kind.
    ItemType.handTowel ||
    ItemType.bathTowel ||
    ItemType.bedSheet ||
    ItemType.pillowcase ||
    ItemType.duvetCover ||
    ItemType.blanket =>
      'Home',
    ItemType.other => 'Other',
  };
}

/// Depop colours for the colour names a garment carries, dominant first.
///
/// The names are the app's own — whatever a scan wrote or the person picked
/// from the swatches ("Charcoal", "Light blue", "Gray") — and each is mapped
/// to the nearest word in Depop's short list. Matching is on the lowercase
/// name with hyphens and extra spaces ignored, and a name that is two colours
/// ("black and white", "navy/white") counts as both.
///
/// * The result is in the order given, without repeats, so the dominant colour
///   comes first.
/// * A name that is not recognised is skipped. Guessing a colour for
///   "rust" would put a confident wrong word in a search filter; saying
///   nothing leaves the person to choose.
/// * More colours than Depop lets a listing carry ([depopColourLimit]) is what
///   its Multi is for, so the result is just [DepopColour.multi]. So is any
///   name that already says multi.
List<DepopColour> depopColoursFor(List<String> colourNames) {
  final found = <DepopColour>[];

  for (final name in colourNames) {
    for (final part in _colourParts(name)) {
      final colour = _depopColourFor(part);
      if (colour == null) continue;
      if (colour == DepopColour.multi) return const [DepopColour.multi];
      if (!found.contains(colour)) found.add(colour);
    }
  }

  if (found.length > depopColourLimit) return const [DepopColour.multi];
  return found;
}

/// A name broken into the colours it lists, each reduced to a lookup key.
Iterable<String> _colourParts(String name) sync* {
  final lowered = name.toLowerCase().replaceAll(RegExp(r'[-_]+'), ' ');
  for (final part in lowered.split(RegExp(r'\s*(?:/|&|\+|,|\band\b)\s*'))) {
    final key = part.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (key.isNotEmpty) yield key;
  }
}

DepopColour? _depopColourFor(String key) {
  final exact = _colourNames[key];
  if (exact != null) return exact;

  // "Light blue", "forest green", "hot pink": a shade in front of a plain
  // colour word. The plain word is the answer, provided there is exactly one —
  // "blue green" names two colours, and picking either would be a guess.
  final plain = {
    for (final word in key.split(' '))
      if (_plainColourWords.contains(word)) _colourNames[word]!,
  };
  return plain.length == 1 ? plain.single : null;
}

/// The words that are colours on their own and, within a longer name, say which
/// colour it is. Each is also a key of [_colourNames].
const Set<String> _plainColourWords = {
  'black',
  'grey',
  'gray',
  'white',
  'brown',
  'yellow',
  'red',
  'orange',
  'pink',
  'purple',
  'blue',
  'green',
  'silver',
  'gold',
};

/// Colour names, lowercase, to Depop's.
///
/// Every name the app can produce is here or reduces to something here: the
/// twenty swatches in the item editor, the names a scan returns, and the
/// shades a person might type. `depop_test.dart` lists them. Mapping is a
/// judgement — teal is as much blue as green — and where it is a close call
/// the choice is written down so that changing it is a one-line edit.
const Map<String, DepopColour> _colourNames = {
  // Depop's own words map to themselves.
  'black': DepopColour.black,
  'grey': DepopColour.grey,
  'white': DepopColour.white,
  'brown': DepopColour.brown,
  'tan': DepopColour.tan,
  'cream': DepopColour.cream,
  'yellow': DepopColour.yellow,
  'red': DepopColour.red,
  'burgundy': DepopColour.burgundy,
  'orange': DepopColour.orange,
  'pink': DepopColour.pink,
  'purple': DepopColour.purple,
  'blue': DepopColour.blue,
  'navy': DepopColour.navy,
  'green': DepopColour.green,
  'khaki': DepopColour.khaki,
  'multi': DepopColour.multi,
  'silver': DepopColour.silver,
  'gold': DepopColour.gold,

  // Greys. American spelling, and the dark ones: charcoal is a grey.
  'gray': DepopColour.grey,
  'charcoal': DepopColour.grey,
  'slate': DepopColour.grey,
  'graphite': DepopColour.grey,
  'gunmetal': DepopColour.grey,
  'heather': DepopColour.grey,
  'marl': DepopColour.grey,
  'marle': DepopColour.grey,
  'ash': DepopColour.grey,

  // Whites and off-whites. Off-white is cream, not white: it is the shade a
  // buyer filtering for white would object to.
  'snow': DepopColour.white,
  'off white': DepopColour.cream,
  'ivory': DepopColour.cream,
  'ecru': DepopColour.cream,
  'bone': DepopColour.cream,
  'eggshell': DepopColour.cream,
  'oatmeal': DepopColour.cream,
  'natural': DepopColour.cream,

  // Neutrals warmer than grey. Depop has no beige, so the mid tones are tan.
  'beige': DepopColour.tan,
  'camel': DepopColour.tan,
  'sand': DepopColour.tan,
  'stone': DepopColour.tan,
  'taupe': DepopColour.tan,
  'fawn': DepopColour.tan,

  'chocolate': DepopColour.brown,
  'coffee': DepopColour.brown,
  'mocha': DepopColour.brown,
  'chestnut': DepopColour.brown,
  'cognac': DepopColour.brown,
  'espresso': DepopColour.brown,

  'mustard': DepopColour.yellow,
  'lemon': DepopColour.yellow,
  'butter': DepopColour.yellow,

  'tangerine': DepopColour.orange,

  'scarlet': DepopColour.red,
  'crimson': DepopColour.red,
  'cherry': DepopColour.red,

  // Dark reds are burgundy.
  'maroon': DepopColour.burgundy,
  'wine': DepopColour.burgundy,
  'wine red': DepopColour.burgundy,
  'oxblood': DepopColour.burgundy,
  'bordeaux': DepopColour.burgundy,
  'claret': DepopColour.burgundy,
  'dark red': DepopColour.burgundy,

  'rose': DepopColour.pink,
  'blush': DepopColour.pink,
  'fuchsia': DepopColour.pink,
  'magenta': DepopColour.pink,
  'salmon': DepopColour.pink,

  'violet': DepopColour.purple,
  'lilac': DepopColour.purple,
  'lavender': DepopColour.purple,
  'mauve': DepopColour.purple,
  'plum': DepopColour.purple,
  'aubergine': DepopColour.purple,

  // Blues. Light and mid blues are blue; the dark ones are navy, and so is
  // indigo, which is how denim is described in the shop.
  'denim': DepopColour.blue,
  'sky': DepopColour.blue,
  'cobalt': DepopColour.blue,
  'azure': DepopColour.blue,
  'cornflower': DepopColour.blue,
  'periwinkle': DepopColour.blue,
  'turquoise': DepopColour.blue,
  'aqua': DepopColour.blue,
  'navy blue': DepopColour.navy,
  'dark blue': DepopColour.navy,
  'midnight': DepopColour.navy,
  'midnight blue': DepopColour.navy,
  'indigo': DepopColour.navy,

  // Greens. Teal sits between the two; it is filed with green.
  'olive': DepopColour.green,
  'sage': DepopColour.green,
  'mint': DepopColour.green,
  'forest': DepopColour.green,
  'emerald': DepopColour.green,
  'lime': DepopColour.green,
  'moss': DepopColour.green,
  'hunter': DepopColour.green,
  'teal': DepopColour.green,

  // Names that already say there is no single colour.
  'multicolor': DepopColour.multi,
  'multicolour': DepopColour.multi,
  'multi color': DepopColour.multi,
  'multi colour': DepopColour.multi,
  'multicolored': DepopColour.multi,
  'multicoloured': DepopColour.multi,
  'rainbow': DepopColour.multi,
  'tie dye': DepopColour.multi,
  'tie dyed': DepopColour.multi,
};
