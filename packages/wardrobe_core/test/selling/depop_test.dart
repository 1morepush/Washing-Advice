import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

/// Every colour name the app can put on a garment, with the Depop colour it
/// must become.
///
/// The app names colours in three ways, and all three are here:
///
/// * the twenty swatches in the item editor (`edit_item_fields.dart`);
/// * the names a scan returns — the server's fake provider and the demo
///   wardrobe use these, and a real model writes a plain name like them;
/// * the shades the describe call writes into a listing's `colors`.
///
/// A name the app can produce and this table lacks would be a colour that
/// silently never reaches the listing, so adding a swatch to the editor means
/// adding it here.
const _appColourNames = <String, DepopColour>{
  // The item editor's swatches, in the order it shows them.
  'White': DepopColour.white,
  'Cream': DepopColour.cream,
  'Beige': DepopColour.tan,
  'Gray': DepopColour.grey,
  'Charcoal': DepopColour.grey,
  'Black': DepopColour.black,
  'Navy': DepopColour.navy,
  'Blue': DepopColour.blue,
  'Light blue': DepopColour.blue,
  'Denim': DepopColour.blue,
  'Teal': DepopColour.green,
  'Green': DepopColour.green,
  'Olive': DepopColour.green,
  'Yellow': DepopColour.yellow,
  'Orange': DepopColour.orange,
  'Red': DepopColour.red,
  'Burgundy': DepopColour.burgundy,
  'Pink': DepopColour.pink,
  'Purple': DepopColour.purple,
  'Brown': DepopColour.brown,

  // Names in the demo wardrobe, the fixtures and the server's fake provider.
  'Indigo': DepopColour.navy,
  'Pale blue': DepopColour.blue,
  'Stone': DepopColour.tan,
  'Faded blue': DepopColour.blue,
  'Grey': DepopColour.grey,
  'Khaki': DepopColour.khaki,

  // What a model writes when asked for plain colour names.
  'Heather grey': DepopColour.grey,
  'Off-white': DepopColour.cream,
  'Off white': DepopColour.cream,
  'Dark green': DepopColour.green,
  'Sky blue': DepopColour.blue,
  'Navy blue': DepopColour.navy,
  'Dark blue': DepopColour.navy,
  'Olive green': DepopColour.green,
  'Forest green': DepopColour.green,
  'Hot pink': DepopColour.pink,
  'Burnt orange': DepopColour.orange,
  'Mustard': DepopColour.yellow,
  'Tan': DepopColour.tan,
  'Camel': DepopColour.tan,
  'Silver': DepopColour.silver,
  'Gold': DepopColour.gold,
  'Maroon': DepopColour.burgundy,
  'Lavender': DepopColour.purple,
  'Multicolor': DepopColour.multi,
  'Multi-colour': DepopColour.multi,
};

