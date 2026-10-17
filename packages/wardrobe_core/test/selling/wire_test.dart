import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

/// A describe `result` as the server sends it.
Map<String, Object?> describeResult({
  Map<String, Object?> overrides = const {},
  Iterable<String> without = const [],
}) =>
    {
      'title': 'Nike vintage crewneck sweatshirt grey',
      'itemType': 'sweatshirt',
      'brand': {'value': 'Nike', 'confidence': 0.93, 'source': 'aiInference'},
      'colors': ['Grey'],
      'material': '80% cotton, 20% polyester',
      'sizeOnTag': {'value': 'M', 'confidence': 0.9, 'source': 'aiInference'},
      'styleWords': ['vintage', 'crewneck'],
      'era': '90s',
      'visibleFlaws': ['small mark on the left cuff'],
      'searchQueries': {
        'depop': 'Nike vintage crewneck sweatshirt grey',
        'retail': 'Nike Club Fleece crew sweatshirt grey',
      },
      ...overrides,
    }..removeWhere((key, _) => without.contains(key));

/// One comparable as the server sends it.
Map<String, Object?> wireComparable({
  Map<String, Object?> overrides = const {},
  Iterable<String> without = const [],
}) =>
    {
      'title': 'Vintage Nike grey crewneck',
      'url': 'https://www.depop.com/products/example-1/',
      'price': 32.0,
      'currency': 'USD',
      'sold': true,
      'condition': 'Used - Excellent',
      'match': 'same',
      'why': 'Same 90s Nike crewneck, also grey',
      ...overrides,
    }..removeWhere((key, _) => without.contains(key));

Map<String, Object?> wireRetail({
  Map<String, Object?> overrides = const {},
  Iterable<String> without = const [],
}) =>
    {
      'title': 'Nike Sportswear Club Fleece Crew',
      'url': 'https://www.nike.com/t/club-fleece-crew',
      'price': 60.0,
      'currency': 'USD',
      'seller': 'nike.com',
      'match': 'similar',
      ...overrides,
    }..removeWhere((key, _) => without.contains(key));

Map<String, Object?> pricesResult({
  String status = 'ok',
  List<Object?>? comparables,
  List<Object?>? retail,
  Map<String, Object?> overrides = const {},
}) =>
    {
      'status': status,
      'searchedAt': '2026-10-17T14:05:00Z',
      'provider': 'tavily',
      'queries': {
        'depop': 'Nike vintage crewneck sweatshirt grey',
        'retail': 'Nike Club Fleece crew sweatshirt grey',
      },
      'comparables': comparables ?? [wireComparable()],
      'retail': retail ?? [wireRetail()],
      'excluded': {'notUsd': 2, 'unverifiedPrice': 1, 'notComparable': 4},
      ...overrides,
    };

