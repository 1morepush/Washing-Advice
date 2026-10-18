/// What the editor makes of what a person types, and the sentences it builds
/// from numbers.
///
/// A price box that reads "3.555" as $3.56, or "12,50" as $1,250, is a box that
/// puts a wrong number in a listing without a word. These hold the edges: what
/// is an amount, what is not, and that "not" means ignored and never zero.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/features/sell/editor/amount_input.dart';
import 'package:washing_advice/features/sell/editor/editor_text.dart';

void main() {
  group('a price typed in dollars', () {
    test('is read from the digits, to the cent', () {
      expect(parseUsdInput('32'), 3200);
      expect(parseUsdInput('32.5'), 3250);
      expect(parseUsdInput('32.50'), 3250);
      expect(parseUsdInput('0.99'), 99);
      // The one a double gets wrong: 32.57 * 100 is 3256.9999999999995.
      expect(parseUsdInput('32.57'), 3257);
      expect(parseUsdInput('19.99'), 1999);
    });

    test('may start or end at the point', () {
      expect(parseUsdInput('.5'), 50);
      expect(parseUsdInput('5.'), 500);
    });

    test('may carry a dollar sign and spaces, as pasted', () {
      expect(parseUsdInput(r'$32'), 3200);
      expect(parseUsdInput(r' $ 32.50 '), 3250);
    });

    test('may group thousands', () {
      expect(parseUsdInput('1,234'), 123400);
      expect(parseUsdInput('1,234.50'), 123450);
      expect(parseUsdInput(r'$12,345'), 1234500);
      expect(parseUsdInput('99,999.99'), 9999999);
      // Two commas are two separators, never a decimal comma; this one is
      // $1,234,567, which is past the ceiling.
      expect(parseUsdInput('1,234,567'), isNull);
    });

    test('may use a comma for the point, as some keyboards do', () {
      expect(parseUsdInput('12,50'), 1250);
      expect(parseUsdInput('12,5'), 1250);
      expect(parseUsdInput('0,99'), 99);
    });

    test('is nothing when it is not an amount', () {
      for (final text in ['', ' ', r'$', '.', 'abc', '3 dollars', '1.2.3']) {
        expect(parseUsdInput(text), isNull, reason: '"$text"');
      }
    });

    test('is nothing when it is zero', () {
      for (final text in ['0', '0.00', '.0', r'$0']) {
        expect(parseUsdInput(text), isNull, reason: '"$text"');
      }
    });

    test('is nothing when it has a third decimal place', () {
      // Not a price however it is rounded, so it is not guessed at.
      expect(parseUsdInput('3.555'), isNull);
      expect(parseUsdInput('3.001'), isNull);
    });

    test('is nothing beyond the ceiling', () {
      expect(maxTypedPriceCents, 10000000);
      expect(parseUsdInput('100000'), 10000000);
      expect(parseUsdInput('100000.01'), isNull);
      expect(parseUsdInput('99999999999999999999'), isNull);
    });

    test(
      'is shown without a sign, and with cents only when there are some',
      () {
        expect(usdInputText(3000), '30');
        expect(usdInputText(3050), '30.50');
        expect(usdInputText(3005), '30.05');
        expect(usdInputText(99), '0.99');
        expect(usdInputText(100), '1');
      },
    );

    test('reads back as what it was shown as', () {
      for (final cents in [1, 99, 100, 3005, 3050, 123456, 10000000]) {
        expect(parseUsdInput(usdInputText(cents)), cents);
      }
    });
  });

  group('inches typed by hand', () {
    test('are read as typed', () {
      expect(parseInchesInput('21'), 21);
      expect(parseInchesInput('21.5'), 21.5);
      expect(parseInchesInput(' 27.25 '), 27.25);
      expect(parseInchesInput('.5'), 0.5);
      expect(parseInchesInput('21.'), 21);
    });

    test('may use a comma for the point', () {
      expect(parseInchesInput('21,5'), 21.5);
    });

    test('are nothing when they are not a measurement', () {
      for (final text in [
        '',
        ' ',
        '.',
        'abc',
        '21 in',
        '-3',
        '0',
        '0.0',
        '1.2.3',
        'NaN',
        'Infinity',
        '1e5',
        '301',
      ]) {
        expect(parseInchesInput(text), isNull, reason: '"$text"');
      }
    });

    test('are shown without trailing zeros', () {
      expect(inchesInputText(21), '21');
      expect(inchesInputText(27.5), '27.5');
      expect(inchesInputText(27.25), '27.25');
      expect(inchesInputText(100), '100');
    });
  });

  group('counts', () {
    test('are grouped in thousands', () {
      expect(groupedCount(0), '0');
      expect(groupedCount(312), '312');
      expect(groupedCount(1000), '1,000');
      expect(groupedCount(1042), '1,042');
      expect(groupedCount(1234567), '1,234,567');
    });
  });

  group('a weight', () {
    test('is ounces under a pound', () {
      expect(weightPhrase(1), '1 oz');
      expect(weightPhrase(12), '12 oz');
      expect(weightPhrase(15), '15 oz');
    });

    test('is whole pounds on the pound', () {
      expect(weightPhrase(16), '1 lb');
      expect(weightPhrase(32), '2 lb');
    });

    test('is pounds and ounces between', () {
      expect(weightPhrase(18), '1 lb 2 oz');
      expect(weightPhrase(33), '2 lb 1 oz');
      expect(weightPhrase(47), '2 lb 15 oz');
    });
  });

  group('how long ago', () {
    final now = DateTime.utc(2026, 10, 18, 12);

    String ago(Duration since) => agoPhrase(now.subtract(since), now);

    test('is just now for under a minute', () {
      expect(ago(Duration.zero), 'just now');
      expect(ago(const Duration(seconds: 59)), 'just now');
    });

    test('is minutes, then hours, then days', () {
      expect(ago(const Duration(minutes: 1)), '1 minute ago');
      expect(ago(const Duration(minutes: 5)), '5 minutes ago');
      expect(ago(const Duration(minutes: 59)), '59 minutes ago');
      expect(ago(const Duration(hours: 1)), '1 hour ago');
      expect(ago(const Duration(hours: 2, minutes: 40)), '2 hours ago');
      expect(ago(const Duration(hours: 23)), '23 hours ago');
      expect(ago(const Duration(days: 1)), '1 day ago');
      expect(ago(const Duration(days: 40)), '40 days ago');
    });

    test('is just now for a time that has not happened', () {
      // A phone with the wrong clock.
      expect(agoPhrase(now.add(const Duration(minutes: 3)), now), 'just now');
    });
  });

  group('how long a listing has been up', () {
    test('is today until a whole day has gone', () {
      expect(listedPhrase(Duration.zero), 'Listed today');
      expect(listedPhrase(const Duration(hours: 23)), 'Listed today');
    });

    test('is in days after that', () {
      expect(listedPhrase(const Duration(days: 1)), 'Listed 1 day ago');
      expect(listedPhrase(const Duration(days: 16)), 'Listed 16 days ago');
    });
  });

  group('what a search left out', () {
    test('names only the reasons that apply', () {
      expect(
        excludedPhrase(notUsd: 2, unverifiedPrice: 1, notComparable: 4),
        '2 not in US dollars, 1 price not on the page, 4 not alike',
      );
      expect(
        excludedPhrase(notUsd: 0, unverifiedPrice: 3, notComparable: 0),
        '3 prices not on the page',
      );
      expect(
        excludedPhrase(notUsd: 0, unverifiedPrice: 0, notComparable: 4),
        '4 not alike',
      );
    });

    test('is empty when nothing was left out', () {
      expect(
        excludedPhrase(notUsd: 0, unverifiedPrice: 0, notComparable: 0),
        isEmpty,
      );
    });
  });
}
