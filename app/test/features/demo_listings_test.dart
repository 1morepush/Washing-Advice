/// The sample listings and canned answers the demo build opens on.
///
/// The screenshots are taken from the demo build, so what is held here is what
/// they will show: a draft with the evidence for its price, a listing that has
/// sat long enough to be nudged, a sale. And that the links in all of it go
/// where nothing can go wrong — a shop's own address, never anything else.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/main_demo.dart';

void main() {
  final now = DateTime.utc(2026, 10, 17, 12);

  /// The demo wardrobe with a photograph on each garment, as the demo build
  /// has once its cutouts are stored.
  final wardrobe = [
    for (final item in demoWardrobe())
      item.copyWith(
        photos: PhotoSet([
          ItemPhoto(
            uri: 'wa-memory:${item.id.value}-front',
            role: PhotoRole.front,
            capturedAt: DateTime.utc(2026, 8, 5),
          ),
        ]),
      ),
  ];

  final listings = demoListings(wardrobe, now: now);
  Listing byId(String id) =>
      listings.singleWhere((listing) => listing.id.value == id);

  group('the sample listings', () {
    test('are three, one in each state', () {
      expect(listings.map((l) => l.id.value), [
        'demo-listing-1',
        'demo-listing-2',
        'demo-listing-3',
      ]);
      expect(listings.map((l) => l.status), [
        ListingStatus.draft,
        ListingStatus.listed,
        ListingStatus.sold,
      ]);
    });

    test(
      'come back newest first, as the Sell tab will be given them',
      () async {
        final stored = await InMemoryListingRepository(listings).all();

        expect(stored.map((l) => l.id.value), [
          'demo-listing-1',
          'demo-listing-2',
          'demo-listing-3',
        ]);
      },
    );

    test('can all be stored and read back', () {
      for (final listing in listings) {
        final back = Listing.fromJson(
          jsonDecode(jsonEncode(listing.toJson())) as Map<String, Object?>,
        );

        expect(back, listing, reason: listing.id.value);
      }
    });

    group('the draft', () {
      final draft = byId('demo-listing-1');

      test('is the demo jumper\'s, as "Sell this" would make it', () {
        expect(draft.itemId, const ItemId('demo-jumper'));
        expect(draft.status, ListingStatus.draft);
        // The wardrobe's brand, and the reading's title.
        expect(draft.brand, 'Uniqlo');
        expect(draft.title, 'Uniqlo merino wool crewneck sweater charcoal');
        expect(draft.itemType, ItemType.sweater);
        expect(draft.colours, [DepopColour.grey]);
        expect(draft.facts, isNotNull);
        expect(draft.flaws, contains('light pilling on the sleeves'));
        // Suggested from its wear history, for the person to confirm.
        expect(draft.condition, isNotNull);
      });

      test('shows the garment\'s own photograph', () {
        expect(draft.photos.map((p) => p.uri), ['wa-memory:demo-jumper-front']);
        expect(draft.photos.single.shot, ListingShot.cover);
      });

      test('carries a price search with all the editor shows', () {
        final search = draft.priceSearch!;

        expect(search.status, PriceSearchStatus.ok);
        expect(search.searchedAt!.isBefore(now), isTrue);
        expect(search.comparables.where((c) => c.sold == true), hasLength(2));
        expect(search.comparables.where((c) => c.sold == false), hasLength(1));
        expect(search.comparables.map((c) => c.match).toSet(), {
          ComparableMatch.same,
          ComparableMatch.similar,
        });
        expect(search.retail, isNotEmpty);
        // So the screen has something to say about what was left out.
        expect(search.excluded.total, greaterThan(0));
      });

      test('is priced at what the evidence suggests, to the cent', () {
        final search = draft.priceSearch!;

        final suggestion = suggestPrice(
          comparables: search.comparables,
          retail: search.retail,
          condition: draft.condition,
        );

        expect(suggestion.basis, PriceBasis.soldComparables);
        expect(suggestion.listPriceCents, 3000);
        expect(suggestion.netCents, 2856);
        expect(formatUsd(suggestion.netCents!), r'$28.56');
        expect(draft.priceCents, suggestion.listPriceCents);
      });
    });

    group('the listing that has been up a while', () {
      final listed = byId('demo-listing-2');

      test('is past the point a listing is worth refreshing', () {
        expect(listed.status, ListingStatus.listed);
        expect(listed.listedFor(now), const Duration(days: 16));
        expect(listed.needsRefresh(now), isTrue);
        expect(listingRefreshAfter, const Duration(days: 14));
      });

      test('is not from the wardrobe, and needs not be', () {
        expect(listed.itemId, isNull);
        expect(listed.priceCents, isNotNull);
      });

      test('is not overdue a few days earlier', () {
        expect(
          listed.needsRefresh(now.subtract(const Duration(days: 3))),
          isFalse,
        );
      });

      test('shows a demo garment\'s photograph', () {
        expect(listed.photos.single.uri, 'wa-memory:demo-jeans-front');
      });
    });

    group('the sale', () {
      final sold = byId('demo-listing-3');

      test('has a price it sold for, which was not the asking price', () {
        expect(sold.status, ListingStatus.sold);
        expect(sold.soldPriceCents, 3400);
        expect(sold.priceCents, 3800);
        expect(sold.soldAt, isNotNull);
        expect(sold.soldAt!.isAfter(sold.listedAt!), isTrue);
        expect(sold.soldAt!.isBefore(now), isTrue);
      });

      test('is not due a refresh, being done with', () {
        expect(sold.needsRefresh(now), isFalse);
      });

      test(
        'is of the blouse in the wardrobe, which is not yet marked sold',
        () {
          expect(sold.itemId, const ItemId('demo-silk'));
        },
      );

      test('shows a demo garment\'s photograph', () {
        expect(sold.photos.single.uri, 'wa-memory:demo-silk-front');
      });
    });

    test('are dated from now, so the nudge is still a nudge tomorrow', () {
      final later = demoListings(
        wardrobe,
        now: now.add(const Duration(days: 30)),
      );

      expect(
        later[1].listedFor(now.add(const Duration(days: 30))),
        const Duration(days: 16),
      );
    });

    test('use the real clock when not given one', () {
      final real = demoListings(wardrobe);

      expect(real[1].needsRefresh(DateTime.now()), isTrue);
    });

    test('still stand when the wardrobe holds no photographs', () {
      // The tests that build the wardrobe without the demo's cutouts.
      final bare = demoListings(demoWardrobe(), now: now);

      expect(bare, hasLength(3));
      expect(bare[1].photos, isEmpty);
    });
  });

  group('the demo server', () {
    final photo = ScanImage(bytes: utf8.encode('x'));

    Future<T> afterWaiting<T>(WidgetTester tester, Future<T> answer) async {
      await tester.pump(const Duration(seconds: 3));
      return answer;
    }

    testWidgets('reads the jumper off photographs of nothing in particular', (
      tester,
    ) async {
      final facts = await afterWaiting(
        tester,
        demoGateway().describeListing([photo]),
      );

      expect(facts.title, 'Uniqlo merino wool crewneck sweater charcoal');
      expect(facts.brand!.value, 'Uniqlo');
      expect(facts.searchQueries.isSearchable, isTrue);
      // No label is in a photograph of a jumper's front, so no size and no
      // fabric: the real server leaves both out, and so does the demo.
      expect(facts.sizeOnTag, isNull);
      expect(facts.material, isNull);
    });

    testWidgets('says a garment\'s record back when it is told one', (
      tester,
    ) async {
      final hoodie = wardrobe.firstWhere((i) => i.id.value == 'demo-hoodie');

      final facts = await afterWaiting(
        tester,
        demoGateway().describeListing([
          photo,
        ], context: describeContextForItem(hoodie)),
      );

      expect(facts.title, 'Nike hoodie navy');
      expect(facts.itemType, ItemType.hoodie);
      expect(facts.brand!.value, 'Nike');
      // Nothing about a garment nobody has looked at is made up.
      expect(facts.styleWords, isEmpty);
      expect(facts.visibleFlaws, isEmpty);
      expect(facts.searchQueries.isSearchable, isTrue);
    });

    testWidgets(
      'and falls back to the jumper when the record says too little',
      (tester) async {
        final facts = await afterWaiting(
          tester,
          demoGateway().describeListing([photo], context: const {}),
        );

        expect(facts.title, 'Uniqlo merino wool crewneck sweater charcoal');
      },
    );

    testWidgets('finds the same listings whatever it is asked about', (
      tester,
    ) async {
      final request = priceSearchRequestJson(
        queries: const SearchQueries(
          depop: 'phrase i corrected',
          retail: 'retail phrase i corrected',
        ),
        itemType: ItemType.hoodie,
        title: 'Nike hoodie navy',
      );

      final search = await afterWaiting(
        tester,
        demoGateway().searchPrices(request),
      );

      expect(search.status, PriceSearchStatus.ok);
      expect(search.comparables, hasLength(4));
      expect(search.retail, hasLength(1));
      // The phrases that were tried come back as the ones that were.
      expect(search.queries.depop, 'phrase i corrected');
      expect(search.queries.retail, 'retail phrase i corrected');
      expect(
        search.searchedAt!.difference(DateTime.now().toUtc()).abs(),
        lessThan(const Duration(minutes: 1)),
      );
    });

    testWidgets('and has phrases of its own when it is given none', (
      tester,
    ) async {
      final search = await afterWaiting(
        tester,
        demoGateway().searchPrices(const {}),
      );

      expect(search.queries.isSearchable, isTrue);
    });
  });

  group('every link', () {
    testWidgets('is an https address on depop.com or nike.com', (tester) async {
      // The search the draft listing carries, and the one the server gives.
      final seeded = demoListings(wardrobe, now: now).first.priceSearch!;
      final pending = demoGateway().searchPrices(const {});
      await tester.pump(const Duration(seconds: 3));
      final answered = await pending;

      final links = <Uri>[
        for (final search in [seeded, answered]) ...[
          for (final c in search.comparables) c.url,
          for (final r in search.retail) r.url,
        ],
      ];

      expect(links, isNotEmpty);
      for (final link in links) {
        expect(link.scheme, 'https', reason: '$link');
        expect(
          ['www.depop.com', 'www.nike.com'],
          contains(link.host),
          reason: '$link',
        );
      }
    });

    testWidgets('and the retail ones are the shop\'s own', (tester) async {
      final pending = demoGateway().searchPrices(const {});
      await tester.pump(const Duration(seconds: 3));
      final search = await pending;

      for (final shop in search.retail) {
        expect(shop.seller, 'nike.com');
        expect(shop.url.host, endsWith('nike.com'));
      }
      for (final listing in search.comparables) {
        expect(listing.url.host, endsWith('depop.com'));
      }
    });
  });

  test('the gateway is a real AiGateway, so it stands in for one', () {
    expect(demoGateway(), isA<AiGateway>());
  });
}
