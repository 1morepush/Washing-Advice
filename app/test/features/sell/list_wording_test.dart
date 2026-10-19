/// The words and sums behind the Sell tab, without the tab.
///
/// The screen tests read these off cards; this is the same thing at its edges —
/// the minute that becomes an hour, the day that is a calendar day and not a
/// moment, the sale with no price in a total — where one line is clearer than a
/// scroll through a list.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/features/sell/list/listing_groups.dart';
import 'package:washing_advice/features/sell/list/listing_money.dart';
import 'package:washing_advice/features/sell/list/listing_when.dart';

void main() {
  group('how long ago', () {
    test('is just now for under a minute', () {
      expect(timeAgo(Duration.zero), 'just now');
      expect(timeAgo(const Duration(seconds: 59)), 'just now');
    });

    test('is minutes, hours and days as the app says them elsewhere', () {
      expect(timeAgo(const Duration(minutes: 5)), '5 minutes ago');
      expect(timeAgo(const Duration(hours: 3)), '3 hours ago');
      expect(timeAgo(const Duration(days: 16)), '16 days ago');
    });

    test('moves to the next unit at the boundary and not before', () {
      expect(
        timeAgo(const Duration(minutes: 59, seconds: 59)),
        '59 minutes ago',
      );
      expect(timeAgo(const Duration(hours: 1)), '1 hour ago');
      expect(timeAgo(const Duration(hours: 23, minutes: 59)), '23 hours ago');
      expect(timeAgo(const Duration(days: 1)), '1 day ago');
    });

    test('is singular where it is one', () {
      expect(timeAgo(const Duration(minutes: 1)), '1 minute ago');
      expect(timeAgo(const Duration(hours: 1)), '1 hour ago');
      expect(timeAgo(const Duration(days: 1)), '1 day ago');
    });

    test('is just now for a clock that is a little behind', () {
      expect(timeAgo(const Duration(minutes: -3)), 'just now');
    });
  });

  group('weeks', () {
    test('are whole ones', () {
      expect(weeksLabel(const Duration(days: 14)), '2 weeks');
      expect(weeksLabel(const Duration(days: 20)), '2 weeks');
      expect(weeksLabel(const Duration(days: 21)), '3 weeks');
    });

    test('are never one in a nudge, which comes at two', () {
      expect(weeksLabel(listingRefreshAfter), '2 weeks');
      expect(weeksLabel(const Duration(days: 7)), '1 week');
    });
  });

  group('a date', () {
    test('is short for a moment, in the phone\'s own day', () {
      // Local, so the day does not depend on where the test runs.
      expect(shortDate(DateTime(2026, 9, 25, 12)), '25 Sep 2026');
      expect(shortDate(DateTime(2026, 1, 3, 23, 59)), '3 Jan 2026');
    });

    test('is long for a calendar day, which no time zone moves', () {
      expect(calendarDate(DateTime.utc(2026, 10, 17)), '17 October 2026');
      expect(calendarDate(DepopFees.us.asOf), '17 October 2026');
    });
  });

  group('the money', () {
    test(
      'is the asking price and what the fee leaves, as the briefing has it',
      () {
        expect(askingLine(3000), r'$30.00 · you get $28.56');
      },
    );

    test('is a sale as what it sold for and what was left', () {
      expect(soldLine(3400), r'Sold for $34.00 · you got $32.43');
    });

    test('is netted by the core\'s fees and nothing of the app\'s', () {
      for (final cents in [100, 999, 2500, 3000, 12345]) {
        expect(netOf(cents), DepopFees.us.netCents(cents), reason: '$cents');
      }
    });

    test('names the fee and the day it was checked', () {
      final note = feeNote();

      expect(note, contains(DepopFees.us.label));
      expect(note, contains('17 October 2026'));
      expect(note, contains('Check Depop\'s fee page'));
    });
  });

  group('the sections', () {
    Listing listing(String id, ListingStatus status, {int? sold}) => Listing(
      id: ListingId(id),
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
      status: status,
      soldPriceCents: sold,
    );

    test('split listings by where they have got to, keeping their order', () {
      final groups = ListingGroups.of([
        listing('a', ListingStatus.sold),
        listing('b', ListingStatus.draft),
        listing('c', ListingStatus.listed),
        listing('d', ListingStatus.draft),
        listing('e', ListingStatus.sold),
      ]);

      expect(groups.drafts.map((l) => l.id.value), ['b', 'd']);
      expect(groups.listed.map((l) => l.id.value), ['c']);
      expect(groups.sold.map((l) => l.id.value), ['a', 'e']);
      expect(groups.isEmpty, isFalse);
    });

    test('are empty for no listings', () {
      expect(ListingGroups.of(const []).isEmpty, isTrue);
    });

    test('cannot be changed from outside', () {
      final groups = ListingGroups.of([listing('a', ListingStatus.draft)]);

      expect(
        () => groups.drafts.add(listing('b', ListingStatus.draft)),
        throwsUnsupportedError,
      );
    });
  });

  group('the sold total', () {
    Listing sold(int? paid) => Listing(
      id: const ListingId('s'),
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
      status: ListingStatus.sold,
      soldPriceCents: paid,
    );

    test('adds up what each sale left after fees', () {
      final totals = SoldTotals.of([sold(3400), sold(5000)]);

      // $32.43 and $47.90.
      expect(totals.count, 2);
      expect(totals.netCents, 3243 + 4790);
      expect(totals.summary, r'2 sold · you got $80.33 after fees');
    });

    test('is nothing for nothing', () {
      final totals = SoldTotals.of(const []);

      expect(totals.count, 0);
      expect(totals.netCents, 0);
      expect(totals.summary, r'0 sold · you got $0.00 after fees');
    });

    test('counts a sale with no price and adds nothing for it', () {
      final totals = SoldTotals.of([sold(3400), sold(null)]);

      expect(totals.count, 2);
      expect(totals.withoutPrice, 1);
      expect(totals.netCents, 3243);
      expect(
        totals.summary,
        r'2 sold · you got $32.43 after fees · 1 has no price recorded',
      );
    });

    test('says how many, when several had no price', () {
      final totals = SoldTotals.of([sold(null), sold(null), sold(3400)]);

      expect(
        totals.summary,
        r'3 sold · you got $32.43 after fees · 2 have no price recorded',
      );
    });

    test('is taken from what it sold for and not what it was asked', () {
      final asked = sold(3400).copyWith(priceCents: 3800);

      expect(SoldTotals.of([asked]).netCents, netOf(3400));
    });
  });
}