void main() {
  group('listingFactsFromJson', () {
    test('reads a description', () {
      final facts = listingFactsFromJson(describeResult());

      expect(facts.title, 'Nike vintage crewneck sweatshirt grey');
      expect(facts.itemType, ItemType.sweatshirt);
      expect(facts.brand!.value, 'Nike');
      expect(facts.brand!.confidence, closeTo(0.93, 1e-9));
      expect(facts.brand!.source, Provenance.aiInference);
      expect(facts.colors, ['Grey']);
      expect(facts.material, '80% cotton, 20% polyester');
      expect(facts.sizeOnTag!.value, 'M');
      expect(facts.styleWords, ['vintage', 'crewneck']);
      expect(facts.era, '90s');
      expect(facts.visibleFlaws, ['small mark on the left cuff']);
      expect(
          facts.searchQueries.depop, 'Nike vintage crewneck sweatshirt grey');
      expect(
        facts.searchQueries.retail,
        'Nike Club Fleece crew sweatshirt grey',
      );
    });

    test('reads what the photographs did not show as absent', () {
      final facts = listingFactsFromJson(
        describeResult(
          without: const ['brand', 'material', 'sizeOnTag', 'era'],
          overrides: const {
            'colors': <Object?>[],
            'styleWords': <Object?>[],
            'visibleFlaws': <Object?>[],
          },
        ),
      );

      expect(facts.brand, isNull);
      expect(facts.material, isNull);
      expect(facts.sizeOnTag, isNull);
      expect(facts.era, isNull);
      expect(facts.colors, isEmpty);
      expect(facts.styleWords, isEmpty);
      expect(facts.visibleFlaws, isEmpty);
    });

    test('reads an item type this build does not know as Other', () {
      final facts = listingFactsFromJson(
        describeResult(overrides: const {'itemType': 'poncho'}),
      );

      expect(facts.itemType, ItemType.other);
    });

    test('reads every item type the core knows by its Dart name', () {
      for (final type in ItemType.values) {
        final facts = listingFactsFromJson(
          describeResult(overrides: {'itemType': type.name}),
        );

        expect(facts.itemType, type);
      }
    });

    test('refuses a description with no title, so the app can fall back', () {
      expect(
        () => listingFactsFromJson(describeResult(without: const ['title'])),
        throwsFormatException,
      );
      expect(
        () => listingFactsFromJson(
          describeResult(overrides: const {'title': '   '}),
        ),
        throwsFormatException,
      );
      expect(
        () => listingFactsFromJson(
          describeResult(overrides: const {'title': 42}),
        ),
        throwsFormatException,
      );
    });

    test('stands the title in for search phrases that are missing', () {
      final facts = listingFactsFromJson(
        describeResult(without: const ['searchQueries']),
      );

      expect(facts.searchQueries.depop, facts.title);
      expect(facts.searchQueries.retail, facts.title);
    });

    test('does not trust a brand to be confident when it did not say', () {
      final facts = listingFactsFromJson(
        describeResult(
          overrides: const {
            'brand': {'value': 'Nike'},
          },
        ),
      );

      expect(facts.brand!.confidence, 0.0);
    });
  });

  group('priceSearchFromJson', () {
    PriceSearch read([Map<String, Object?>? result]) =>
        priceSearchFromJson(result ?? pricesResult());

    test('reads a search', () {
      final search = read();

      expect(search.status, PriceSearchStatus.ok);
      expect(search.searchedAt, DateTime.utc(2026, 10, 17, 14, 5));
      expect(search.searchedAt!.isUtc, isTrue);
      expect(search.provider, 'tavily');
      expect(search.queries.depop, 'Nike vintage crewneck sweatshirt grey');
      expect(search.queries.retail, 'Nike Club Fleece crew sweatshirt grey');
      expect(search.excluded.notUsd, 2);
      expect(search.excluded.unverifiedPrice, 1);
      expect(search.excluded.notComparable, 4);
      expect(search.excluded.total, 7);
    });

    test('reads a comparable', () {
      final comparable = read().comparables.single;

      expect(comparable.title, 'Vintage Nike grey crewneck');
      expect(
        comparable.url,
        Uri.parse('https://www.depop.com/products/example-1/'),
      );
      expect(comparable.priceCents, 3200);
      expect(comparable.sold, isTrue);
      expect(comparable.condition, 'Used - Excellent');
      expect(comparable.match, ComparableMatch.same);
      expect(comparable.why, 'Same 90s Nike crewneck, also grey');
    });

    test('reads a retail reference', () {
      final retail = read().retail.single;

      expect(retail.title, 'Nike Sportswear Club Fleece Crew');
      expect(retail.url, Uri.parse('https://www.nike.com/t/club-fleece-crew'));
      expect(retail.priceCents, 6000);
      expect(retail.seller, 'nike.com');
      expect(retail.match, ComparableMatch.similar);
    });

    group('turns dollars into cents', () {
      int centsFor(Object? price) => read(
            pricesResult(comparables: [
              wireComparable(overrides: {'price': price})
            ]),
          ).comparables.single.priceCents;

      test('exactly', () {
        expect(centsFor(28.56), 2856);
        expect(centsFor(19.99), 1999);
        expect(centsFor(1234.5), 123450);
      });

      test('rounding away floating-point noise', () {
        // 0.29 * 100 is 28.999999999999996 in a double.
        expect(centsFor(0.29), 29);
        expect(centsFor(4.35), 435);
        expect(centsFor(8.2), 820);
      });

      test('from a whole number', () {
        expect(centsFor(30), 3000);
      });

      test('to the nearest cent when there are fractions of one', () {
        expect(centsFor(10.004), 1000);
        expect(centsFor(10.006), 1001);
      });

      test('for the dearest price the contract carries', () {
        expect(centsFor(100000), 10000000);
      });
    });

    group('skips a comparable instead of throwing', () {
      List<SaleComparable> comparablesFrom(
              List<Map<String, Object?>> entries) =>
          read(pricesResult(comparables: entries)).comparables;

      test('whose link is not https', () {
        for (final url in [
          'http://www.depop.com/products/x/',
          'javascript:alert(1)',
          'ftp://www.depop.com/x',
          '/products/x/',
          'www.depop.com/products/x/',
          'https://',
          '',
          '   ',
        ]) {
          expect(
            comparablesFrom([
              wireComparable(overrides: {'url': url})
            ]),
            isEmpty,
            reason: 'url "$url"',
          );
        }
      });

      test('whose link is missing or not text', () {
        expect(
            comparablesFrom([
              wireComparable(without: const ['url'])
            ]),
            isEmpty);
        expect(
            comparablesFrom([
              wireComparable(overrides: {'url': 42})
            ]),
            isEmpty);
        expect(
            comparablesFrom([
              wireComparable(overrides: {'url': null})
            ]),
            isEmpty);
      });

      test('whose price is missing', () {
        expect(
            comparablesFrom([
              wireComparable(without: const ['price'])
            ]),
            isEmpty);
        expect(
            comparablesFrom([
              wireComparable(overrides: {'price': null})
            ]),
            isEmpty);
      });

      test('whose price is nothing, negative or not a number', () {
        for (final price in [
          0,
          0.0,
          -5,
          -0.01,
          '28.00',
          true,
          0.004,
          double.nan,
          double.infinity
        ]) {
          expect(
            comparablesFrom([
              wireComparable(overrides: {'price': price})
            ]),
            isEmpty,
            reason: 'price $price',
          );
        }
      });

      test('whose price is beyond what the contract carries', () {
        expect(
          comparablesFrom([
            wireComparable(overrides: {'price': 100000.01})
          ]),
          isEmpty,
        );
      });

      test('whose price is in another currency, without converting it', () {
        for (final currency in ['EUR', 'GBP', 'usd', r'US$', '']) {
          expect(
            comparablesFrom([
              wireComparable(overrides: {'currency': currency})
            ]),
            isEmpty,
            reason: 'currency "$currency"',
          );
        }
      });

      test('whose currency is not given, since it cannot be known to be US',
          () {
        expect(
            comparablesFrom([
              wireComparable(without: const ['currency'])
            ]),
            isEmpty);
      });

      test('with no title', () {
        expect(
            comparablesFrom([
              wireComparable(without: const ['title'])
            ]),
            isEmpty);
        expect(
            comparablesFrom([
              wireComparable(overrides: {'title': '  '})
            ]),
            isEmpty);
      });

      test('and keeps the ones either side of it, in order', () {
        final kept = comparablesFrom([
          wireComparable(overrides: {'title': 'first', 'price': 10.0}),
          wireComparable(
              overrides: {'title': 'bad link', 'url': 'http://x.com'}),
          wireComparable(overrides: {'title': 'second', 'price': 20.0}),
          wireComparable(
              overrides: {'title': 'no price'}, without: const ['price']),
          wireComparable(overrides: {'title': 'third', 'price': 30.0}),
        ]);

        expect([for (final c in kept) c.title], ['first', 'second', 'third']);
        expect([for (final c in kept) c.priceCents], [1000, 2000, 3000]);
      });

      test('and ignores an entry that is not an object at all', () {
        final kept = read(
          pricesResult(
            comparables: ['nonsense', 7, null, wireComparable()],
          ),
        ).comparables;

        expect(kept, hasLength(1));
      });

      test('without adding to the counts the server reported', () {
        // The server counted what it dropped; the app dropping more is its own
        // business and must not rewrite that.
        final search = read(
          pricesResult(
            comparables: [
              wireComparable(overrides: {'currency': 'EUR'})
            ],
          ),
        );

        expect(search.comparables, isEmpty);
        expect(search.excluded.total, 7);
      });
    });

    group('skips a retail reference instead of throwing', () {
      List<RetailReference> retailFrom(List<Map<String, Object?>> entries) =>
          read(pricesResult(retail: entries)).retail;

      test('whose link is not https', () {
        expect(
          retailFrom([
            wireRetail(overrides: {'url': 'http://www.nike.com/x'})
          ]),
          isEmpty,
        );
      });

      test('whose price is missing, nothing or in another currency', () {
        expect(
            retailFrom([
              wireRetail(without: const ['price'])
            ]),
            isEmpty);
        expect(
            retailFrom([
              wireRetail(overrides: {'price': 0})
            ]),
            isEmpty);
        expect(
            retailFrom([
              wireRetail(overrides: {'currency': 'EUR'})
            ]),
            isEmpty);
      });

      test('and keeps the rest', () {
        final kept = retailFrom([
          wireRetail(overrides: {'currency': 'GBP'}),
          wireRetail(overrides: {'price': 55.5}),
        ]);

        expect(kept.single.priceCents, 5550);
      });

      test('reads a reference with no seller', () {
        expect(
            retailFrom([
              wireRetail(without: const ['seller'])
            ]).single.seller,
            isNull);
      });
    });

    test('reads a sold state only when the page said one', () {
      List<bool?> soldFor(List<Object?> values) => [
            for (final c in read(
              pricesResult(
                comparables: [
                  for (final v in values)
                    wireComparable(overrides: {'sold': v}),
                ],
              ),
            ).comparables)
              c.sold,
          ];

      expect(soldFor([true, false, null, 'yes', 1]),
          [true, false, null, null, null]);
    });

    test('keeps an absent sold state absent', () {
      final comparable = read(
        pricesResult(comparables: [
          wireComparable(without: const ['sold'])
        ]),
      ).comparables.single;

      expect(comparable.sold, isNull);
    });

    test('reads a match this build does not know as similar', () {
      final comparable = read(
        pricesResult(comparables: [
          wireComparable(overrides: {'match': 'exact'})
        ]),
      ).comparables.single;

      expect(comparable.match, ComparableMatch.similar);
    });

    test('reads an absent condition and reason as absent', () {
      final comparable = read(
        pricesResult(
          comparables: [
            wireComparable(without: const ['condition', 'why'])
          ],
        ),
      ).comparables.single;

      expect(comparable.condition, isNull);
      expect(comparable.why, isNull);
    });

    group('the status', () {
      test('is read for each the contract names', () {
        for (final status in PriceSearchStatus.values) {
          expect(read(pricesResult(status: status.name)).status, status);
        }
      });

      test('is unavailable when it is one this build does not know', () {
        expect(read(pricesResult(status: 'rateLimited')).status,
            PriceSearchStatus.unavailable);
        expect(read(pricesResult(status: '')).status,
            PriceSearchStatus.unavailable);
      });

      test('is unavailable when it is missing', () {
        final result = pricesResult()..remove('status');

        expect(read(result).status, PriceSearchStatus.unavailable);
      });

      test('comes with empty lists unless it is ok', () {
        final search = read(
          pricesResult(
            status: 'notConfigured',
            comparables: const [],
            retail: const [],
            overrides: {
              'excluded': {
                'notUsd': 0,
                'unverifiedPrice': 0,
                'notComparable': 0
              },
            },
          )
            ..remove('searchedAt')
            ..remove('provider'),
        );

        expect(search.status, PriceSearchStatus.notConfigured);
        expect(search.comparables, isEmpty);
        expect(search.retail, isEmpty);
        expect(search.searchedAt, isNull);
        expect(search.provider, isNull);
        expect(search.excluded.total, 0);
        expect(search.queries.depop, isNotEmpty);
      });
    });

    test('reads a time it cannot parse as absent', () {
      expect(
          read(pricesResult(overrides: {'searchedAt': 'yesterday'})).searchedAt,
          isNull);
    });

    test('reads a time with an offset as the same instant in UTC', () {
      final search = read(
        pricesResult(overrides: {'searchedAt': '2026-10-17T16:05:00+02:00'}),
      );

      expect(search.searchedAt, DateTime.utc(2026, 10, 17, 14, 5));
    });

    test('reads missing counts and phrases as none', () {
      final search = read(
        pricesResult()
          ..remove('excluded')
          ..remove('queries'),
      );

      expect(search.excluded.total, 0);
      expect(search.queries.isSearchable, isFalse);
    });

    test('reads a response with missing lists as having no results', () {
      final search = read(
        pricesResult()
          ..remove('comparables')
          ..remove('retail'),
      );

      expect(search.comparables, isEmpty);
      expect(search.retail, isEmpty);
    });

    test('can be priced straight away', () {
      final search = read(
        pricesResult(
          comparables: [
            wireComparable(overrides: {'price': 32.0, 'sold': true}),
            wireComparable(overrides: {'price': 28.0, 'sold': false}),
          ],
        ),
      );
      final suggestion = suggestPrice(
        comparables: search.comparables,
        retail: search.retail,
        condition: DepopCondition.usedExcellent,
      );

      expect(suggestion.listPriceCents, 3000);
      expect(suggestion.netCents, 2856);
    });
  });

  group('priceSearchRequestJson', () {
    const queries = SearchQueries(
      depop: 'Nike vintage crewneck sweatshirt grey',
      retail: 'Nike Club Fleece crew sweatshirt grey',
    );

    test('writes the contract\'s body', () {
      expect(
        priceSearchRequestJson(
          queries: queries,
          itemType: ItemType.sweatshirt,
          title: 'Nike vintage crewneck sweatshirt grey',
          brand: 'Nike',
          colors: const ['Grey'],
        ),
        {
          'queries': {
            'depop': 'Nike vintage crewneck sweatshirt grey',
            'retail': 'Nike Club Fleece crew sweatshirt grey',
          },
          'itemType': 'sweatshirt',
          'title': 'Nike vintage crewneck sweatshirt grey',
          'brand': 'Nike',
          'colors': ['Grey'],
        },
      );
    });

    test('leaves out a brand there is not', () {
      for (final brand in [null, '', '   ']) {
        final body = priceSearchRequestJson(
          queries: queries,
          itemType: ItemType.hoodie,
          title: 'Grey hoodie',
          brand: brand,
        );

        expect(body.containsKey('brand'), isFalse, reason: '"$brand"');
      }
    });

    test('leaves out colours when there are none', () {
      final body = priceSearchRequestJson(
        queries: queries,
        itemType: ItemType.hoodie,
        title: 'Grey hoodie',
        colors: const ['', '  '],
      );

      expect(body.containsKey('colors'), isFalse);
    });

    test('sends the item type by its name', () {
      for (final type in ItemType.values) {
        expect(
          priceSearchRequestJson(
            queries: queries,
            itemType: type,
            title: 'Grey hoodie',
          )['itemType'],
          type.name,
        );
      }
    });

    test('trims what it sends', () {
      final body = priceSearchRequestJson(
        queries:
            const SearchQueries(depop: '  grey hoodie  ', retail: ' nike '),
        itemType: ItemType.hoodie,
        title: '  Grey hoodie ',
        brand: ' Nike ',
        colors: const [' Grey '],
      );

      expect(body['queries'], {'depop': 'grey hoodie', 'retail': 'nike'});
      expect(body['title'], 'Grey hoodie');
      expect(body['brand'], 'Nike');
      expect(body['colors'], ['Grey']);
    });

    test('cuts a title, brand and phrases to the lengths the server takes', () {
      final body = priceSearchRequestJson(
        queries: SearchQueries(depop: 'd' * 500, retail: 'r' * 500),
        itemType: ItemType.hoodie,
        title: 't' * 500,
        brand: 'b' * 500,
      );

      expect((body['title']! as String).length, 80);
      expect((body['brand']! as String).length, 60);
      expect(
          ((body['queries']! as Map<String, Object?>)['depop']! as String)
              .length,
          120);
      expect(
          ((body['queries']! as Map<String, Object?>)['retail']! as String)
              .length,
          120);
    });

    test('sends at most three colours, each cut to 30 characters', () {
      final body = priceSearchRequestJson(
        queries: queries,
        itemType: ItemType.hoodie,
        title: 'Grey hoodie',
        colors: ['c' * 100, 'Navy', '', 'White', 'Red', 'Green'],
      );

      expect(body['colors'], ['c' * 30, 'Navy', 'White']);
    });

    test('cuts by character, not through the middle of an emoji', () {
      final body = priceSearchRequestJson(
        queries: queries,
        itemType: ItemType.hoodie,
        title: '😀' * 100,
      );
      final title = body['title']! as String;

      expect(title.runes.length, 80);
      expect(title, '😀' * 80);
    });

    test('does not leave a space at the end of a cut phrase', () {
      final body = priceSearchRequestJson(
        queries: queries,
        itemType: ItemType.hoodie,
        title: '${'a' * 79} bbbbb',
      );

      expect(body['title'], 'a' * 79);
    });

    test('has exactly the keys the contract allows', () {
      final body = priceSearchRequestJson(
        queries: queries,
        itemType: ItemType.hoodie,
        title: 'Grey hoodie',
        brand: 'Nike',
        colors: const ['Grey'],
      );

      expect(body.keys.toSet(),
          {'queries', 'itemType', 'title', 'brand', 'colors'});
      expect((body['queries']! as Map<String, Object?>).keys.toSet(),
          {'depop', 'retail'});
    });
  });

  group('describeContextJson', () {
    test('writes the contract\'s context', () {
      expect(
        describeContextJson(
          itemType: ItemType.sweatshirt,
          brand: 'Nike',
          colors: const ['Grey'],
          material: '80% cotton, 20% polyester',
          sizeLabel: 'M',
          notes: 'Bought in 2019, worn a handful of times',
        ),
        {
          'known': {
            'itemType': 'sweatshirt',
            'brand': 'Nike',
            'colors': ['Grey'],
            'material': '80% cotton, 20% polyester',
            'sizeLabel': 'M',
          },
          'notes': 'Bought in 2019, worn a handful of times',
        },
      );
    });

    test('is empty when nothing is known', () {
      expect(describeContextJson(), isEmpty);
      expect(
        describeContextJson(
            brand: '  ', colors: const [''], material: '', notes: ' '),
        isEmpty,
      );
    });

    test('sends only what is known', () {
      expect(describeContextJson(brand: 'Nike'), {
        'known': {'brand': 'Nike'},
      });
      expect(describeContextJson(sizeLabel: 'M'), {
        'known': {'sizeLabel': 'M'},
      });
    });

    test('sends notes without a known section when that is all there is', () {
      expect(
          describeContextJson(notes: 'Worn twice.'), {'notes': 'Worn twice.'});
    });

    test('trims what it sends', () {
      expect(
        describeContextJson(brand: '  Nike ', sizeLabel: ' M ', notes: ' hi '),
        {
          'known': {'brand': 'Nike', 'sizeLabel': 'M'},
          'notes': 'hi',
        },
      );
    });

    test('cuts each field to the length the server takes', () {
      final context = describeContextJson(
        brand: 'b' * 200,
        material: 'm' * 500,
        sizeLabel: 's' * 100,
        notes: 'n' * 900,
        colors: ['c' * 90, 'Navy', 'White', 'Red'],
      );
      final known = context['known']! as Map<String, Object?>;

      expect((known['brand']! as String).length, 60);
      expect((known['material']! as String).length, 120);
      expect((known['sizeLabel']! as String).length, 30);
      expect((context['notes']! as String).length, 300);
      expect(known['colors'], ['c' * 30, 'Navy', 'White']);
    });

    test('has exactly the keys the contract allows', () {
      final context = describeContextJson(
        itemType: ItemType.hoodie,
        brand: 'Nike',
        colors: const ['Grey'],
        material: 'cotton',
        sizeLabel: 'M',
        notes: 'hi',
      );

      expect(context.keys.toSet(), {'known', 'notes'});
      expect((context['known']! as Map<String, Object?>).keys.toSet(), {
        'itemType',
        'brand',
        'colors',
        'material',
        'sizeLabel',
      });
    });
  });

  group('describeContextForItem', () {
    WardrobeItem sweatshirt({
      String? brand = 'Nike',
      String? sizeLabel = 'M',
      List<ItemColor>? colors,
      ItemType type = ItemType.sweatshirt,
      int timesWorn = 0,
    }) =>
        buildItem(
          type: type,
          brand: brand,
          sizeLabel: sizeLabel,
          colors: colors ?? [Colors.grey],
          composition: const {Fiber.cotton: 80, Fiber.polyester: 20},
          usage: UsageStats(timesWorn: timesWorn),
        );

    test('says what the wardrobe knows about the garment', () {
      expect(describeContextForItem(sweatshirt(timesWorn: 12)), {
        'known': {
          'itemType': 'sweatshirt',
          'brand': 'Nike',
          'colors': ['Grey'],
          'material': '80% Cotton, 20% Polyester',
          'sizeLabel': 'M',
        },
        'notes': 'Worn 12 times.',
      });
    });

    test('says how often it has been worn', () {
      String? notesFor(int times) =>
          describeContextForItem(sweatshirt(timesWorn: times))['notes']
              as String?;

      expect(notesFor(12), 'Worn 12 times.');
      expect(notesFor(2), 'Worn 2 times.');
      expect(notesFor(1), 'Worn once.');
    });

    test('says nothing about wear for something never worn', () {
      expect(
          describeContextForItem(sweatshirt()).containsKey('notes'), isFalse);
    });

    test('adds what the person typed in the garment\'s notes', () {
      final item = sweatshirt(timesWorn: 3).copyWith(
        notes: 'Bought in 2019',
      );

      expect(describeContextForItem(item)['notes'],
          'Worn 3 times. Bought in 2019');
    });

    test('sends the typed notes alone for something never worn', () {
      final item = sweatshirt().copyWith(notes: '  Bought in 2019  ');

      expect(describeContextForItem(item)['notes'], 'Bought in 2019');
    });

    test('cuts long notes to 300 characters and keeps the wear line', () {
      final item = sweatshirt(timesWorn: 12).copyWith(notes: 'n' * 1000);
      final notes = describeContextForItem(item)['notes']! as String;

      expect(notes.length, 300);
      expect(notes, startsWith('Worn 12 times. nnn'));
    });

    test('leaves out a type that is just Other', () {
      // The wardrobe had no better word, which is not something the
      // photographs should be held to.
      final known = describeContextForItem(
        sweatshirt(type: ItemType.other),
      )['known']! as Map<String, Object?>;

      expect(known.containsKey('itemType'), isFalse);
    });

    test('leaves out a brand or size there is not', () {
      final known = describeContextForItem(
        sweatshirt(brand: null, sizeLabel: null),
      )['known']! as Map<String, Object?>;

      expect(known.containsKey('brand'), isFalse);
      expect(known.containsKey('sizeLabel'), isFalse);
    });

    test('sends colour names, dominant first, and not hex codes', () {
      final item = sweatshirt(
        colors: [
          Colors.navy.copyWith(coverage: 0.7),
          Colors.white.copyWith(coverage: 0.3),
          ItemColor.fromHex('#123456', name: '#123456').copyWith(coverage: 0.1),
          ItemColor.fromHex('#654321').copyWith(coverage: 0.05),
        ],
      );
      final known =
          describeContextForItem(item)['known']! as Map<String, Object?>;

      expect(known['colors'], ['Navy', 'White']);
    });

    test('sends the fabric when a label stated it', () {
      final known = describeContextForItem(sweatshirt())['known']!
          as Map<String, Object?>;

      expect(known['material'], '80% Cotton, 20% Polyester');
    });

    test('sends the fabric when the person typed it', () {
      final item = sweatshirt().copyWith(
        composition: Confident.fromUser(
          FabricComposition(const {Fiber.wool: 100}),
        ),
      );
      final known =
          describeContextForItem(item)['known']! as Map<String, Object?>;

      expect(known['material'], '100% Wool');
    });

    test('does not send a fabric that was only a guess from a photograph', () {
      // "Known" means known. Sending the server its own guess back as a fact
      // would make it the one thing the description could not be corrected on.
      final item = sweatshirt().copyWith(
        composition: Confident(
          FabricComposition(const {Fiber.cotton: 100}),
          confidence: 0.4,
          source: Provenance.aiInference,
        ),
      );
      final known =
          describeContextForItem(item)['known']! as Map<String, Object?>;

      expect(known.containsKey('material'), isFalse);
    });

    test('does not send an unknown fabric as "Unknown composition"', () {
      final item = sweatshirt().copyWith(
        composition: Confident(
          FabricComposition.unknown(),
          confidence: 0.9,
          source: Provenance.tagScan,
        ),
      );
      final known =
          describeContextForItem(item)['known']! as Map<String, Object?>;

      expect(known.containsKey('material'), isFalse);
    });

    test('leaves everything out for a garment that says nothing', () {
      final item = sweatshirt(
        brand: null,
        sizeLabel: null,
        type: ItemType.other,
        colors: [ItemColor.fromHex('#123456')],
      ).copyWith(
        composition: Confident(
          FabricComposition.unknown(),
          confidence: 0.0,
          source: Provenance.fallbackDefault,
        ),
      );

      expect(describeContextForItem(item), isEmpty);
    });

    test('has exactly the keys the contract allows', () {
      final context = describeContextForItem(
        sweatshirt(timesWorn: 3).copyWith(notes: 'x'),
      );

      expect(context.keys.toSet(), {'known', 'notes'});
      expect((context['known']! as Map<String, Object?>).keys.toSet(), {
        'itemType',
        'brand',
        'colors',
        'material',
        'sizeLabel',
      });
    });
  });
}
