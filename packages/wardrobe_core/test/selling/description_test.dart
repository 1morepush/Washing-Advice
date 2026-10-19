import 'dart:math';

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/selling_fixtures.dart';

const _flawPhoto =
    ListingPhoto(uri: 'store://cuff.jpg', shot: ListingShot.flaw);

/// The listing the briefing's example description was written for.
Listing described({
  String title = 'Nike vintage crewneck sweatshirt grey',
  ItemType itemType = ItemType.sweatshirt,
  String? brand = 'Nike',
  String? sizeLabel = 'M',
  DepopCondition? condition = DepopCondition.usedExcellent,
  List<DepopColour> colours = const [DepopColour.grey],
  String? material = '80% cotton, 20% polyester',
  Measurements measurements = const Measurements(
    pitToPitIn: 21,
    lengthIn: 27,
  ),
  List<String> flaws = const ['small mark on the left cuff'],
  List<String> styleWords = const ['vintage', 'crewneck', '90s'],
  String? era,
  String? notes = 'Ships within 5 days.',
  List<ListingPhoto> photos = const [_flawPhoto],
}) =>
    Listing(
      id: const ListingId('d-1'),
      createdAt: listingCreated,
      updatedAt: listingCreated,
      title: title,
      itemType: itemType,
      brand: brand,
      sizeLabel: sizeLabel,
      condition: condition,
      colours: colours,
      material: material,
      measurements: measurements,
      flaws: flaws,
      styleWords: styleWords,
      era: era,
      notes: notes,
      photos: photos,
    );

/// A listing with only the fields named, for tests about one line.
Listing sparse({
  String title = '',
  String? brand,
  String? sizeLabel,
  DepopCondition? condition,
  List<DepopColour> colours = const [],
  String? material,
  Measurements measurements = Measurements.none,
  List<String> flaws = const [],
  String? notes,
  ItemType itemType = ItemType.other,
  List<String> styleWords = const [],
  String? era,
  List<ListingPhoto> photos = const [],
}) =>
    described(
      title: title,
      itemType: itemType,
      brand: brand,
      sizeLabel: sizeLabel,
      condition: condition,
      colours: colours,
      material: material,
      measurements: measurements,
      flaws: flaws,
      styleWords: styleWords,
      era: era,
      notes: notes,
      photos: photos,
    );

