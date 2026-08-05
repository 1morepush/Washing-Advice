/// Colour harmony, pinned against real garment colours.
///
/// The thresholds in `color_harmony.dart` are calibrated to measured CIELAB
/// hue angles, not to the red-yellow-blue wheel, so the only way to keep them
/// honest is to test them against colours that have names. Every expectation
/// below is a claim about clothes rather than about arithmetic.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final black = ItemColor.fromHex('#111114');
  final charcoal = ItemColor.fromHex('#3C3F44');
  final white = ItemColor.fromHex('#F7F6F2');
  final cream = ItemColor.fromHex('#F2E8D5');
  final navy = ItemColor.fromHex('#1F2A44');
  final red = ItemColor.fromHex('#C62828');
  final burgundy = ItemColor.fromHex('#7B1F2B');
  final orange = ItemColor.fromHex('#E8710A');
  final camel = ItemColor.fromHex('#C19A6B');
  final yellow = ItemColor.fromHex('#F9D423');
  final olive = ItemColor.fromHex('#6B7A3A');
  final green = ItemColor.fromHex('#2E7D32');
  final teal = ItemColor.fromHex('#00897B');
  final blue = ItemColor.fromHex('#1565C0');

  group('hue', () {
    test('wraps the short way round the wheel', () {
      expect(hueDifference(10, 350), closeTo(20, 0.001));
      expect(hueDifference(350, 10), closeTo(20, 0.001));
      expect(hueDifference(0, 180), closeTo(180, 0.001));
    });

    test('is symmetric, so harmony cannot depend on argument order', () {
      expect(harmonyBetween(red, green), harmonyBetween(green, red));
      expect(harmonyBetween(navy, white), harmonyBetween(white, navy));
    });
  });

  group('what counts as a neutral', () {
    test('navy is one, which is the whole reason the threshold is loose', () {
      // Navy measures a chroma of 18 — a colour by the numbers, and nothing
      // like one in a wardrobe. If this ever regresses, every suggestion
      // involving the most common garment colour there is gets worse.
      expect(navy.isNeutral, isTrue);
      expect(navy.chroma, greaterThan(15));
    });

    test('so are black, white, charcoal and cream', () {
      for (final color in [black, white, charcoal, cream]) {
        expect(color.isNeutral, isTrue, reason: '$color should be neutral');
      }
    });

    test('camel, olive and teal are not', () {
      // Muted, but still colours: they have to be chosen to go with things.
      for (final color in [camel, olive, teal, red, blue]) {
        expect(color.isNeutral, isFalse, reason: '$color should be a colour');
      }
    });
  });

  group('neutrals', () {
    test('go with any colour', () {
      expect(harmonyBetween(black, red), greaterThan(0.8));
      expect(harmonyBetween(navy, orange), greaterThan(0.8));
      expect(harmonyBetween(cream, green), greaterThan(0.8));
    });

    test('contrasting neutrals score best of all', () {
      expect(harmonyBetween(black, white), 1);
      expect(harmonyBetween(navy, cream), 1);
    });

    test('two mid-toned neutrals score worse than a strong contrast', () {
      // Charcoal with black is not wrong, but it reads as laundry rather than
      // as a decision, and the builder should prefer the deliberate pairing.
      expect(
        harmonyBetween(charcoal, black),
        lessThan(harmonyBetween(white, charcoal)),
      );
    });
  });

  group('colours, by measured hue distance', () {
    test('near-identical hues read as shades of one colour', () {
      expect(harmonyBetween(red, burgundy), 0.9);
      expect(describePairing(red, burgundy), 'Shades of one colour');
    });

    test('neighbours work', () {
      expect(harmonyBetween(red, yellow), 0.8);
      expect(harmonyBetween(camel, olive), 0.8);
      expect(describePairing(orange, yellow), 'Neighbouring colours');
    });

    test('optical opposites work', () {
      // These are the pairs CIELAB calls opposite, and they are the pairs that
      // actually work on clothes: blue with yellow, red with teal.
      expect(harmonyBetween(blue, yellow), 0.8);
      expect(harmonyBetween(red, teal), 0.8);
      expect(describePairing(blue, yellow), contains('Opposite'));
    });

    test('red and green are a clash, not a complement', () {
      // The correction that matters. On the pigment wheel these are opposite;
      // in the opponent space vision actually uses they are 107° apart, which
      // is the awkward middle — and red with green is exactly the pairing
      // people avoid outside December.
      expect(hueDifference(red.hue, green.hue), inInclusiveRange(100, 115));
      expect(harmonyBetween(red, green), 0.5);
      expect(describePairing(red, green), contains('awkward'));
    });

    test('orange and green are the same kind of gap', () {
      expect(harmonyBetween(orange, green), 0.5);
      expect(
        harmonyBetween(orange, green),
        lessThan(harmonyBetween(red, orange)),
      );
    });

    test('nothing scores zero', () {
      // A clash is a weak suggestion, not a prohibition. A hard zero would let
      // one questionable pairing veto an otherwise good outfit.
      final swatches = [red, orange, yellow, green, teal, blue, black, white];
      for (final x in swatches) {
        for (final y in swatches) {
          expect(harmonyBetween(x, y), greaterThan(0));
        }
      }
    });
  });

  group('a whole outfit', () {
    test('is judged by its worst pair, not its average', () {
      // Two excellent pairs and one poor one. Averaging would hide the pair
      // the wearer will actually notice.
      expect(harmonyOf([black, white, red]), harmonyBetween(black, red));
      expect(harmonyOf([navy, cream, red, green]), 0.5);
    });

    test('a single colour is unconstrained', () {
      expect(harmonyOf([red]), 1);
      expect(harmonyOf([]), 1);
    });
  });

  group('explanations', () {
    test('say nothing when there is nothing to say', () {
      // "This neutral goes with everything" is noise beside a suggestion.
      expect(describePairing(black, red), isNull);
      expect(describePairing(black, charcoal), isNull);
    });

    test('call out a strong neutral contrast, which is a real choice', () {
      expect(describePairing(black, white), contains('contrast'));
    });
  });
}
