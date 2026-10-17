import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

const _bands = [
  'under 8 oz',
  'under 1 lb',
  '1–2 lb',
  '2–3 lb',
  'over 3 lb',
];

void main() {
  group('estimateShipping', () {
    test('adds a poly mailer to the typical weight of the garment', () {
      for (final type in ItemType.values) {
        expect(
          estimateShipping(type).packedGrams,
          type.typicalWeightGrams + 60,
          reason: type.name,
        );
      }
    });

    test('rounds the label weight up, never down', () {
      // 150 g + 60 g = 210 g = 7.41 oz.
      final tee = estimateShipping(ItemType.tShirt);

      expect(tee.packedGrams, 210);
      expect(tee.ounces, 8);
    });

    test('a light garment is under 8 oz', () {
      final socks = estimateShipping(ItemType.socks);

      expect(socks.packedGrams, 110);
      expect(socks.ounces, 4);
      expect(socks.band, 'under 8 oz');
    });

    test('bands on the weight itself, so 7.4 oz is under 8 oz', () {
      // Its label weight is 8 oz, and the band does not follow it up.
      final tee = estimateShipping(ItemType.tShirt);

      expect(tee.ounces, 8);
      expect(tee.band, 'under 8 oz');
    });

    test('a shirt is under a pound', () {
      final shirt = estimateShipping(ItemType.dressShirt);

      expect(shirt.packedGrams, 260);
      expect(shirt.ounces, 10);
      expect(shirt.band, 'under 1 lb');
    });

    test('a hoodie is between one and two pounds', () {
      final hoodie = estimateShipping(ItemType.hoodie);

      expect(hoodie.packedGrams, 610);
      expect(hoodie.ounces, 22);
      expect(hoodie.band, '1–2 lb');
    });

    test('boots are between two and three pounds', () {
      final boots = estimateShipping(ItemType.boots);

      expect(boots.packedGrams, 1260);
      expect(boots.ounces, 45);
      expect(boots.band, '2–3 lb');
    });

    test('a coat is over three pounds', () {
      final coat = estimateShipping(ItemType.coat);

      expect(coat.packedGrams, 1460);
      expect(coat.ounces, 52);
      expect(coat.band, 'over 3 lb');
    });

    test('every type lands in one of the five bands', () {
      for (final type in ItemType.values) {
        expect(_bands, contains(estimateShipping(type).band),
            reason: type.name);
      }
    });

    test('a heavier parcel is never in a lighter band', () {
      final byWeight = [...ItemType.values]
        ..sort((a, b) => a.typicalWeightGrams.compareTo(b.typicalWeightGrams));

      var lastBand = 0;
      for (final type in byWeight) {
        final band = _bands.indexOf(estimateShipping(type).band);
        expect(band, greaterThanOrEqualTo(lastBand), reason: type.name);
        lastBand = band;
      }
    });

    test('the label weight is the packed weight in ounces, rounded up', () {
      for (final type in ItemType.values) {
        final estimate = estimateShipping(type);
        final exact = estimate.packedGrams / 28.349523125;

        expect(estimate.ounces, greaterThanOrEqualTo(exact), reason: type.name);
        expect(estimate.ounces, lessThan(exact + 1), reason: type.name);
      }
    });

    test('agrees with the band thresholds for every type', () {
      for (final type in ItemType.values) {
        final estimate = estimateShipping(type);
        final exact = estimate.packedGrams / 28.349523125;
        final expected = exact < 8
            ? 'under 8 oz'
            : exact < 16
                ? 'under 1 lb'
                : exact <= 32
                    ? '1–2 lb'
                    : exact <= 48
                        ? '2–3 lb'
                        : 'over 3 lb';

        expect(estimate.band, expected, reason: type.name);
      }
    });
  });
}
