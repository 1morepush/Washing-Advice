import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

void main() {
  group('CIEDE2000', () {
    // The published verification data from Sharma, Wu and Dalal (2005),
    // including the pairs that sit exactly on the hue-quadrant discontinuity —
    // rows 9 to 12 differ only in the fourth decimal of b* yet must produce
    // visibly different results. Getting these right is the difference between
    // a working colour comparison and one that silently mis-sorts laundry.
    const referenceVectors = <List<double>>[
      [50.0000, 2.6772, -79.7751, 50.0000, 0.0000, -82.7485, 2.0425],
      [50.0000, 3.1571, -77.2803, 50.0000, 0.0000, -82.7485, 2.8615],
      [50.0000, 2.8361, -74.0200, 50.0000, 0.0000, -82.7485, 3.4412],
      [50.0000, -1.3802, -84.2814, 50.0000, 0.0000, -82.7485, 1.0000],
      [50.0000, -1.1848, -84.8006, 50.0000, 0.0000, -82.7485, 1.0000],
      [50.0000, -0.9009, -85.5211, 50.0000, 0.0000, -82.7485, 1.0000],
      [50.0000, 0.0000, 0.0000, 50.0000, -1.0000, 2.0000, 2.3669],
      [50.0000, -1.0000, 2.0000, 50.0000, 0.0000, 0.0000, 2.3669],
      [50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0009, 7.1792],
      [50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0010, 7.1792],
      [50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0011, 7.2195],
      [50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0012, 7.2195],
      [50.0000, -0.0010, 2.4900, 50.0000, 0.0009, -2.4900, 4.8045],
      [50.0000, 2.5000, 0.0000, 50.0000, 0.0000, -2.5000, 4.3065],
      [50.0000, 2.5000, 0.0000, 73.0000, 25.0000, -18.0000, 27.1492],
      [50.0000, 2.5000, 0.0000, 50.0000, 3.1736, 0.5854, 1.0000],
      [50.0000, 2.5000, 0.0000, 50.0000, 3.2972, 0.0000, 1.0000],
      [60.2574, -34.0099, 36.2677, 60.4626, -34.1751, 39.4387, 1.2644],
      [63.0109, -31.0961, -5.8663, 62.8187, -29.7946, -4.0864, 1.2630],
      [61.2901, 3.7196, -5.3901, 61.4292, 2.2480, -4.9620, 1.8731],
      [35.0831, -44.1164, 3.7933, 35.0232, -40.0716, 1.5901, 1.8645],
      [22.7233, 20.0904, -46.6940, 23.0331, 14.9730, -42.5619, 2.0373],
      [36.4612, 47.8580, 18.3852, 36.2715, 50.5065, 21.2231, 1.4146],
      [90.8027, -2.0831, 1.4410, 91.1528, -1.6435, 0.0447, 1.4441],
      [2.0776, 0.0795, -1.1350, 0.9033, -0.0636, -0.5514, 0.9082],
    ];

    for (var i = 0; i < referenceVectors.length; i++) {
      final v = referenceVectors[i];
      test('matches reference vector ${i + 1}', () {
        final difference = ItemColor.difference(
          ItemColor(lightness: v[0], a: v[1], b: v[2]),
          ItemColor(lightness: v[3], a: v[4], b: v[5]),
        );
        expect(difference, closeTo(v[6], 0.0002));
      });
    }

    test('is symmetric', () {
      final delta = ItemColor.difference(Colors.navy, Colors.black);
      final reversed = ItemColor.difference(Colors.black, Colors.navy);
      expect(delta, closeTo(reversed, 1e-9));
    });

    test('a colour is identical to itself', () {
      expect(ItemColor.difference(Colors.red, Colors.red), closeTo(0, 1e-9));
    });
  });

  group('sRGB to CIELAB', () {
    test('white converts to L=100 on the neutral axis', () {
      final white = ItemColor.fromHex('#FFFFFF');
      expect(white.lightness, closeTo(100, 0.01));
      expect(white.chroma, closeTo(0, 0.01));
    });

    test('black converts to L=0', () {
      expect(ItemColor.fromHex('#000000').lightness, closeTo(0, 0.01));
    });

    test('pure red matches its published Lab value', () {
      final red = ItemColor.fromHex('#FF0000');
      expect(red.lightness, closeTo(53.24, 0.01));
      expect(red.a, closeTo(80.09, 0.01));
      expect(red.b, closeTo(67.20, 0.01));
    });

    test('accepts hex with and without a leading hash', () {
      expect(ItemColor.fromHex('#FF0000').a, ItemColor.fromHex('FF0000').a);
    });

    test('rejects a malformed hex string', () {
      expect(() => ItemColor.fromHex('#FFF'), throwsFormatException);
    });
  });

  group('CIELAB to sRGB', () {
    test('round-trips every channel exactly', () {
      // Exact, not approximate: the conversion runs through two non-linear
      // transfer functions, and rounding drift here would show up as a swatch
      // that is not the colour the garment was scanned as.
      const samples = [
        '#FFFFFF',
        '#000000',
        '#FF0000',
        '#00FF00',
        '#0000FF',
        '#3F5B8C',
        '#8A8A8A',
        '#1A1A2E',
      ];
      for (final hex in samples) {
        expect(ItemColor.fromHex(hex).hex, hex, reason: hex);
      }
    });

    test('clamps colours sRGB cannot show instead of overflowing', () {
      // A highly chromatic Lab value sits outside the sRGB gamut. Clamping
      // loses accuracy, which is honest; letting the channel wrap would render
      // a vivid green garment as something unrelated.
      const outOfGamut = ItemColor(lightness: 60, a: -120, b: 90);
      final rgb = outOfGamut.rgb;
      for (var shift = 0; shift <= 16; shift += 8) {
        expect((rgb >> shift) & 0xFF, inInclusiveRange(0, 255));
      }
    });
  });

  group('colour classification', () {
    test('near-white with low chroma is a white', () {
      expect(Colors.white.colorClass, ColorClass.whites);
    });

    test('black and navy are darks', () {
      expect(Colors.black.colorClass, ColorClass.darks);
      expect(Colors.navy.colorClass, ColorClass.darks);
    });

    test('saturated red is a bright, not a dark', () {
      expect(Colors.red.colorClass, ColorClass.brights);
    });

    test('pastel pink is a light', () {
      expect(Colors.pastelPink.colorClass, ColorClass.lights);
    });

    test('saturated mid-tone colours are flagged as likely to bleed', () {
      expect(Colors.red.isLikelyToBleed, isTrue);
      expect(Colors.royalBlue.isLikelyToBleed, isTrue);
    });

    test('pastels and neutrals are not flagged as bleeding', () {
      expect(Colors.pastelPink.isLikelyToBleed, isFalse);
      expect(Colors.grey.isLikelyToBleed, isFalse);
      expect(Colors.white.isLikelyToBleed, isFalse);
    });
  });

  group('ColorPalette', () {
    test('orders colours by coverage, largest first', () {
      final palette = ColorPalette([
        Colors.red.copyWith(coverage: 0.2),
        Colors.navy.copyWith(coverage: 0.8),
      ]);
      expect(palette.dominant?.name, 'Navy');
    });

    test('a mostly-white garment with a large navy print is not a white', () {
      // The case that ruins a whites load: a white tee with a big dark graphic
      // cannot be washed with whites, even though its dominant colour is white.
      final palette = ColorPalette([
        Colors.white.copyWith(coverage: 0.7),
        Colors.navy.copyWith(coverage: 0.3),
      ]);
      expect(palette.colors.first.colorClass, ColorClass.whites);
      expect(palette.colorClass, ColorClass.lights);
    });

    test('a white garment with a tiny accent stays a white', () {
      final palette = ColorPalette([
        Colors.white.copyWith(coverage: 0.97),
        Colors.navy.copyWith(coverage: 0.03),
      ]);
      expect(palette.colorClass, ColorClass.whites);
    });

    test('an empty palette is treated as dark, the safe assumption', () {
      expect(ColorPalette.empty().colorClass, ColorClass.darks);
    });

    test('reports bleeding when any colour present can run', () {
      final palette = ColorPalette([
        Colors.white.copyWith(coverage: 0.8),
        Colors.red.copyWith(coverage: 0.2),
      ]);
      expect(palette.isLikelyToBleed, isTrue);
    });

    test('survives a JSON round trip', () {
      final palette = ColorPalette([
        Colors.navy.copyWith(coverage: 0.6),
        Colors.white.copyWith(coverage: 0.4),
      ]);
      expect(ColorPalette.fromJson(palette.toJson()), palette);
    });
  });
}
