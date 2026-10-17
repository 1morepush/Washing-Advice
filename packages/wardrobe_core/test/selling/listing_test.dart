import 'dart:convert';

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/selling_fixtures.dart';

final created = listingCreated;

Listing draft({
  List<ListingPhoto> photos = const [],
  List<String> flaws = const [],
  String title = 'Nike crewneck',
}) =>
    draftListing(photos: photos, flaws: flaws, title: title);

ListingPhoto photo(ListingShot shot) =>
    ListingPhoto(uri: 'store://${shot.name}.jpg', shot: shot);

void main() {
  group('a new listing', () {
    test('is a draft that has not been posted or sold', () {
      final listing = draft();

      expect(listing.status, ListingStatus.draft);
      expect(listing.listedAt, isNull);
      expect(listing.soldAt, isNull);
      expect(listing.soldPriceCents, isNull);
      expect(listing.priceCents, isNull);
    });

    test('has nothing filled in that nobody said', () {
      final listing = Listing(
        id: const ListingId('x'),
        createdAt: created,
        updatedAt: created,
      );

      expect(listing.title, '');
      expect(listing.itemType, ItemType.other);
      expect(listing.condition, isNull);
      expect(listing.department, isNull);
      expect(listing.brand, isNull);
      expect(listing.colours, isEmpty);
      expect(listing.measurements.isEmpty, isTrue);
      expect(listing.flaws, isEmpty);
      expect(listing.photos, isEmpty);
      expect(listing.typedComparableCents, isEmpty);
      expect(listing.typedComparablesSold, isFalse);
    });

    test('keeps its lists out of reach of whoever built them', () {
      final flaws = ['small mark'];
      final listing = draft(flaws: flaws);
      flaws.add('later');

      expect(listing.flaws, ['small mark']);
      expect(() => listing.flaws.add('x'), throwsUnsupportedError);
      expect(() => listing.photos.add(photo(ListingShot.cover)),
          throwsUnsupportedError);
      expect(
          () => listing.colours.add(DepopColour.red), throwsUnsupportedError);
      expect(() => listing.styleWords.add('x'), throwsUnsupportedError);
      expect(
        () => listing.typedComparableCents.add(100),
        throwsUnsupportedError,
      );
    });
  });

  group('missing photographs', () {
    test('a listing with none is asked for the four that every one needs', () {
      expect(draft().missingShots, {
        ListingShot.cover,
        ListingShot.back,
        ListingShot.brandTag,
        ListingShot.sizeLabel,
      });
    });

    test('asks for them in the order the checklist shows them', () {
      expect(draft().missingShots.toList(), [
        ListingShot.cover,
        ListingShot.back,
        ListingShot.brandTag,
        ListingShot.sizeLabel,
      ]);
    });

    test('stops asking for what has been taken', () {
      final listing = draft(
        photos: [photo(ListingShot.cover), photo(ListingShot.brandTag)],
      );

      expect(listing.missingShots, {ListingShot.back, ListingShot.sizeLabel});
    });

    test('is empty once all four are taken', () {
      final listing = draft(
        photos: [
          photo(ListingShot.cover),
          photo(ListingShot.back),
          photo(ListingShot.brandTag),
          photo(ListingShot.sizeLabel),
        ],
      );

      expect(listing.missingShots, isEmpty);
    });

    test('asks for a photograph of a flaw only when a flaw is listed', () {
      final none = draft();
      final one = draft(flaws: ['small mark on the left cuff']);

      expect(none.missingShots, isNot(contains(ListingShot.flaw)));
      expect(one.missingShots, contains(ListingShot.flaw));
    });

    test('the flaw comes last, after the four that are always asked for', () {
      final listing = draft(flaws: ['small mark']);

      expect(listing.missingShots.last, ListingShot.flaw);
    });

    test('stops asking for the flaw once it is pictured', () {
      final listing = draft(
        flaws: ['small mark'],
        photos: [photo(ListingShot.flaw)],
      );

      expect(listing.missingShots, isNot(contains(ListingShot.flaw)));
    });

    test('a care label or another shot is never asked for', () {
      final listing = draft(photos: [photo(ListingShot.other)]);

      expect(listing.missingShots, isNot(contains(ListingShot.careLabel)));
      expect(listing.missingShots, isNot(contains(ListingShot.other)));
    });

    test('a photograph of the wrong kind does not count', () {
      final listing = draft(photos: [photo(ListingShot.other)]);

      expect(listing.missingShots, contains(ListingShot.cover));
    });
  });

  group('refreshing', () {
    final posted = DateTime.utc(2026, 10, 1, 12);
    final listed = draft().markListed(posted);

    test('is not needed before two weeks', () {
      expect(
          listed.needsRefresh(posted.add(const Duration(days: 13))), isFalse);
      expect(
        listed.needsRefresh(posted.add(const Duration(days: 13, hours: 23))),
        isFalse,
      );
    });

    test('is needed at exactly two weeks', () {
      expect(listed.needsRefresh(posted.add(const Duration(days: 14))), isTrue);
    });

    test('is needed after two weeks', () {
      expect(listed.needsRefresh(posted.add(const Duration(days: 40))), isTrue);
    });

    test('is not needed for a draft, however old', () {
      expect(
        draft().needsRefresh(created.add(const Duration(days: 400))),
        isFalse,
      );
    });

    test('is not needed once it has sold', () {
      final sold = listed.markSold(posted.add(const Duration(days: 20)));

      expect(sold.needsRefresh(posted.add(const Duration(days: 60))), isFalse);
    });

    test('is not needed when there is no posting date to count from', () {
      final odd = draft().copyWith(status: ListingStatus.listed);

      expect(odd.needsRefresh(created.add(const Duration(days: 60))), isFalse);
    });

    test('refreshing it restarts the clock', () {
      final later = posted.add(const Duration(days: 15));
      expect(listed.needsRefresh(later), isTrue);

      final refreshed = listed.markListed(later);

      expect(refreshed.needsRefresh(later), isFalse);
      expect(
        refreshed.needsRefresh(later.add(const Duration(days: 14))),
        isTrue,
      );
    });

    test('names the two weeks it counts', () {
      expect(listingRefreshAfter, const Duration(days: 14));
    });
  });

  group('how long it has been listed', () {
    final posted = DateTime.utc(2026, 10, 1, 12);

    test('a draft has not been listed', () {
      expect(draft().listedFor(posted), isNull);
    });

    test('a listing up is as old as the time since it was posted', () {
      final listed = draft().markListed(posted);

      expect(
        listed.listedFor(posted.add(const Duration(days: 9, hours: 2))),
        const Duration(days: 9, hours: 2),
      );
    });

    test('a sold listing stopped counting when it sold', () {
      final sold = draft()
          .markListed(posted)
          .markSold(posted.add(const Duration(days: 5)));

      expect(
        sold.listedFor(posted.add(const Duration(days: 90))),
        const Duration(days: 5),
      );
    });

    test('something sold without ever being listed has no listed time', () {
      final sold = draft().markSold(posted);

      expect(sold.listedFor(posted.add(const Duration(days: 3))), isNull);
    });

    test('a clock that runs backwards never gives a negative time', () {
      final listed = draft().markListed(posted);

      expect(
        listed.listedFor(posted.subtract(const Duration(hours: 1))),
        Duration.zero,
      );
    });
  });

  group('changing status', () {
    final at = DateTime.utc(2026, 10, 5, 9);

    test('markListed records when it was posted and moves it on', () {
      final listed = draft().markListed(at);

      expect(listed.status, ListingStatus.listed);
      expect(listed.listedAt, at);
      expect(listed.updatedAt, at);
    });

    test('markListed does not touch anything else', () {
      final base = fullListing().backToDraft();
      final listed = base.markListed(at);

      expect(listed.title, base.title);
      expect(listed.priceCents, base.priceCents);
      expect(listed.photos, base.photos);
    });

    test('relisting a sold one takes the sale back', () {
      final back = fullListing().markListed(at);

      expect(back.status, ListingStatus.listed);
      expect(back.soldAt, isNull);
      expect(back.soldPriceCents, isNull);
    });

    test('markSold records when, and moves it on', () {
      final sold = draft().markListed(created).markSold(at, priceCents: 2800);

      expect(sold.status, ListingStatus.sold);
      expect(sold.soldAt, at);
      expect(sold.updatedAt, at);
    });

    test('the sold price is what was given', () {
      final sold = draft()
          .copyWith(priceCents: 3000)
          .markListed(created)
          .markSold(at, priceCents: 2500);

      expect(sold.soldPriceCents, 2500);
      expect(sold.priceCents, 3000);
    });

    test('the sold price defaults to the asking price', () {
      final sold =
          draft().copyWith(priceCents: 3000).markListed(created).markSold(at);

      expect(sold.soldPriceCents, 3000);
    });

    test('with no asking price and none given, the sold price stays unknown',
        () {
      final sold = draft().markListed(created).markSold(at);

      expect(sold.soldPriceCents, isNull);
    });

    test('a price recorded earlier is not carried into a new sale', () {
      final resold = fullListing().markSold(at);

      // fullListing asks 3000 and sold for 2800; selling again defaults to the
      // asking price and not to the earlier sale.
      expect(resold.soldPriceCents, 3000);
    });

    test('backToDraft forgets when it was posted and any sale', () {
      final back = fullListing().backToDraft();

      expect(back.status, ListingStatus.draft);
      expect(back.listedAt, isNull);
      expect(back.soldAt, isNull);
      expect(back.soldPriceCents, isNull);
    });

    test('backToDraft keeps what was written, priced and photographed', () {
      final listing = fullListing();
      final back = listing.backToDraft();

      expect(back.title, listing.title);
      expect(back.priceCents, listing.priceCents);
      expect(back.photos, listing.photos);
      expect(back.priceSearch, listing.priceSearch);
    });

    test('backToDraft stamps the change only when told the time', () {
      final listing = fullListing();

      expect(listing.backToDraft().updatedAt, listing.updatedAt);
      expect(listing.backToDraft(at: at).updatedAt, at);
    });

    test('none of them change which listing it is', () {
      final listing = fullListing();

      for (final changed in [
        listing.markListed(at),
        listing.markSold(at),
        listing.backToDraft(),
      ]) {
        expect(changed.id, listing.id);
        expect(changed.itemId, listing.itemId);
        expect(changed.createdAt, listing.createdAt);
      }
    });
  });

  group('copyWith', () {
    test('changes what it is given and keeps the rest', () {
      final listing = fullListing();
      final changed = listing.copyWith(title: 'New title', priceCents: 4000);

      expect(changed.title, 'New title');
      expect(changed.priceCents, 4000);
      expect(changed.brand, listing.brand);
      expect(changed.photos, listing.photos);
      expect(changed.priceSearch, listing.priceSearch);
    });

    test('does not change which listing it is or when it was made', () {
      final listing = fullListing();
      final changed = listing.copyWith(title: 'x');

      expect(changed.id, listing.id);
      expect(changed.itemId, listing.itemId);
      expect(changed.createdAt, listing.createdAt);
    });

    test('leaves the updated time alone unless given one', () {
      final listing = fullListing();

      expect(listing.copyWith(title: 'x').updatedAt, listing.updatedAt);
      expect(
        listing.copyWith(updatedAt: DateTime.utc(2027)).updatedAt,
        DateTime.utc(2027),
      );
    });

    test('can take back each field that can be taken back', () {
      final listing = fullListing();
      final cleared = listing.copyWith(
        clearListedAt: true,
        clearSoldAt: true,
        clearSoldPrice: true,
        clearDepartment: true,
        clearBrand: true,
        clearSizeLabel: true,
        clearCondition: true,
        clearMaterial: true,
        clearEra: true,
        clearNotes: true,
        clearPrice: true,
        clearPriceSearch: true,
        clearFacts: true,
      );

      expect(cleared.listedAt, isNull);
      expect(cleared.soldAt, isNull);
      expect(cleared.soldPriceCents, isNull);
      expect(cleared.department, isNull);
      expect(cleared.brand, isNull);
      expect(cleared.sizeLabel, isNull);
      expect(cleared.condition, isNull);
      expect(cleared.material, isNull);
      expect(cleared.era, isNull);
      expect(cleared.notes, isNull);
      expect(cleared.priceCents, isNull);
      expect(cleared.priceSearch, isNull);
      expect(cleared.facts, isNull);
      // And nothing else went with them.
      expect(cleared.title, listing.title);
      expect(cleared.flaws, listing.flaws);
      expect(cleared.photos, listing.photos);
    });

    test('clears one field without disturbing another', () {
      final listing = fullListing();
      final cleared = listing.copyWith(clearBrand: true);

      expect(cleared.brand, isNull);
      expect(cleared.sizeLabel, listing.sizeLabel);
      expect(cleared.material, listing.material);
    });

    test('replaces a list wholesale', () {
      final changed = fullListing().copyWith(
        flaws: ['hole'],
        colours: [DepopColour.black],
        photos: [photo(ListingShot.cover)],
        typedComparableCents: [100],
        typedComparablesSold: false,
        measurements: const Measurements(lengthIn: 30),
      );

      expect(changed.flaws, ['hole']);
      expect(changed.colours, [DepopColour.black]);
      expect(changed.photos, hasLength(1));
      expect(changed.typedComparableCents, [100]);
      expect(changed.typedComparablesSold, isFalse);
      expect(changed.measurements.lengthIn, 30);
    });
  });

  group('equality', () {
    test('two listings with the same contents are equal', () {
      expect(fullListing(), fullListing());
      expect(fullListing().hashCode, fullListing().hashCode);
    });

    test('an edit makes it unequal, which is how unsaved changes are noticed',
        () {
      final original = fullListing();

      expect(original.copyWith(title: 'Different'), isNot(original));
      expect(original.copyWith(priceCents: 1), isNot(original));
      expect(original.copyWith(flaws: const []), isNot(original));
      expect(original.copyWith(clearNotes: true), isNot(original));
    });

    test('every field takes part', () {
      final original = fullListing();
      final changes = <String, Listing>{
        'status': original.copyWith(status: ListingStatus.listed),
        'listedAt': original.copyWith(listedAt: DateTime.utc(2030)),
        'soldAt': original.copyWith(soldAt: DateTime.utc(2030)),
        'soldPriceCents': original.copyWith(soldPriceCents: 1),
        'department': original.copyWith(department: DepopDepartment.women),
        'itemType': original.copyWith(itemType: ItemType.hoodie),
        'brand': original.copyWith(brand: 'Adidas'),
        'sizeLabel': original.copyWith(sizeLabel: 'L'),
        'condition': original.copyWith(condition: DepopCondition.usedFair),
        'colours': original.copyWith(colours: [DepopColour.red]),
        'material': original.copyWith(material: 'wool'),
        'measurements': original.copyWith(measurements: Measurements.none),
        'styleWords': original.copyWith(styleWords: ['other']),
        'era': original.copyWith(era: 'Y2K'),
        'priceSearch': original.copyWith(clearPriceSearch: true),
        'facts': original.copyWith(clearFacts: true),
        'photos': original.copyWith(photos: const []),
        'typedComparableCents': original.copyWith(typedComparableCents: [1]),
        'typedComparablesSold': original.copyWith(typedComparablesSold: false),
        'updatedAt': original.copyWith(updatedAt: DateTime.utc(2030)),
      };

      changes.forEach((field, changed) {
        expect(changed, isNot(original), reason: field);
      });
    });

    test('a different id is a different listing', () {
      final other = Listing(
        id: const ListingId('another'),
        createdAt: created,
        updatedAt: created,
      );
      final same = Listing(
        id: const ListingId('listing-1'),
        createdAt: created,
        updatedAt: created,
      );

      expect(other, isNot(same));
    });
  });

  group('what to search for', () {
    test('uses the last search\'s phrases first, since they may be corrected',
        () {
      final listing = fullListing().copyWith(
        priceSearch: PriceSearch(
          status: PriceSearchStatus.ok,
          queries: const SearchQueries(
            depop: 'corrected depop phrase',
            retail: 'corrected retail phrase',
          ),
        ),
      );

      expect(listing.searchQueries!.depop, 'corrected depop phrase');
      expect(listing.searchQueries!.retail, 'corrected retail phrase');
    });

    test('then the phrases the photographs produced', () {
      final listing = fullListing().copyWith(clearPriceSearch: true);

      expect(
        listing.searchQueries,
        const SearchQueries(
          depop: 'Nike vintage crewneck sweatshirt grey',
          retail: 'Nike Club Fleece crew sweatshirt grey',
        ),
      );
    });

    test('a search whose phrases were too short to use is passed over', () {
      final listing = fullListing().copyWith(
        priceSearch: PriceSearch(
          status: PriceSearchStatus.unavailable,
          queries: const SearchQueries(depop: '', retail: ''),
        ),
      );

      expect(listing.searchQueries!.depop,
          'Nike vintage crewneck sweatshirt grey');
    });

    test('then words built from the listing itself', () {
      final listing = Listing(
        id: const ListingId('x'),
        createdAt: created,
        updatedAt: created,
        title: 'Vintage Champion reverse weave crewneck',
        itemType: ItemType.sweatshirt,
        brand: 'Champion',
        colours: const [DepopColour.grey],
      );

      expect(listing.searchQueries!.depop,
          'Vintage Champion reverse weave crewneck');
      expect(listing.searchQueries!.retail, 'Champion sweatshirt grey');
    });

    test('builds the search from the brand, colour and type with no title', () {
      final listing = Listing(
        id: const ListingId('x'),
        createdAt: created,
        updatedAt: created,
        itemType: ItemType.hoodie,
        brand: 'Nike',
        colours: const [DepopColour.navy],
      );

      expect(listing.searchQueries!.depop, 'Nike navy hoodie');
      expect(listing.searchQueries!.retail, 'Nike hoodie navy');
    });

    test('leaves out a type that is just Other', () {
      final listing = Listing(
        id: const ListingId('x'),
        createdAt: created,
        updatedAt: created,
        brand: 'Nike',
        colours: const [DepopColour.navy],
      );

      expect(listing.searchQueries!.depop, 'Nike navy');
      expect(listing.searchQueries!.retail, 'Nike navy');
    });

    test('is null when there is too little to search on', () {
      final blank = Listing(
        id: const ListingId('x'),
        createdAt: created,
        updatedAt: created,
      );

      expect(blank.searchQueries, isNull);
      expect(blank.canLookUpPrices, isFalse);
    });

    test('a type on its own is enough to search on, if not a good search', () {
      final listing = Listing(
        id: const ListingId('x'),
        createdAt: created,
        updatedAt: created,
        itemType: ItemType.hat,
      );

      // "hat" is three characters: searchable, if not much use.
      expect(listing.searchQueries!.depop, 'hat');
    });

    test('never builds a phrase longer than the server takes', () {
      final listing = Listing(
        id: const ListingId('x'),
        createdAt: created,
        updatedAt: created,
        title: 'a' * 300,
      );

      expect(listing.searchQueries!.depop.length, SearchQueries.maxLength);
    });

    test('a price search can be run once there is a title and phrases', () {
      expect(fullListing().canLookUpPrices, isTrue);
      expect(draft().canLookUpPrices, isTrue);
    });

    test('a price search needs a title as well as phrases', () {
      final noTitle = fullListing().copyWith(title: '  ');

      expect(noTitle.searchQueries, isNotNull);
      expect(noTitle.canLookUpPrices, isFalse);
      expect(fullListing().copyWith(title: 'ab').canLookUpPrices, isFalse);
    });
  });

  group('storage', () {
    Map<String, Object?> stored(Listing listing) => viaText(listing.toJson());

    test('every field survives a round trip through JSON text', () {
      final original = fullListing();
      final back = Listing.fromJson(stored(original));

      expect(back, original);
      expect(back.toJson(), original.toJson());
    });

    test('each field comes back as it went in', () {
      final original = fullListing();
      final back = Listing.fromJson(stored(original));

      expect(back.id, const ListingId('listing-1'));
      expect(back.itemId, const ItemId('item-1'));
      expect(back.status, ListingStatus.sold);
      expect(back.createdAt, original.createdAt);
      expect(back.updatedAt, original.updatedAt);
      expect(back.listedAt, original.listedAt);
      expect(back.soldAt, original.soldAt);
      expect(back.soldPriceCents, 2800);
      expect(back.department, DepopDepartment.men);
      expect(back.title, 'Nike vintage crewneck sweatshirt grey');
      expect(back.itemType, ItemType.sweatshirt);
      expect(back.brand, 'Nike');
      expect(back.sizeLabel, 'M');
      expect(back.condition, DepopCondition.usedExcellent);
      expect(back.colours, [DepopColour.grey, DepopColour.white]);
      expect(back.material, '80% cotton, 20% polyester');
      expect(back.measurements, original.measurements);
      expect(back.flaws, ['small mark on the left cuff', 'light pilling']);
      expect(back.styleWords, ['vintage', 'crewneck']);
      expect(back.era, '90s');
      expect(back.notes, 'Ships within 5 days.');
      expect(back.priceCents, 3000);
      expect(back.priceSearch, original.priceSearch);
      expect(back.facts, original.facts);
      expect(back.photos, original.photos);
      expect(back.typedComparableCents, [2500, 2900]);
      expect(back.typedComparablesSold, isTrue);
    });

    test('writes a version, so a later shape can recognise this one', () {
      expect(fullListing().toJson()['v'], 1);
    });

    test('writes only plain JSON, no Dart objects', () {
      // jsonEncode throws on a Uri or DateTime that was left as an object.
      expect(() => jsonEncode(fullListing().toJson()), returnsNormally);
    });

    test('leaves out what is absent instead of writing a null', () {
      final json = draft().toJson();

      for (final key in [
        'itemId',
        'listedAt',
        'soldAt',
        'soldPriceCents',
        'department',
        'brand',
        'sizeLabel',
        'condition',
        'material',
        'era',
        'notes',
        'priceCents',
        'priceSearch',
        'facts',
      ]) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
    });

    test('ignores keys it does not know', () {
      final json = stored(fullListing())
        ..['addedInAFutureVersion'] = {
          'anything': [1, 2, 3]
        }
        ..['v'] = 7;

      expect(Listing.fromJson(json), fullListing());
    });

    test('ignores unknown keys inside what it contains', () {
      final json = stored(fullListing());
      (json['measurements']! as Map<String, Object?>)['chestIn'] = 40;
      (json['photos']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .first['alt'] = 'text';
      (json['priceSearch']! as Map<String, Object?>)['cost'] = 0;

      expect(Listing.fromJson(json), fullListing());
    });

    test('reads a listing that has only an id and a creation time', () {
      // A field added later must not break an older stored listing, and the
      // oldest listing possible has only what could not be done without.
      final listing = Listing.fromJson({
        'id': 'old-1',
        'createdAt': '2026-10-01T09:00:00.000Z',
      });

      expect(listing.id, const ListingId('old-1'));
      expect(listing.status, ListingStatus.draft);
      expect(listing.updatedAt, DateTime.utc(2026, 10, 1, 9));
      expect(listing.title, '');
      expect(listing.itemType, ItemType.other);
      expect(listing.colours, isEmpty);
      expect(listing.flaws, isEmpty);
      expect(listing.photos, isEmpty);
      expect(listing.measurements.isEmpty, isTrue);
      expect(listing.priceSearch, isNull);
      expect(listing.facts, isNull);
      expect(listing.typedComparablesSold, isFalse);
    });

    test('a name it has never heard of falls back instead of failing', () {
      final json = stored(fullListing())
        ..['status'] = 'archived'
        ..['itemType'] = 'spaceSuit'
        ..['condition'] = 'Mint'
        ..['department'] = 'kids'
        ..['colours'] = ['grey', 'chartreuse', 'white'];

      final listing = Listing.fromJson(json);

      expect(listing.status, ListingStatus.draft);
      expect(listing.itemType, ItemType.other);
      expect(listing.condition, isNull);
      expect(listing.department, isNull);
      expect(listing.colours, [DepopColour.grey, DepopColour.white]);
    });

    test('an unreadable photograph is dropped and the rest kept', () {
      final json = stored(fullListing());
      (json['photos']! as List<Object?>)
        ..insert(0, {'shot': 'cover'})
        ..add('not even an object')
        ..add({'uri': 'store://extra.jpg', 'shot': 'sideways'});

      final photos = Listing.fromJson(json).photos;

      expect(photos, hasLength(3));
      expect(photos.last.shot, ListingShot.other);
    });

    test('a stored price search that cannot be read does not lose the listing',
        () {
      final json = stored(fullListing())..['priceSearch'] = <String, Object?>{};

      final listing = Listing.fromJson(json);

      expect(listing.priceSearch!.status, PriceSearchStatus.unavailable);
      expect(listing.title, fullListing().title);
    });

    test('refuses a listing with no id, because it could not be found again',
        () {
      final json = stored(fullListing())..remove('id');

      expect(() => Listing.fromJson(json), throwsFormatException);
      expect(
        () => Listing.fromJson({'id': '', 'createdAt': '2026-10-01T09:00:00Z'}),
        throwsFormatException,
      );
    });

    test('refuses a listing with no creation time', () {
      final json = stored(fullListing())..remove('createdAt');

      expect(() => Listing.fromJson(json), throwsFormatException);
    });

    test('a listing with no updated time takes its creation time', () {
      final json = stored(fullListing())..remove('updatedAt');

      expect(Listing.fromJson(json).updatedAt, fullListing().createdAt);
    });

    test('reads whole-number money written as a decimal', () {
      final json = stored(fullListing())
        ..['priceCents'] = 3000.0
        ..['typedComparableCents'] = [2500.0, 2900];

      final listing = Listing.fromJson(json);

      expect(listing.priceCents, 3000);
      expect(listing.typedComparableCents, [2500, 2900]);
    });

    test('a listing written locally reads back the same in another time zone',
        () {
      // Stored as ISO-8601 with its zone, so a phone that crosses a time zone
      // reads the same instant.
      final local = fullListing().copyWith(
        listedAt: DateTime.utc(2026, 10, 2, 10).toLocal(),
      );
      final back = Listing.fromJson(stored(local));

      expect(back.listedAt!.toUtc(), DateTime.utc(2026, 10, 2, 10));
    });
  });
}
