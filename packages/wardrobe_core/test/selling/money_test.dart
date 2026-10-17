import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  group('formatUsd', () {
    test('writes cents as dollars with two places', () {
      expect(formatUsd(2856), r'$28.56');
      expect(formatUsd(3000), r'$30.00');
      expect(formatUsd(45), r'$0.45');
    });

    test('pads a single-digit number of cents', () {
      expect(formatUsd(5), r'$0.05');
      expect(formatUsd(101), r'$1.01');
    });

    test('zero is a price too', () {
      expect(formatUsd(0), r'$0.00');
    });

    test('groups thousands, so a large price can still be read at a glance',
        () {
      expect(formatUsd(123456), r'$1,234.56');
      expect(formatUsd(99999), r'$999.99');
      expect(formatUsd(100000), r'$1,000.00');
      expect(formatUsd(100000000), r'$1,000,000.00');
    });

    test('keeps the sign in front of the dollar sign', () {
      // What is left after fees can be negative on a very cheap sale.
      expect(formatUsd(-45), r'-$0.45');
      expect(formatUsd(-123456), r'-$1,234.56');
    });
  });

  group('roundListPrice', () {
    test('under \$10 it is the nearest whole dollar', () {
      expect(roundListPrice(949), 900); // $9.49 -> $9
      expect(roundListPrice(701), 700);
      expect(roundListPrice(249), 200);
    });

    test('a half dollar rounds up', () {
      expect(roundListPrice(950), 1000); // $9.50 -> $10
      expect(roundListPrice(750), 800);
      expect(roundListPrice(150), 200);
    });

    test('never goes below \$1', () {
      expect(roundListPrice(45), 100);
      expect(roundListPrice(0), 100);
      expect(roundListPrice(149), 100);
      expect(roundListPrice(-500), 100);
    });

    test('from \$10 it is the nearest multiple of \$5', () {
      expect(roundListPrice(1000), 1000);
      expect(roundListPrice(1249), 1000); // $12.49 -> $10
      expect(roundListPrice(1300), 1500);
      expect(roundListPrice(2856), 3000);
      expect(roundListPrice(2740), 2500);
    });

    test('a tie between two multiples of \$5 rounds up', () {
      expect(roundListPrice(1250), 1500); // $12.50 -> $15
      expect(roundListPrice(1750), 2000);
      expect(roundListPrice(6250), 6500);
    });

    test('a multiple of \$5 is left alone', () {
      for (final dollars in [10, 15, 20, 45, 100, 250]) {
        expect(roundListPrice(dollars * 100), dollars * 100);
      }
    });

    test('the step up to \$10 is continuous with the step above it', () {
      // $9.99 is the most a whole-dollar price can be, and it must land on
      // the first multiple of $5 rather than skip over it.
      expect(roundListPrice(999), 1000);
      expect(roundListPrice(1000), 1000);
    });

    test('is idempotent, so a rounded price does not move again', () {
      for (var cents = 0; cents <= 20000; cents += 7) {
        final once = roundListPrice(cents);
        expect(roundListPrice(once), once, reason: 'for $cents');
      }
    });
  });

  group('roundListPriceDown', () {
    test('rounds down to a whole dollar under \$10', () {
      expect(roundListPriceDown(999), 900);
      expect(roundListPriceDown(950), 900);
      expect(roundListPriceDown(300), 300);
    });

    test('rounds down to a multiple of \$5 from \$10', () {
      expect(roundListPriceDown(6350), 6000); // $63.50 -> $60
      expect(roundListPriceDown(1499), 1000);
      expect(roundListPriceDown(1500), 1500);
    });

    test('never goes below \$1', () {
      expect(roundListPriceDown(80), 100);
      expect(roundListPriceDown(0), 100);
    });

    test('is never above the amount it was given, above \$1', () {
      for (var cents = 100; cents <= 20000; cents += 11) {
        expect(roundListPriceDown(cents), lessThanOrEqualTo(cents));
        expect(
            roundListPriceDown(cents),
            lessThanOrEqualTo(
              roundListPrice(cents),
            ));
      }
    });
  });

  group('median', () {
    test('an odd count is the middle value', () {
      expect(median([3000, 2500, 3200]), 3000);
      expect(median([1000]), 1000);
    });

    test('an even count is the mean of the two in the middle', () {
      expect(median([2800, 3200]), 3000);
      expect(median([1000, 2000, 3000, 9000]), 2500);
    });

    test('a half cent rounds up to the nearest cent', () {
      expect(median([2501, 2600]), 2551); // 2550.5
      expect(median([1, 2]), 2); // 1.5
    });

    test('one outlier does not move it', () {
      // The reason it is a median and not a mean.
      expect(median([2500, 2800, 3000, 40000]), 2900);
      expect(median([2500, 2800, 3000]), 2800);
    });

    test('does not reorder the list it was given', () {
      final values = [3200, 2500, 2800];
      median(values);
      expect(values, [3200, 2500, 2800]);
    });

    test('throws on an empty list rather than inventing a middle', () {
      expect(() => median(const []), throwsArgumentError);
    });
  });
}