void main() {
  group('hashtagsFor', () {
    test('takes brand, then the item, then era, then style words', () {
      final listing = described(
        styleWords: const ['vintage', 'crewneck'],
        era: '90s',
      );

      expect(hashtagsFor(listing), [
        '#nike',
        '#sweatshirt',
        '#90s',
        '#vintage',
        '#crewneck',
      ]);
    });

    test('is at most five, whatever there is to say', () {
      final listing = described(
        styleWords: const ['a1', 'b2', 'c3', 'd4', 'e5', 'f6', 'g7'],
        era: 'y2k',
      );

      expect(hashtagsFor(listing), hasLength(depopHashtagLimit));
      expect(hashtagsFor(listing).take(3), ['#nike', '#sweatshirt', '#y2k']);
    });

    test('is lower case with only letters and digits', () {
      final listing = described(
        brand: "Levi's",
        styleWords: const ['Y2K!', 'Hi-Vis', 'zip up'],
        era: null,
      );

      expect(hashtagsFor(listing), [
        '#levis',
        '#sweatshirt',
        '#y2k',
        '#hivis',
        '#zipup',
      ]);
    });

    test('runs a brand of several words together', () {
      expect(
        hashtagsFor(described(brand: 'Calvin Klein')).first,
        '#calvinklein',
      );
      expect(hashtagsFor(described(brand: 'H&M')).first, '#hm');
    });

    test('keeps letters that are not ASCII', () {
      expect(
        hashtagsFor(described(brand: 'Comme des Garçons')).first,
        '#commedesgarçons',
      );
    });

    test('runs a style word of several words together', () {
      final listing = described(styleWords: const ['embroidered logo']);

      expect(hashtagsFor(listing), contains('#embroideredlogo'));
    });

    test('takes each word of the item type', () {
      expect(
        hashtagsFor(described(
            brand: null,
            itemType: ItemType.longSleeveShirt,
            styleWords: const [])),
        ['#longsleeve', '#shirt'],
      );
      expect(
        hashtagsFor(described(
            brand: null, itemType: ItemType.tShirt, styleWords: const [])),
        ['#tshirt'],
      );
      expect(
        hashtagsFor(described(
            brand: null, itemType: ItemType.poloShirt, styleWords: const [])),
        ['#polo', '#shirt'],
      );
    });

    test('has no tag for an item that is just Other', () {
      final listing = described(
        brand: 'Nike',
        itemType: ItemType.other,
        styleWords: const ['vintage'],
      );

      expect(hashtagsFor(listing), ['#nike', '#vintage']);
    });

    test('lists a tag once, however many ways it was reached', () {
      final listing = described(
        brand: 'Nike',
        styleWords: const ['nike', 'sweatshirt', '90s', '90s', 'Vintage'],
        era: '90s',
      );

      expect(hashtagsFor(listing), [
        '#nike',
        '#sweatshirt',
        '#90s',
        '#vintage',
      ]);
    });

    test('never makes a tag with nothing in it', () {
      final listing = described(
        brand: '&&',
        itemType: ItemType.other,
        styleWords: const ['', '   ', '!!!', 'vintage'],
        era: '',
      );

      expect(hashtagsFor(listing), ['#vintage']);
    });

    test('leaves out a brand or era there is not', () {
      final listing = described(brand: null, era: null, styleWords: const []);

      expect(hashtagsFor(listing), ['#sweatshirt']);
    });

    test('is empty for a listing with nothing to tag', () {
      expect(hashtagsFor(sparse()), isEmpty);
    });

    test('has a hash in front of every one and no spaces in any', () {
      for (final tag in hashtagsFor(described(styleWords: const ['a b c']))) {
        expect(tag, startsWith('#'));
        expect(tag.substring(1), isNot(contains(' ')));
        expect(tag.length, greaterThan(1));
      }
    });
  });

  group('composeDescription', () {
    test('lays a full listing out the way the briefing shows it', () {
      expect(composeDescription(described()), '''
Nike vintage crewneck sweatshirt grey

Brand: Nike
Size: M
Measurements: pit to pit 21", length 27"
Condition: Used - Excellent. Flaws: small mark on the left cuff (see photos).
Color: Grey
Material: 80% cotton, 20% polyester

Ships within 5 days.

#nike #sweatshirt #vintage #crewneck #90s''');
    });

    test('is written in American English', () {
      final text = composeDescription(described());

      expect(text, contains('Color: Grey'));
      expect(text, isNot(contains('Colour')));
    });

    group('leaves out a line when its value is missing', () {
      test('the brand', () {
        expect(composeDescription(described(brand: null)),
            isNot(contains('Brand:')));
      });

      test('the size', () {
        expect(composeDescription(described(sizeLabel: null)),
            isNot(contains('Size:')));
        expect(composeDescription(described(sizeLabel: '  ')),
            isNot(contains('Size:')));
      });

      test('the measurements', () {
        expect(
          composeDescription(described(measurements: Measurements.none)),
          isNot(contains('Measurements:')),
        );
      });

      test('the colour', () {
        expect(composeDescription(described(colours: const [])),
            isNot(contains('Color:')));
      });

      test('the material', () {
        expect(composeDescription(described(material: null)),
            isNot(contains('Material:')));
      });

      test('the condition and the flaws together', () {
        final text = composeDescription(
          described(condition: null, flaws: const []),
        );

        expect(text, isNot(contains('Condition:')));
        expect(text, isNot(contains('Flaws:')));
      });

      test('the notes', () {
        final text = composeDescription(described(notes: null));

        expect(text, isNot(contains('Ships within')));
        expect(composeDescription(described(notes: '   ')), text);
      });

      test('the title', () {
        expect(composeDescription(described(title: '  ')),
            startsWith('Brand: Nike'));
      });
    });

    test('leaves no gap where a line or a block was', () {
      final text = composeDescription(
        described(
          title: '',
          brand: null,
          sizeLabel: null,
          measurements: Measurements.none,
          condition: null,
          flaws: const [],
          colours: const [],
          material: null,
          notes: null,
        ),
      );

      // Only the hashtags are left, and with no brand there is no #nike.
      expect(text, '#sweatshirt #vintage #crewneck #90s');
    });

    test('separates the blocks with one blank line and no more', () {
      final text = composeDescription(described());

      expect(text, isNot(contains('\n\n\n')));
      expect(text, isNot(startsWith('\n')));
      expect(text, isNot(endsWith('\n')));
    });

    test('is empty for a listing with nothing in it', () {
      expect(composeDescription(sparse()), isEmpty);
    });

    group('the measurements', () {
      String measurementsFor(Measurements m) => composeDescription(
            sparse(measurements: m),
          );

      test('are written in inches with no trailing zeros', () {
        expect(
          measurementsFor(const Measurements(pitToPitIn: 21, lengthIn: 27.5)),
          'Measurements: pit to pit 21", length 27.5"',
        );
      });

      test('keep a fraction that is there', () {
        expect(
          measurementsFor(const Measurements(waistIn: 30.25)),
          'Measurements: waist 30.25"',
        );
      });

      test('round away noise', () {
        expect(
          measurementsFor(const Measurements(lengthIn: 21.999999)),
          'Measurements: length 22"',
        );
        expect(
          measurementsFor(const Measurements(lengthIn: 0.1 + 0.2 + 26.7)),
          'Measurements: length 27"',
        );
      });

      test('keep a whole number of tens whole', () {
        expect(
          measurementsFor(const Measurements(inseamIn: 30)),
          'Measurements: inseam 30"',
        );
        expect(
          measurementsFor(const Measurements(lengthIn: 100)),
          'Measurements: length 100"',
        );
      });

      test('list only the ones given, in the order a buyer reads them', () {
        expect(
          measurementsFor(
            const Measurements(
              inseamIn: 32,
              pitToPitIn: 21,
              sleeveIn: 24,
              waistIn: 30,
              lengthIn: 27,
            ),
          ),
          'Measurements: pit to pit 21", length 27", sleeve 24", waist 30", '
          'inseam 32"',
        );
      });
    });

    group('the condition and the flaws', () {
      String lineFor({
        DepopCondition? condition,
        List<String> flaws = const [],
        List<ListingPhoto> photos = const [],
      }) =>
          composeDescription(
            sparse(condition: condition, flaws: flaws, photos: photos),
          );

      test('are one line, joined by the condition', () {
        expect(
          lineFor(
            condition: DepopCondition.usedGood,
            flaws: const ['light pilling'],
            photos: const [_flawPhoto],
          ),
          'Condition: Used - Good. Flaws: light pilling (see photos).',
        );
      });

      test('are just the condition when no flaws are listed', () {
        expect(
          lineFor(condition: DepopCondition.likeNew),
          'Condition: Like new.',
        );
      });

      test('never claim there are no flaws', () {
        for (final condition in DepopCondition.values) {
          final text = composeDescription(
            described(condition: condition, flaws: const [], photos: const []),
          ).toLowerCase();

          expect(text, isNot(contains('flaw')), reason: condition.name);
          expect(text, isNot(contains('perfect')), reason: condition.name);
          expect(text, isNot(contains('mint')), reason: condition.name);
          expect(text, isNot(contains('no issues')), reason: condition.name);
        }
      });

      test('say Flaws on their own when nobody has graded it yet', () {
        // A flaw must not wait for a grade before it is disclosed.
        expect(
          lineFor(flaws: const ['small hole at the hem']),
          'Flaws: small hole at the hem.',
        );
      });

      test('add "see photos" only when a photograph of a flaw is there', () {
        expect(
          lineFor(
            condition: DepopCondition.usedFair,
            flaws: const ['small hole'],
          ),
          'Condition: Used - Fair. Flaws: small hole.',
        );
        expect(
          lineFor(
            condition: DepopCondition.usedFair,
            flaws: const ['small hole'],
            photos: const [
              ListingPhoto(uri: 'store://a.jpg', shot: ListingShot.cover),
            ],
          ),
          'Condition: Used - Fair. Flaws: small hole.',
        );
        expect(
          lineFor(
            condition: DepopCondition.usedFair,
            flaws: const ['small hole'],
            photos: const [_flawPhoto],
          ),
          'Condition: Used - Fair. Flaws: small hole (see photos).',
        );
      });

      test('list every flaw, separated by semicolons', () {
        expect(
          lineFor(
            condition: DepopCondition.usedGood,
            flaws: const ['light pilling', 'faded collar', 'loose thread'],
          ),
          'Condition: Used - Good. Flaws: light pilling; faded collar; '
          'loose thread.',
        );
      });

      test('do not end in two full stops when a flaw was typed with one', () {
        expect(
          lineFor(
            condition: DepopCondition.usedGood,
            flaws: const ['light pilling.', 'faded collar...'],
          ),
          'Condition: Used - Good. Flaws: light pilling; faded collar.',
        );
      });

      test('skip a flaw that is only whitespace', () {
        expect(
          lineFor(
            condition: DepopCondition.usedGood,
            flaws: const ['  ', 'light pilling'],
          ),
          'Condition: Used - Good. Flaws: light pilling.',
        );
      });

      test('say nothing at all when there are neither', () {
        expect(lineFor(), isEmpty);
        expect(lineFor(flaws: const ['   ']), isEmpty);
      });
    });

    group('the hashtags', () {
      test('come last, after the notes', () {
        final text = composeDescription(described());

        expect(text.trimRight().split('\n').last, startsWith('#nike'));
      });

      test('use up some of the five when the notes already have some', () {
        final text = composeDescription(
          described(notes: 'Smoke free home. #vintage #y2k'),
        );
        final check = checkDescription(text);

        expect(check.hashtagCount, depopHashtagLimit);
        expect(check.tooManyHashtags, isFalse);
        expect(text, endsWith('#nike #sweatshirt #crewneck'));
      });

      test('are left out when the notes already have five', () {
        final text = composeDescription(
          described(notes: '#a1 #b2 #c3 #d4 #e5'),
        );

        expect(checkDescription(text).hashtagCount, 5);
        expect(text, endsWith('#a1 #b2 #c3 #d4 #e5'));
      });

      test('never repeat one the person wrote', () {
        final text = composeDescription(
          described(notes: 'Nice one. #Nike'),
        );

        expect('#nike'.allMatches(text.toLowerCase()).length, 1);
      });

      test('are within Depop\'s five, whatever is passed', () {
        final text = composeDescription(
          described(styleWords: [for (var i = 0; i < 20; i++) 'word$i']),
        );

        expect(checkDescription(text).tooManyHashtags, isFalse);
      });

      test('match what hashtagsFor says when the notes have none', () {
        final listing = described();
        final text = composeDescription(listing);

        expect(text, endsWith(hashtagsFor(listing).join(' ')));
      });
    });

    group('when it would be too long', () {
      /// The length of the description with [flaw] as its one flaw.
      int lengthWith(String flaw, {List<String> styleWords = const []}) =>
          composeDescription(
            described(
              notes: null,
              flaws: [flaw],
              styleWords: styleWords,
              photos: const [],
            ),
          ).length;

      test('a description within the limit is left exactly as composed', () {
        final text = composeDescription(described());

        expect(text.length, lessThan(depopDescriptionLimit));
        expect(text, contains('Ships within 5 days.'));
      });

      test('drops the notes first', () {
        final text = composeDescription(described(notes: 'n' * 1200));

        expect(text.length, lessThanOrEqualTo(depopDescriptionLimit));
        expect(text, isNot(contains('nnnn')));
        // Everything else is untouched.
        expect(text, contains('Flaws: small mark on the left cuff'));
        expect(text, endsWith('#nike #sweatshirt #vintage #crewneck #90s'));
      });

      test('keeps notes that fit', () {
        final text = composeDescription(described(notes: 'n' * 300));

        expect(text, contains('n' * 300));
      });

      test('then shortens the flaws to the first, and says there were more',
          () {
        final flaws = [
          'first flaw ${'a' * 300}',
          'second flaw ${'b' * 300}',
          'third flaw ${'c' * 300}',
        ];
        final text = composeDescription(
          described(flaws: flaws, notes: 'short note'),
        );

        expect(text.length, lessThanOrEqualTo(depopDescriptionLimit));
        expect(text, isNot(contains('short note')));
        expect(text, contains('first flaw'));
        expect(text, isNot(contains('second flaw')));
        expect(text, contains(', and others'));
        expect(text, endsWith('#nike #sweatshirt #vintage #crewneck #90s'));
      });

      test('keeps every flaw when dropping the notes is enough', () {
        final flaws = ['first flaw ${'a' * 100}', 'second flaw ${'b' * 100}'];
        final text = composeDescription(
          described(flaws: flaws, notes: 'n' * 1200),
        );

        expect(text, contains('first flaw'));
        expect(text, contains('second flaw'));
        expect(text, isNot(contains('and others')));
      });

      test('says "see photos" after "and others" when there is a flaw photo',
          () {
        final flaws = ['first ${'a' * 400}', 'second ${'b' * 400}'];
        final text = composeDescription(described(flaws: flaws, notes: null));

        expect(text, contains(', and others (see photos).'));
      });

      test('then drops the style-word hashtags, keeping brand and type', () {
        // A flaw sized so that the description is exactly the limit without
        // style-word tags, and over it with them.
        final base = lengthWith('x', styleWords: const []);
        final flaw = 'x' * (1 + depopDescriptionLimit - base);
        expect(lengthWith(flaw), depopDescriptionLimit);

        final text = composeDescription(
          described(
            notes: null,
            flaws: [flaw],
            styleWords: const ['vintage', 'crewneck'],
            photos: const [],
          ),
        );

        expect(text.length, depopDescriptionLimit);
        expect(text, isNot(contains('#vintage')));
        expect(text, isNot(contains('#crewneck')));
        expect(text, endsWith('#nike #sweatshirt'));
      });

      test('then drops every hashtag', () {
        final listing = described(
          notes: null,
          flaws: const ['x'],
          styleWords: const [],
          photos: const [],
        );
        final withoutTags = composeDescription(listing)
            .split('\n\n')
            .where((block) => !block.startsWith('#'))
            .join('\n\n');
        final flaw = 'x' * (1 + depopDescriptionLimit - withoutTags.length);

        final text = composeDescription(
          described(
            notes: null,
            flaws: [flaw],
            styleWords: const [],
            photos: const [],
          ),
        );

        expect(text.length, depopDescriptionLimit);
        expect(text, isNot(contains('#')));
      });

      test('and only then cuts the text, ending in an ellipsis', () {
        final text = composeDescription(described(title: 't' * 3000));

        expect(text.length, depopDescriptionLimit);
        expect(text, endsWith('…'));
        expect(text, startsWith('ttt'));
      });

      test('never cuts through the middle of an emoji', () {
        // A title of emoji, each two code units long, so the limit lands
        // between the halves of one.
        for (final padding in [0, 1]) {
          final text = composeDescription(
            described(title: '${'a' * padding}${'😀' * 800}'),
          );

          expect(text.length, lessThanOrEqualTo(depopDescriptionLimit));
          final withoutEllipsis = text.substring(0, text.length - 1);
          expect(
            withoutEllipsis.codeUnits.last,
            isNot(inInclusiveRange(0xD800, 0xDBFF)),
            reason: 'padding $padding',
          );
        }
      });

      test('is never longer than Depop takes, whatever it is given', () {
        final random = Random(1017);
        String words(int n) => List.generate(
              n,
              (_) => String.fromCharCodes(
                List.generate(
                    1 + random.nextInt(9), (_) => 97 + random.nextInt(26)),
              ),
            ).join(' ');

        for (var round = 0; round < 300; round++) {
          final listing = described(
            title: words(random.nextInt(60)),
            brand: random.nextBool() ? words(random.nextInt(8)) : null,
            sizeLabel: random.nextBool() ? words(random.nextInt(4)) : null,
            material: random.nextBool() ? words(random.nextInt(80)) : null,
            notes: random.nextBool() ? words(random.nextInt(400)) : null,
            flaws: [
              for (var i = 0; i < random.nextInt(8); i++)
                words(random.nextInt(60)),
            ],
            styleWords: [
              for (var i = 0; i < random.nextInt(10); i++)
                words(random.nextInt(5)),
            ],
            photos: random.nextBool() ? const [_flawPhoto] : const [],
          );

          final text = composeDescription(listing);
          final check = checkDescription(text);

          expect(check.overLimit, isFalse, reason: 'round $round');
          expect(check.tooManyHashtags, isFalse, reason: 'round $round');
        }
      });

      test('is never longer than Depop takes with absurdly long inputs', () {
        final big = 'word ' * 2000;
        final listing = described(
          title: big,
          brand: big,
          sizeLabel: big,
          material: big,
          notes: big,
          flaws: [big, big, big],
          styleWords: [big, big],
        );

        expect(
          composeDescription(listing).length,
          lessThanOrEqualTo(depopDescriptionLimit),
        );
      });
    });
  });

  group('checkDescription', () {
    test('counts the characters', () {
      expect(checkDescription('').length, 0);
      expect(checkDescription('hello world').length, 11);
    });

    test('counts the hashtags', () {
      expect(checkDescription('#nike #vintage').hashtagCount, 2);
      expect(checkDescription('no tags here').hashtagCount, 0);
      expect(checkDescription('').hashtagCount, 0);
    });

    test('counts a tag in brackets or at the start of a line', () {
      expect(checkDescription('(#nike)').hashtagCount, 1);
      expect(checkDescription('line one\n#nike\n#vintage').hashtagCount, 2);
    });

    test('does not count a hash in the middle of a word', () {
      expect(checkDescription('item#4 and a#b').hashtagCount, 0);
      expect(
        checkDescription('see https://example.com/page#section').hashtagCount,
        0,
      );
    });

    test('does not count a lone hash', () {
      expect(checkDescription('# nike').hashtagCount, 0);
      expect(checkDescription('#').hashtagCount, 0);
      expect(checkDescription('#!').hashtagCount, 0);
    });

    test('counts digits, underscores and letters that are not ASCII', () {
      expect(
          checkDescription('#90s #y2k #vintage_look #garçon').hashtagCount, 4);
    });

    test('counts a repeated tag each time it appears', () {
      expect(checkDescription('#nike #nike').hashtagCount, 2);
    });

    test('is over the limit past a thousand characters', () {
      expect(checkDescription('a' * 1000).overLimit, isFalse);
      expect(checkDescription('a' * 1001).overLimit, isTrue);
    });

    test('has too many hashtags past five', () {
      expect(checkDescription('#a #b #c #d #e').tooManyHashtags, isFalse);
      expect(checkDescription('#a #b #c #d #e #f').tooManyHashtags, isTrue);
    });

    test('agrees with the description it was composed from', () {
      final text = composeDescription(described());
      final check = checkDescription(text);

      expect(check.length, text.length);
      expect(check.hashtagCount, 5);
      expect(check.overLimit, isFalse);
      expect(check.tooManyHashtags, isFalse);
    });
  });
}