void main() {
  group('DepopCondition', () {
    test('uses Depop\'s five labels, spelled as its picker spells them', () {
      expect([
        for (final c in DepopCondition.values) c.label
      ], [
        'Brand new',
        'Like new',
        'Used - Excellent',
        'Used - Good',
        'Used - Fair',
      ]);
    });

    test('says in a few words what each one means', () {
      expect(DepopCondition.brandNew.meaning, 'Unworn, may have tags');
      expect(DepopCondition.likeNew.meaning, 'Worn, no signs of wear');
      expect(DepopCondition.usedExcellent.meaning, 'Minimal signs of wear');
      expect(DepopCondition.usedGood.meaning, 'Some signs of wear');
      expect(
        DepopCondition.usedFair.meaning,
        'Noticeable flaws, all described',
      );
    });

    test('is ordered best to worst, so the index can be compared', () {
      expect(
        DepopCondition.brandNew.index,
        lessThan(DepopCondition.likeNew.index),
      );
      expect(
        DepopCondition.usedGood.index,
        lessThan(DepopCondition.usedFair.index),
      );
    });
  });

  group('DepopDepartment', () {
    test('is men or women', () {
      expect([
        for (final d in DepopDepartment.values) d.label
      ], [
        'Men',
        'Women',
      ]);
    });
  });

  group('limits', () {
    test('are the ones Depop enforces', () {
      expect(depopDescriptionLimit, 1000);
      expect(depopHashtagLimit, 5);
      expect(depopColourLimit, 2);
      expect(depopPhotoLimit, 8);
    });
  });

  group('DepopColour', () {
    test('is Depop\'s nineteen colours', () {
      expect(DepopColour.values, hasLength(19));
      expect(DepopColour.values.map((c) => c.label), [
        'Black',
        'Grey',
        'White',
        'Brown',
        'Tan',
        'Cream',
        'Yellow',
        'Red',
        'Burgundy',
        'Orange',
        'Pink',
        'Purple',
        'Blue',
        'Navy',
        'Green',
        'Khaki',
        'Multi',
        'Silver',
        'Gold',
      ]);
    });
  });

  group('depopCategoryFor', () {
    String category(
      ItemType type, [
      DepopDepartment department = DepopDepartment.men,
    ]) =>
        depopCategoryFor(type, department);

    test('walks from the broad heading to the narrow one', () {
      expect(category(ItemType.sweatshirt), 'Tops › Sweatshirts');
      expect(category(ItemType.tShirt), 'Tops › T-shirts');
      expect(category(ItemType.jeans), 'Bottoms › Jeans');
    });

    test('uses American words, since the shop is American', () {
      expect(category(ItemType.sweater), 'Tops › Sweaters');
      expect(category(ItemType.trousers), 'Bottoms › Pants');
      expect(category(ItemType.chinos), 'Bottoms › Pants');
      expect(category(ItemType.sneakers), 'Footwear › Sneakers');
      expect(category(ItemType.pajamas), 'Loungewear › Pajamas');
    });

    test('files towels and bedding under Home', () {
      for (final type in [
        ItemType.handTowel,
        ItemType.bathTowel,
        ItemType.bedSheet,
        ItemType.pillowcase,
        ItemType.duvetCover,
        ItemType.blanket,
      ]) {
        expect(category(type), 'Home', reason: type.name);
      }
    });

    test('files something that is no known type under Other', () {
      expect(category(ItemType.other), 'Other');
    });

    test('answers for every type in both departments', () {
      // The case a new ItemType would otherwise slip through: a switch with
      // no default forces a decision at compile time, and this checks the
      // decision is a usable path.
      for (final type in ItemType.values) {
        for (final department in DepopDepartment.values) {
          final path = depopCategoryFor(type, department);
          expect(path, isNotEmpty, reason: '${type.name}/${department.name}');
          expect(path, equals(path.trim()));
          for (final step in path.split(' › ')) {
            expect(step, isNotEmpty, reason: path);
          }
        }
      }
    });

    test('a blouse is a women\'s category, so a man is told shirts', () {
      expect(
        category(ItemType.blouse, DepopDepartment.women),
        'Tops › Blouses',
      );
      expect(category(ItemType.blouse, DepopDepartment.men), 'Tops › Shirts');
    });

    test('a bra or tights are still answered for the men\'s side', () {
      expect(category(ItemType.bra, DepopDepartment.women), 'Underwear › Bras');
      expect(category(ItemType.bra, DepopDepartment.men), 'Underwear');
      expect(
        category(ItemType.tights, DepopDepartment.women),
        'Underwear › Tights',
      );
      expect(category(ItemType.tights, DepopDepartment.men), 'Underwear');
    });

    test('a dress and a skirt are answered for either department', () {
      expect(category(ItemType.dress, DepopDepartment.men), 'Dresses');
      expect(category(ItemType.dress, DepopDepartment.women), 'Dresses');
      expect(category(ItemType.skirt, DepopDepartment.men), 'Bottoms › Skirts');
      expect(
        category(ItemType.skirt, DepopDepartment.women),
        'Bottoms › Skirts',
      );
    });
  });

  group('depopColoursFor', () {
    test('maps every colour name the app can produce', () {
      _appColourNames.forEach((name, expected) {
        expect(depopColoursFor([name]), [expected], reason: name);
      });
    });

    test('covers every one of Depop\'s colours from some name', () {
      // A colour nothing maps to is one the table forgot, since the app can
      // always be handed its name.
      final reached = {
        for (final colour in DepopColour.values)
          ...depopColoursFor([colour.label]),
      };
      expect(reached, DepopColour.values.toSet());
    });

    test('each of Depop\'s own labels maps to itself', () {
      for (final colour in DepopColour.values) {
        expect(depopColoursFor([colour.label]), [colour], reason: colour.name);
      }
    });

    test('puts the dominant colour first', () {
      expect(depopColoursFor(['Navy', 'White']), [
        DepopColour.navy,
        DepopColour.white,
      ]);
      expect(depopColoursFor(['White', 'Navy']), [
        DepopColour.white,
        DepopColour.navy,
      ]);
    });

    test('lists a colour once, however many names reduce to it', () {
      expect(depopColoursFor(['Gray', 'Charcoal']), [DepopColour.grey]);
      expect(depopColoursFor(['Grey', 'Heather grey', 'Slate']), [
        DepopColour.grey,
      ]);
    });

    test('a repeat does not use up one of the two places', () {
      expect(depopColoursFor(['Gray', 'Charcoal', 'White']), [
        DepopColour.grey,
        DepopColour.white,
      ]);
    });

    test('three or more distinct colours is Multi', () {
      expect(depopColoursFor(['Red', 'White', 'Blue']), [DepopColour.multi]);
      expect(
        depopColoursFor(['Red', 'White', 'Blue', 'Green']),
        [DepopColour.multi],
      );
    });

    test('never returns more than the colours Depop allows', () {
      for (final names in [
        ['Red'],
        ['Red', 'Blue'],
        ['Red', 'Blue', 'Green'],
        ['Red', 'Blue', 'Green', 'Pink', 'Gold'],
      ]) {
        expect(
          depopColoursFor(names).length,
          lessThanOrEqualTo(depopColourLimit),
          reason: '$names',
        );
      }
    });

    test('a name that already says multi is Multi on its own', () {
      expect(depopColoursFor(['Multicolour']), [DepopColour.multi]);
      expect(depopColoursFor(['Red', 'Multicolor']), [DepopColour.multi]);
      expect(depopColoursFor(['Tie-dye']), [DepopColour.multi]);
    });

    test('skips a name it does not know rather than guessing', () {
      expect(depopColoursFor(['Rust']), isEmpty);
      expect(depopColoursFor(['Rust', 'Navy']), [DepopColour.navy]);
      expect(depopColoursFor(['Heather']), [DepopColour.grey]);
    });

    test('an unknown name does not count towards Multi', () {
      expect(depopColoursFor(['Red', 'Rust', 'Blue']), [
        DepopColour.red,
        DepopColour.blue,
      ]);
    });

    test('a hex code is not a colour name', () {
      // The item editor names a typed hex colour after itself.
      expect(depopColoursFor(['#1F2A44']), isEmpty);
    });

    test('an empty list, or empty names, give nothing', () {
      expect(depopColoursFor(const []), isEmpty);
      expect(depopColoursFor(['', '  ']), isEmpty);
    });

    test('ignores case, hyphens and stray spaces', () {
      expect(depopColoursFor(['  NAVY  ']), [DepopColour.navy]);
      expect(depopColoursFor(['off-white']), [DepopColour.cream]);
      expect(depopColoursFor(['Off   White']), [DepopColour.cream]);
      expect(depopColoursFor(['light_blue']), [DepopColour.blue]);
    });

    test('a name that lists two colours counts as both', () {
      expect(depopColoursFor(['Black and white']), [
        DepopColour.black,
        DepopColour.white,
      ]);
      expect(depopColoursFor(['Navy/White']), [
        DepopColour.navy,
        DepopColour.white,
      ]);
      expect(depopColoursFor(['Grey & red']), [
        DepopColour.grey,
        DepopColour.red,
      ]);
      expect(depopColoursFor(['Grey, white']), [
        DepopColour.grey,
        DepopColour.white,
      ]);
    });

    test('a name that lists three colours is Multi', () {
      expect(depopColoursFor(['Red/white/blue']), [DepopColour.multi]);
    });

    test('does not split a word that merely contains "and"', () {
      expect(depopColoursFor(['Sand']), [DepopColour.tan]);
    });

    test('a shade in front of one plain colour is that colour', () {
      expect(depopColoursFor(['Dusty pink']), [DepopColour.pink]);
      expect(depopColoursFor(['Electric blue']), [DepopColour.blue]);
      expect(depopColoursFor(['Metallic silver']), [DepopColour.silver]);
    });

    test('two plain colours in one name are ambiguous, so it is skipped', () {
      expect(depopColoursFor(['Blue green']), isEmpty);
      expect(depopColoursFor(['Grey-blue']), isEmpty);
    });

    test('an exact name wins over the plain word inside it', () {
      // Off-white is cream and dark blue is navy; neither is the colour that
      // happens to appear in the name.
      expect(depopColoursFor(['Off white']), [DepopColour.cream]);
      expect(depopColoursFor(['Dark blue']), [DepopColour.navy]);
      expect(depopColoursFor(['Dark red']), [DepopColour.burgundy]);
    });
  });
}
