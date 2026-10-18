/// What the Sell screens do to a listing, with no screen in sight.
///
/// The controller holds no selling rule — those are the core's, and tested
/// there — so what is held here is the sequencing, which is where a listing
/// goes wrong without anyone noticing: one saved before the server answered, a
/// photograph deleted that a garment still shows, a sale recorded on the
/// listing and not on the garment. The pieces it sequences are real; the
/// server is a fake that records what it was asked.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/api/scan_dto.dart';
import 'package:washing_advice/data/images/image_store.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/sell/listing_controller.dart';

import '../../support/fixtures.dart';

void main() {
  late InMemoryListingRepository listings;
  late InMemoryWardrobeRepository wardrobe;
  late InMemoryEventLog events;
  late MemoryImageStore images;
  late _FakeGateway gateway;
  late ProviderContainer container;

  setUp(() {
    listings = InMemoryListingRepository();
    wardrobe = InMemoryWardrobeRepository();
    events = InMemoryEventLog();
    images = MemoryImageStore();
    gateway = _FakeGateway();
    container = _container(
      listings: listings,
      wardrobe: wardrobe,
      events: events,
      images: images,
      gateway: gateway,
    );
    addTearDown(container.dispose);
  });

  ListingController controller() => container.read(listingControllerProvider);

  /// A photograph that is one letter, so that which were sent is readable.
  ScanImage photo(String mark) => ScanImage(bytes: utf8.encode(mark));

  /// What the fake server was last sent, as the letters on the photographs.
  List<String> sent() => gateway.described.last.images.map(_mark).toList();

  /// A garment in the wardrobe whose photographs are each a letter in the
  /// store, in the order given.
  Future<WardrobeItem> garment({
    String id = 'sweat',
    List<(PhotoRole, String)> photos = const [],
    bool cutouts = false,
    LifecycleState lifecycle = LifecycleState.active,
  }) async {
    final held = <ItemPhoto>[];
    for (final (index, (role, mark)) in photos.indexed) {
      held.add(
        ItemPhoto(
          uri: await images.save(_bytes(mark), name: '$id-${role.name}-$index'),
          cutoutUri: cutouts
              ? await images.save(
                  _bytes('$mark-cutout'),
                  name: '$id-${role.name}-$index-cutout',
                )
              : null,
          role: role,
          capturedAt: DateTime.utc(2026, 1, 1 + index),
        ),
      );
    }
    final item = confidentItem(
      id: id,
      name: 'Grey crewneck',
      type: ItemType.sweatshirt,
      colorName: 'Charcoal',
      lifecycle: lifecycle,
    ).copyWith(brand: Confident.fromUser('Uniqlo'), photos: PhotoSet(held));
    await wardrobe.save(item);
    return item;
  }

  /// A draft that is in the repository already.
  Future<Listing> saved(Listing listing) async {
    await listings.save(listing);
    return listing;
  }

  group('a new id', () {
    test('comes from the app\'s generator', () {
      expect(controller().newListingId(), const ListingId('listing-1'));
      expect(controller().newListingId(), const ListingId('listing-2'));
    });
  });

  group('storing photographs', () {
    test('keeps each in the store, in order, with what it is of', () async {
      final stored = await controller().storePhotos(const ListingId('l1'), [
        (photo('A'), ListingShot.cover),
        (photo('B'), ListingShot.back),
        (photo('C'), ListingShot.flaw),
      ]);

      expect(stored.map((p) => p.shot), [
        ListingShot.cover,
        ListingShot.back,
        ListingShot.flaw,
      ]);
      expect(
        [
          for (final p in stored)
            _mark(ScanImage(bytes: await images.read(p.uri) ?? [])),
        ],
        ['A', 'B', 'C'],
      );
    });

    test('names them after the listing and the shot', () async {
      final stored = await controller().storePhotos(const ListingId('l1'), [
        (photo('A'), ListingShot.brandTag),
      ]);

      expect(stored.single.uri, startsWith('$memoryImageScheme:l1-brandTag-'));
    });

    test('keeps two of one shot apart', () async {
      // Two photographs of flaws are two photographs, not one rewritten.
      final stored = await controller().storePhotos(const ListingId('l1'), [
        (photo('A'), ListingShot.flaw),
        (photo('B'), ListingShot.flaw),
      ]);

      expect({for (final p in stored) p.uri}, hasLength(2));
      expect(images.length, 2);
    });

    test('keeps no more than Depop takes', () async {
      final stored = await controller().storePhotos(const ListingId('l1'), [
        for (var i = 0; i < 11; i++) (photo('$i'), ListingShot.other),
      ]);

      expect(depopPhotoLimit, 8);
      expect(stored, hasLength(8));
      expect(images.length, 8);
      // The first eight, not the last.
      expect(
        [
          for (final p in stored)
            _mark(ScanImage(bytes: await images.read(p.uri) ?? [])),
        ],
        ['0', '1', '2', '3', '4', '5', '6', '7'],
      );
    });

    test('leaves out one that cannot be stored and keeps the rest', () async {
      final flaky = _FlakyStore(images, failsToSave: {'-flaw-'});
      final container = _container(
        listings: listings,
        wardrobe: wardrobe,
        events: events,
        images: flaky,
        gateway: gateway,
      );
      addTearDown(container.dispose);

      final stored = await container
          .read(listingControllerProvider)
          .storePhotos(const ListingId('l1'), [
            (photo('A'), ListingShot.cover),
            (photo('B'), ListingShot.flaw),
            (photo('C'), ListingShot.back),
          ]);

      expect(stored.map((p) => p.shot), [ListingShot.cover, ListingShot.back]);
    });

    test('stores nothing when there is nothing to store', () async {
      expect(
        await controller().storePhotos(const ListingId('l1'), []),
        isEmpty,
      );
      expect(images.length, 0);
    });
  });

  group('a listing from photographs', () {
    const id = ListingId('l1');

    test('sends the four most worth reading, most telling first', () async {
      // Taken in the order a person might: the back last, the tags between.
      await controller().createFromPhotos(id, const [], [
        (photo('A'), ListingShot.back),
        (photo('B'), ListingShot.other),
        (photo('C'), ListingShot.careLabel),
        (photo('D'), ListingShot.flaw),
        (photo('E'), ListingShot.sizeLabel),
        (photo('F'), ListingShot.brandTag),
        (photo('G'), ListingShot.cover),
      ]);

      // Cover, brand tag, size label, flaw: and not the back, the care label
      // or the rest.
      expect(sent(), ['G', 'F', 'E', 'D']);
    });

    test('and the rest in their own order when there are fewer', () async {
      await controller().createFromPhotos(id, const [], [
        (photo('A'), ListingShot.other),
        (photo('B'), ListingShot.careLabel),
        (photo('C'), ListingShot.back),
      ]);

      expect(sent(), ['C', 'B', 'A']);
    });

    test('never more than four, whatever there are', () async {
      await controller().createFromPhotos(id, const [], [
        for (var i = 0; i < 8; i++) (photo('$i'), ListingShot.other),
      ]);

      expect(AiGateway.describePhotoLimit, 4);
      // The first four of a kind, in the order given.
      expect(sent(), ['0', '1', '2', '3']);
    });

    test('keeps the order of photographs of one kind', () async {
      await controller().createFromPhotos(id, const [], [
        (photo('A'), ListingShot.flaw),
        (photo('B'), ListingShot.cover),
        (photo('C'), ListingShot.flaw),
        (photo('D'), ListingShot.cover),
        (photo('E'), ListingShot.flaw),
      ]);

      // Two covers, then flaws in the order they came: the third flaw is the
      // one that did not fit.
      expect(sent(), ['B', 'D', 'A', 'C']);
    });

    test('can read a photograph of any kind', () async {
      // A kind of shot with no place in the order would be dropped without a
      // word, and a listing written from photographs of it would be written
      // from none.
      for (final shot in ListingShot.values) {
        await controller().createFromPhotos(
          ListingId('l-${shot.name}'),
          const [],
          [(photo('X'), shot)],
        );

        expect(sent(), ['X'], reason: shot.name);
      }
    });

    test('says nothing about a garment it does not have', () async {
      await controller().createFromPhotos(id, const [], [
        (photo('A'), ListingShot.cover),
      ]);

      expect(gateway.described.single.context, isNull);
    });

    test('makes the draft from what was read, and saves it', () async {
      final photos = [
        const ListingPhoto(uri: 'wa-memory:front', shot: ListingShot.cover),
        const ListingPhoto(uri: 'wa-memory:tag', shot: ListingShot.brandTag),
      ];

      final listing = await controller().createFromPhotos(id, photos, [
        (photo('A'), ListingShot.cover),
      ]);

      expect(listing.id, id);
      expect(listing.status, ListingStatus.draft);
      expect(listing.title, 'Nike vintage crewneck sweatshirt grey');
      expect(listing.brand, 'Nike');
      expect(listing.sizeLabel, 'M');
      expect(listing.photos, photos);
      expect(listing.itemId, isNull);
      // Saved, and the same as what came back.
      expect(await listings.byId(id), listing);
      expect(listings.length, 1);
    });

    test('is made the way the core makes one from facts', () async {
      final listing = await controller().createFromPhotos(id, const [], [
        (photo('A'), ListingShot.cover),
      ]);

      expect(
        listing,
        Listing.fromFacts(id: id, now: listing.createdAt, facts: gateway.facts),
      );
    });

    test('is stamped now, in UTC', () async {
      final before = DateTime.now().toUtc();

      final listing = await controller().createFromPhotos(id, const [], [
        (photo('A'), ListingShot.cover),
      ]);

      expect(listing.createdAt.isUtc, isTrue);
      expect(listing.createdAt.isBefore(before), isFalse);
      expect(listing.updatedAt, listing.createdAt);
    });

    group('when the server cannot read them', () {
      test('throws a ScanFailure and saves nothing', () async {
        gateway.describeError = const ScanFailure('The server is asleep.');

        await expectLater(
          controller().createFromPhotos(id, const [], [
            (photo('A'), ListingShot.cover),
          ]),
          throwsA(
            isA<ScanFailure>()
                .having((f) => f.message, 'message', 'The server is asleep.')
                .having((f) => f.isRetryable, 'isRetryable', true),
          ),
        );

        expect(listings.length, 0);
      });

      test('and says when trying again would not help', () async {
        gateway.describeError = const ScanFailure(
          'That is not a photograph.',
          isRetryable: false,
        );

        await expectLater(
          controller().createFromPhotos(id, const [], [
            (photo('A'), ListingShot.cover),
          ]),
          throwsA(
            isA<ScanFailure>().having(
              (f) => f.isRetryable,
              'isRetryable',
              false,
            ),
          ),
        );
      });

      test(
        'an answer it cannot read is a failure too, and saves nothing',
        () async {
          for (final unreadable in <Exception>[
            ScanContractError('the response had no "result"'),
            const FormatException('not JSON'),
          ]) {
            gateway.describeError = unreadable;

            await expectLater(
              controller().createFromPhotos(id, const [], [
                (photo('A'), ListingShot.cover),
              ]),
              throwsA(
                isA<ScanFailure>()
                    .having(
                      (f) => f.message,
                      'message',
                      contains('cannot read'),
                    )
                    .having((f) => f.isRetryable, 'isRetryable', false),
              ),
              reason: '$unreadable',
            );
          }

          expect(listings.length, 0);
        },
      );

      test(
        'the photographs are still kept, to try again or write it by hand',
        () async {
          final shots = [
            (photo('A'), ListingShot.cover),
            (photo('B'), ListingShot.brandTag),
          ];
          final stored = await controller().storePhotos(id, shots);
          gateway.describeError = const ScanFailure('The server is asleep.');

          await expectLater(
            controller().createFromPhotos(id, stored, shots),
            throwsA(isA<ScanFailure>()),
          );
          expect(images.length, 2);

          // And the same photographs go into the listing written by hand.
          final empty = await controller().createEmpty(id, stored);
          expect(empty.photos, stored);
          expect(await listings.byId(id), empty);
        },
      );
    });
  });

  group('a listing written by hand', () {
    test('is blank, with the photographs', () async {
      const photos = [
        ListingPhoto(uri: 'wa-memory:front', shot: ListingShot.cover),
      ];

      final listing = await controller().createEmpty(
        const ListingId('l1'),
        photos,
      );

      expect(listing.title, '');
      expect(listing.status, ListingStatus.draft);
      expect(listing.photos, photos);
      expect(listing.facts, isNull);
      expect(await listings.byId(const ListingId('l1')), listing);
    });

    test('asks the server nothing', () async {
      await controller().createEmpty(const ListingId('l1'), const []);

      expect(gateway.described, isEmpty);
    });
  });

  group('a listing for a garment', () {
    test('is made from the garment and what the photographs show', () async {
      final item = await garment(photos: [(PhotoRole.front, 'F')]);

      final made = await controller().openOrCreateForGarment(item.id);

      expect(made.reused, isFalse);
      expect(made.describeFailed, isFalse);
      expect(made.listing.itemId, item.id);
      expect(made.listing.status, ListingStatus.draft);
      // The title is the reading's; the brand is the wardrobe's, since a brand
      // somebody typed is not second-guessed from a photograph.
      expect(made.listing.title, gateway.facts.title);
      expect(made.listing.brand, 'Uniqlo');
      expect(made.listing.facts, gateway.facts);
      // Saved, and the one that came back.
      expect(await listings.byId(made.listing.id), made.listing);
      expect(listings.length, 1);
    });

    test('is made the way the core makes one from a garment', () async {
      final item = await garment(photos: [(PhotoRole.front, 'F')]);

      final made = await controller().openOrCreateForGarment(item.id);

      final expected = Listing.fromGarment(
        id: made.listing.id,
        now: made.listing.createdAt,
        item: item,
        facts: gateway.facts,
      );
      expect(made.listing, expected);
    });

    test(
      'reads the garment\'s own photographs, the most telling four',
      () async {
        final item = await garment(
          photos: [
            (PhotoRole.careTag, 'C'),
            (PhotoRole.back, 'B'),
            (PhotoRole.condition, 'W'),
            (PhotoRole.brandTag, 'T'),
            (PhotoRole.front, 'F'),
            (PhotoRole.detail, 'D'),
          ],
        );

        await controller().openOrCreateForGarment(item.id);

        // The front is the cover, the brand label the brand tag, the condition
        // shot a flaw, and then the back: the care label and the detail go
        // unread.
        expect(sent(), ['F', 'T', 'W', 'B']);
      },
    );

    test('sends what the wardrobe knows with them', () async {
      final item = await garment(photos: [(PhotoRole.front, 'F')]);

      await controller().openOrCreateForGarment(item.id);

      expect(
        gateway.described.single.context,
        describeContextForItem((await wardrobe.byId(item.id))!),
      );
      expect(gateway.described.single.context!['known'], contains('brand'));
    });

    test('sends the photograph and not its cutout', () async {
      // A model reads a label from a photograph of it, not from a silhouette.
      final item = await garment(
        photos: [(PhotoRole.front, 'F')],
        cutouts: true,
      );

      await controller().openOrCreateForGarment(item.id);

      expect(sent(), ['F']);
    });

    test('passes over a photograph whose file is gone for the next', () async {
      final item = await garment(
        photos: [
          (PhotoRole.front, 'F'),
          (PhotoRole.brandTag, 'T'),
          (PhotoRole.back, 'B'),
        ],
      );
      await images.delete(item.photos.photos.first.uri);

      await controller().openOrCreateForGarment(item.id);

      expect(sent(), ['T', 'B']);
    });

    test('points the listing at the garment\'s photographs', () async {
      final item = await garment(
        photos: [(PhotoRole.front, 'F'), (PhotoRole.back, 'B')],
      );

      final made = await controller().openOrCreateForGarment(item.id);

      expect(
        [for (final p in made.listing.photos) p.uri],
        [for (final p in item.photos.photos) p.uri],
      );
      expect(
        [for (final p in made.listing.photos) p.shot],
        [ListingShot.cover, ListingShot.back],
      );
      // Nothing was copied: the store holds what it held.
      expect(images.length, 2);
    });

    test('takes its id from the app\'s generator', () async {
      final item = await garment(photos: [(PhotoRole.front, 'F')]);

      final made = await controller().openOrCreateForGarment(item.id);

      expect(made.listing.id, const ListingId('listing-1'));
    });

    group('that already has one', () {
      test('opens it and makes no other', () async {
        final item = await garment(photos: [(PhotoRole.front, 'F')]);
        final started = await saved(
          Listing(
            id: const ListingId('mine'),
            itemId: item.id,
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
            title: 'Already started',
          ),
        );

        final made = await controller().openOrCreateForGarment(item.id);

        expect(made.reused, isTrue);
        expect(made.describeFailed, isFalse);
        expect(made.listing, started);
        expect(listings.length, 1);
        expect(gateway.described, isEmpty);
      });

      test('also when it is already up for sale', () async {
        final item = await garment(photos: [(PhotoRole.front, 'F')]);
        final up = Listing(
          id: const ListingId('up'),
          itemId: item.id,
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          title: 'Up',
        ).markListed(DateTime.utc(2026, 10, 2));
        await listings.save(up);

        final made = await controller().openOrCreateForGarment(item.id);

        expect(made.reused, isTrue);
        expect(made.listing, up);
      });

      test('even when the garment itself is gone', () async {
        // A listing outlives the garment it was made from.
        final forGone = Listing(
          id: const ListingId('orphan'),
          itemId: const ItemId('gone'),
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          title: 'Gone',
        );
        await listings.save(forGone);

        final made = await controller().openOrCreateForGarment(
          const ItemId('gone'),
        );

        expect(made.reused, isTrue);
        expect(made.listing, forGone);
      });

      test('but not one that has sold, which is finished', () async {
        final item = await garment(photos: [(PhotoRole.front, 'F')]);
        await listings.save(
          Listing(
            id: const ListingId('old'),
            itemId: item.id,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
            title: 'Sold last month',
          ).markSold(DateTime.utc(2026, 9, 20), priceCents: 2800),
        );

        final made = await controller().openOrCreateForGarment(item.id);

        expect(made.reused, isFalse);
        expect(made.listing.id, isNot(const ListingId('old')));
        expect(listings.length, 2);
      });

      test('and not another garment\'s', () async {
        final item = await garment(photos: [(PhotoRole.front, 'F')]);
        await listings.save(
          Listing(
            id: const ListingId('theirs'),
            itemId: const ItemId('jeans'),
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
          ),
        );

        final made = await controller().openOrCreateForGarment(item.id);

        expect(made.reused, isFalse);
        expect(listings.length, 2);
      });
    });

    group('when the photographs cannot be read', () {
      test('is made from the wardrobe alone, and says so', () async {
        final item = await garment(photos: [(PhotoRole.front, 'F')]);
        gateway.describeError = const ScanFailure('The server is asleep.');

        final made = await controller().openOrCreateForGarment(item.id);

        expect(made.describeFailed, isTrue);
        expect(made.reused, isFalse);
        expect(made.listing.facts, isNull);
        // Built from the brand, the type and the colour the wardrobe holds.
        expect(made.listing.title, 'Uniqlo sweatshirt charcoal');
        expect(made.listing.brand, 'Uniqlo');
        expect(made.listing.itemId, item.id);
        expect(await listings.byId(made.listing.id), made.listing);
      });

      test('whichever way it failed', () async {
        final item = await garment(photos: [(PhotoRole.front, 'F')]);

        for (final failure in <Exception>[
          const ScanFailure('offline'),
          const ScanFailure('no', isRetryable: false),
          ScanContractError('no title'),
          const FormatException('not JSON'),
        ]) {
          gateway.describeError = failure;

          final made = await controller().openOrCreateForGarment(item.id);

          expect(made.describeFailed, isTrue, reason: '$failure');
          expect(made.listing.facts, isNull, reason: '$failure');
          await listings.delete(made.listing.id);
        }
      });

      test('a garment with no photographs is not sent anywhere', () async {
        final item = await garment();

        final made = await controller().openOrCreateForGarment(item.id);

        expect(gateway.described, isEmpty);
        expect(made.describeFailed, isTrue);
        expect(made.listing.facts, isNull);
        expect(made.listing.photos, isEmpty);
        expect(await listings.byId(made.listing.id), made.listing);
      });

      test('nor one whose photographs have all gone from the store', () async {
        final item = await garment(photos: [(PhotoRole.front, 'F')]);
        await images.delete(item.photos.photos.single.uri);

        final made = await controller().openOrCreateForGarment(item.id);

        expect(gateway.described, isEmpty);
        expect(made.describeFailed, isTrue);
      });
    });

    group('that is not in the wardrobe', () {
      test('is refused, and nothing is made', () async {
        await expectLater(
          controller().openOrCreateForGarment(const ItemId('nope')),
          throwsA(isA<GarmentNotFound>()),
        );

        expect(listings.length, 0);
        expect(gateway.described, isEmpty);
      });

      test('nor one that has been deleted', () async {
        final item = await garment(
          photos: [(PhotoRole.front, 'F')],
          lifecycle: LifecycleState.removed,
        );

        await expectLater(
          controller().openOrCreateForGarment(item.id),
          throwsA(isA<GarmentNotFound>()),
        );
        expect(listings.length, 0);
      });
    });
  });

  group('changing a listing', () {
    final started = DateTime.utc(2026, 10, 1, 9);
    Listing draft() => Listing(
      id: const ListingId('l1'),
      createdAt: started,
      updatedAt: started,
      title: 'Nike vintage crewneck sweatshirt grey',
      itemType: ItemType.sweatshirt,
      brand: 'Nike',
      colours: const [DepopColour.grey, DepopColour.white],
    );

    test('saving stamps when it changed, and keeps the rest', () async {
      final before = DateTime.now().toUtc();

      final stamped = await controller().save(
        draft().copyWith(title: 'Nike crewneck'),
      );

      expect(stamped.title, 'Nike crewneck');
      expect(stamped.createdAt, started);
      expect(stamped.updatedAt.isUtc, isTrue);
      expect(stamped.updatedAt.isBefore(before), isFalse);
      expect(await listings.byId(stamped.id), stamped);
    });

    test('saving puts it back at the top of the list', () async {
      await listings.save(
        draft().copyWith(updatedAt: DateTime.utc(2026, 10, 2)),
      );
      await listings.save(
        Listing(
          id: const ListingId('other'),
          createdAt: started,
          updatedAt: DateTime.utc(2026, 10, 3),
        ),
      );

      await controller().save(draft());

      expect((await listings.all()).first.id, const ListingId('l1'));
    });

    group('looking up prices', () {
      test('asks for what the listing is, with the phrases to search', () async {
        final listing = await saved(draft());

        await controller().searchPrices(listing);

        expect(gateway.searched.single, {
          // Words the core builds from the listing, there being no reading and
          // no earlier search: the title for Depop, brand and kind for shops.
          'queries': {
            'depop': 'Nike vintage crewneck sweatshirt grey',
            'retail': 'Nike sweatshirt grey',
          },
          'itemType': 'sweatshirt',
          'title': 'Nike vintage crewneck sweatshirt grey',
          'brand': 'Nike',
          'colors': ['Grey', 'White'],
        });
      });

      test('asks the way the core writes the request', () async {
        final listing = await saved(draft());

        await controller().searchPrices(listing);

        expect(
          gateway.searched.single,
          priceSearchRequestJson(
            queries: listing.searchQueries!,
            itemType: listing.itemType,
            title: listing.title,
            brand: listing.brand,
            colors: ['Grey', 'White'],
          ),
        );
      });

      test('keeps the answer on the listing, and saves it', () async {
        final listing = await saved(draft());

        final updated = (await controller().searchPrices(listing)).listing;

        expect(updated.priceSearch, gateway.search);
        expect(updated.priceSearch!.comparables, hasLength(2));
        expect(updated.updatedAt.isAfter(started), isTrue);
        // Everything else as it was.
        expect(
          updated.copyWith(clearPriceSearch: true, updatedAt: started),
          listing,
        );
        expect(await listings.byId(listing.id), updated);
      });

      test('keeps a search that found nothing too, with its phrases', () async {
        final listing = await saved(draft());

        for (final status in [
          PriceSearchStatus.notConfigured,
          PriceSearchStatus.quotaExceeded,
          PriceSearchStatus.unavailable,
        ]) {
          gateway.search = PriceSearch(
            status: status,
            queries: const SearchQueries(
              depop: 'the phrase tried',
              retail: 'the retail phrase tried',
            ),
          );

          final updated = (await controller().searchPrices(listing)).listing;

          expect(updated.priceSearch!.status, status);
          expect(updated.priceSearch!.comparables, isEmpty);
          expect(updated.priceSearch!.queries.depop, 'the phrase tried');
          expect(await listings.byId(listing.id), updated);
        }
      });

      test('searches again from the phrases the last search used', () async {
        final listing = await saved(draft());
        gateway.search = PriceSearch(
          status: PriceSearchStatus.unavailable,
          queries: const SearchQueries(
            depop: 'phrase the server was given',
            retail: 'retail phrase the server was given',
          ),
        );
        final after = (await controller().searchPrices(listing)).listing;
        gateway.searched.clear();

        await controller().searchPrices(after);

        expect(
          (gateway.searched.single['queries']! as Map)['depop'],
          'phrase the server was given',
        );
      });

      test('uses the phrases the person wrote, over every other', () async {
        final listing = await saved(draft());
        final edited = await controller().editQueries(
          listing,
          const SearchQueries(
            depop: 'nike 90s crewneck grey',
            retail: 'nike club fleece crew grey',
          ),
        );

        await controller().searchPrices(edited);

        expect(gateway.searched.single['queries'], {
          'depop': 'nike 90s crewneck grey',
          'retail': 'nike club fleece crew grey',
        });
      });

      group('looking again, when the listing already has prices', () {
        late Listing found;

        setUp(() async {
          found = (await controller().searchPrices(
            await saved(draft()),
          )).listing;
          expect(found.priceSearch!.status, PriceSearchStatus.ok);
          expect(found.priceSearch!.comparables, isNotEmpty);
        });

        PriceSearch answering(PriceSearchStatus status) =>
            PriceSearch(status: status, queries: found.priceSearch!.queries);

        for (final status in [
          PriceSearchStatus.notConfigured,
          PriceSearchStatus.quotaExceeded,
          PriceSearchStatus.unavailable,
        ]) {
          test('keeps them when the new answer is ${status.name}', () async {
            gateway.search = answering(status);

            final lookup = await controller().searchPrices(found);

            // The earlier search, untouched, and the new status for the screen
            // to say so with.
            expect(lookup.listing, found);
            expect(lookup.listing.priceSearch!.comparables, isNotEmpty);
            expect(lookup.failedWith, status);
          });
        }

        test('saves nothing when it keeps them', () async {
          gateway.search = answering(PriceSearchStatus.unavailable);

          await controller().searchPrices(found);

          // Not even a new time: a look-up that changed nothing must not move
          // the listing to the top of the Sell tab.
          expect(await listings.byId(found.id), found);
        });

        test('still asks the server, once, for the failure', () async {
          gateway.search = answering(PriceSearchStatus.quotaExceeded);
          gateway.searched.clear();

          await controller().searchPrices(found);

          expect(gateway.searched, hasLength(1));
        });

        test('keeps them again after a second failure', () async {
          gateway.search = answering(PriceSearchStatus.unavailable);
          final first = await controller().searchPrices(found);

          final second = await controller().searchPrices(first.listing);

          expect(second.listing, found);
          expect(second.failedWith, PriceSearchStatus.unavailable);
        });

        test('replaces them when the new answer found prices', () async {
          gateway.search = PriceSearch(
            status: PriceSearchStatus.ok,
            searchedAt: DateTime.utc(2026, 10, 18, 9),
            queries: found.priceSearch!.queries,
            comparables: [
              SaleComparable(
                title: 'Nike crewneck grey',
                url: Uri.parse('https://www.depop.com/products/example-3/'),
                priceCents: 2500,
                sold: true,
                match: ComparableMatch.similar,
              ),
            ],
          );

          final lookup = await controller().searchPrices(found);

          expect(lookup.failedWith, isNull);
          expect(lookup.listing.priceSearch, gateway.search);
          expect(lookup.listing.priceSearch!.comparables, hasLength(1));
          expect(await listings.byId(found.id), lookup.listing);
        });

        test('replaces them when it answered, and found nothing', () async {
          // An answer is not a failure. The server looked and nothing usable
          // came back, which is something to show, and it is not the server
          // being asleep.
          gateway.search = PriceSearch(
            status: PriceSearchStatus.ok,
            searchedAt: DateTime.utc(2026, 10, 18, 9),
            queries: const SearchQueries(
              depop: 'a different phrase',
              retail: 'another different phrase',
            ),
            excluded: const ExcludedCounts(notComparable: 4),
          );

          final lookup = await controller().searchPrices(found);

          expect(lookup.failedWith, isNull);
          expect(lookup.listing.priceSearch!.status, PriceSearchStatus.ok);
          expect(lookup.listing.priceSearch!.comparables, isEmpty);
        });

        test(
          'throws, and keeps them, when the server cannot be reached',
          () async {
            gateway.searchError = const ScanFailure('The server is asleep.');

            await expectLater(
              controller().searchPrices(found),
              throwsA(isA<ScanFailure>()),
            );

            expect(await listings.byId(found.id), found);
          },
        );
      });

      group('looking, when the listing has no prices yet', () {
        test('keeps a failure, which is all there is to keep', () async {
          final listing = await saved(draft());
          gateway.search = PriceSearch(
            status: PriceSearchStatus.quotaExceeded,
            queries: const SearchQueries(
              depop: 'the phrase tried',
              retail: 'the retail phrase tried',
            ),
          );

          final lookup = await controller().searchPrices(listing);

          // Nothing was lost, so nothing is reported as lost: the failure is
          // what the listing now holds, and it says so itself.
          expect(lookup.failedWith, isNull);
          expect(
            lookup.listing.priceSearch!.status,
            PriceSearchStatus.quotaExceeded,
          );
        });

        test('replaces an earlier failure with a later one', () async {
          final listing = await saved(draft());
          gateway.search = PriceSearch(
            status: PriceSearchStatus.unavailable,
            queries: const SearchQueries(
              depop: 'the phrase tried',
              retail: 'the retail phrase tried',
            ),
          );
          final first = await controller().searchPrices(listing);

          gateway.search = PriceSearch(
            status: PriceSearchStatus.notConfigured,
            queries: first.listing.priceSearch!.queries,
          );
          final second = await controller().searchPrices(first.listing);

          expect(second.failedWith, isNull);
          expect(
            second.listing.priceSearch!.status,
            PriceSearchStatus.notConfigured,
          );
        });
      });

      test('does nothing without a title to search with', () async {
        final listing = await saved(draft().copyWith(title: ' '));

        final same = (await controller().searchPrices(listing)).listing;

        expect(same, listing);
        expect(gateway.searched, isEmpty);
        expect(await listings.byId(listing.id), listing);
      });

      test('does nothing for a listing with nothing to search on', () async {
        final blank = await saved(
          Listing(
            id: const ListingId('blank'),
            createdAt: started,
            updatedAt: started,
          ),
        );

        final same = (await controller().searchPrices(blank)).listing;

        expect(same, blank);
        expect(gateway.searched, isEmpty);
      });

      test(
        'an answer it cannot read is a failure too, and changes nothing',
        () async {
          final listing = await saved(draft());

          for (final unreadable in <Exception>[
            ScanContractError('the response had no "result"'),
            const FormatException('not JSON'),
          ]) {
            gateway.searchError = unreadable;

            await expectLater(
              controller().searchPrices(listing),
              throwsA(
                isA<ScanFailure>()
                    .having(
                      (f) => f.message,
                      'message',
                      contains('cannot read'),
                    )
                    .having((f) => f.isRetryable, 'isRetryable', false),
              ),
              reason: '$unreadable',
            );
          }

          expect(await listings.byId(listing.id), listing);
        },
      );

      test(
        'throws, and changes nothing, when the server cannot be reached',
        () async {
          final listing = await saved(draft());
          gateway.searchError = const ScanFailure('The server is asleep.');

          await expectLater(
            controller().searchPrices(listing),
            throwsA(isA<ScanFailure>()),
          );

          expect(await listings.byId(listing.id), listing);
        },
      );
    });

    test('keeping the phrases the person wrote saves them', () async {
      final listing = await saved(draft());
      const written = SearchQueries(
        depop: 'nike 90s crewneck grey',
        retail: 'nike club fleece crew grey',
      );

      final edited = await controller().editQueries(listing, written);

      expect(edited.editedQueries, written);
      expect(edited.searchQueries, written);
      expect(edited.updatedAt.isAfter(started), isTrue);
      expect(await listings.byId(listing.id), edited);
      // Before any search: nothing was asked of the server.
      expect(gateway.searched, isEmpty);
    });

    group('its place in its life', () {
      test('posted', () async {
        final listing = await saved(draft());

        final posted = await controller().markListed(listing);

        expect(posted.status, ListingStatus.listed);
        expect(posted.listedAt, isNotNull);
        expect(posted.listedAt!.isUtc, isTrue);
        expect(posted.updatedAt, posted.listedAt);
        expect(await listings.byId(listing.id), posted);
      });

      test('posted again restarts the clock', () async {
        final listing = await saved(
          draft().markListed(DateTime.utc(2026, 10, 2)),
        );

        final refreshed = await controller().markListed(listing);

        expect(refreshed.listedAt!.isAfter(DateTime.utc(2026, 10, 2)), isTrue);
        expect(refreshed.needsRefresh(DateTime.now()), isFalse);
      });

      test('sold for the asking price unless told otherwise', () async {
        final listing = await saved(
          draft()
              .copyWith(priceCents: 3000)
              .markListed(DateTime.utc(2026, 10, 2)),
        );

        final sold = await controller().markSold(listing);

        expect(sold.status, ListingStatus.sold);
        expect(sold.soldPriceCents, 3000);
        expect(sold.soldAt!.isUtc, isTrue);
        expect(await listings.byId(listing.id), sold);
      });

      test('sold for what it sold for', () async {
        final listing = await saved(
          draft()
              .copyWith(priceCents: 3000)
              .markListed(DateTime.utc(2026, 10, 2)),
        );

        final sold = await controller().markSold(listing, priceCents: 2500);

        expect(sold.soldPriceCents, 2500);
      });

      test('and back to a draft', () async {
        final listing = await saved(
          draft()
              .markListed(DateTime.utc(2026, 10, 2))
              .markSold(DateTime.utc(2026, 10, 9), priceCents: 2800),
        );

        final back = await controller().backToDraft(listing);

        expect(back.status, ListingStatus.draft);
        expect(back.listedAt, isNull);
        expect(back.soldAt, isNull);
        expect(back.soldPriceCents, isNull);
        expect(back.updatedAt.isAfter(DateTime.utc(2026, 10, 9)), isTrue);
        expect(await listings.byId(listing.id), back);
      });
    });
  });

  group('selling the garment', () {
    Listing forGarment(ItemId? id) => Listing(
      id: const ListingId('l1'),
      itemId: id,
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
      title: 'Nike crewneck',
    );

    test('moves it out of the wardrobe, and says it did', () async {
      final item = await garment();

      final sold = await controller().markGarmentSold(forGarment(item.id));

      expect(sold, isTrue);
      expect((await wardrobe.byId(item.id))!.lifecycle, LifecycleState.sold);
    });

    test(
      'through the path that records it in the garment\'s history',
      () async {
        final item = await garment();

        await controller().markGarmentSold(forGarment(item.id));

        final changes = (await events.forItem(
          item.id,
        )).whereType<LifecycleChanged>();
        expect(changes.map((e) => e.to), [LifecycleState.sold]);
      },
    );

    test('for a listing with no garment, does nothing and says so', () async {
      await garment();

      final sold = await controller().markGarmentSold(forGarment(null));

      expect(sold, isFalse);
      expect(await events.all(), isEmpty);
    });

    test('for a garment that is not there, says it did not', () async {
      expect(
        await controller().markGarmentSold(forGarment(const ItemId('gone'))),
        isFalse,
      );
    });

    test('and for one that has been deleted', () async {
      final item = await garment(lifecycle: LifecycleState.removed);

      final sold = await controller().markGarmentSold(forGarment(item.id));

      expect(sold, isFalse);
      expect((await wardrobe.byId(item.id))!.lifecycle, LifecycleState.removed);
    });

    test(
      'and for one already given away, which cannot be sold from there',
      () async {
        final item = await garment(lifecycle: LifecycleState.donated);

        final sold = await controller().markGarmentSold(forGarment(item.id));

        expect(sold, isFalse);
        expect(
          (await wardrobe.byId(item.id))!.lifecycle,
          LifecycleState.donated,
        );
        expect(await events.forItem(item.id), isEmpty);
      },
    );

    test('one already sold is still sold', () async {
      final item = await garment(lifecycle: LifecycleState.sold);

      expect(await controller().markGarmentSold(forGarment(item.id)), isTrue);
    });

    test('leaves the listing as it is', () async {
      final item = await garment();
      final listing = await saved(forGarment(item.id));

      await controller().markGarmentSold(listing);

      expect(await listings.byId(listing.id), listing);
    });
  });

  group('deleting a listing', () {
    const id = ListingId('l1');

    test('removes it', () async {
      final listing = await saved(
        Listing(
          id: id,
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
        ),
      );

      await controller().delete(listing);

      expect(await listings.byId(id), isNull);
      expect(listings.length, 0);
    });

    test('and the photographs that were taken for it', () async {
      final photos = await controller().storePhotos(id, [
        (photo('A'), ListingShot.cover),
        (photo('B'), ListingShot.flaw),
      ]);
      final listing = await controller().createEmpty(id, photos);
      expect(images.length, 2);

      await controller().delete(listing);

      expect(images.length, 0);
      for (final p in photos) {
        expect(await images.read(p.uri), isNull);
      }
    });

    test('but not the garment\'s, which it only points at', () async {
      final item = await garment(
        photos: [(PhotoRole.front, 'F'), (PhotoRole.back, 'B')],
      );
      final made = await controller().openOrCreateForGarment(item.id);
      expect(made.listing.photos, hasLength(2));

      await controller().delete(made.listing);

      expect(await listings.byId(made.listing.id), isNull);
      for (final photo in item.photos.photos) {
        expect(await images.read(photo.uri), isNotNull, reason: photo.uri);
      }
      expect(images.length, 2);
    });

    test('nor the garment\'s cutouts', () async {
      final item = await garment(
        photos: [(PhotoRole.front, 'F')],
        cutouts: true,
      );
      final cutout = item.photos.photos.single.cutoutUri!;
      // A listing that shows the cutout of the garment's photograph.
      final listing = await saved(
        Listing(
          id: id,
          itemId: item.id,
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          photos: [ListingPhoto(uri: cutout, shot: ListingShot.cover)],
        ),
      );

      await controller().delete(listing);

      expect(await images.read(cutout), isNotNull);
    });

    test(
      'keeps what the garment holds and deletes what is the listing\'s',
      () async {
        final item = await garment(photos: [(PhotoRole.front, 'F')]);
        final own = await controller().storePhotos(id, [
          (photo('X'), ListingShot.flaw),
        ]);
        final listing = await saved(
          Listing(
            id: id,
            itemId: item.id,
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
            photos: [
              ListingPhoto(
                uri: item.photos.photos.single.uri,
                shot: ListingShot.cover,
              ),
              ...own,
            ],
          ),
        );

        await controller().delete(listing);

        expect(await images.read(item.photos.photos.single.uri), isNotNull);
        expect(await images.read(own.single.uri), isNull);
      },
    );

    test('a garment that is deleted still holds its photographs', () async {
      // A deleted garment is a row that says so, and the row still lists its
      // images. Nothing a wardrobe row names is deleted from here.
      final item = await garment(
        photos: [(PhotoRole.front, 'F')],
        lifecycle: LifecycleState.removed,
      );
      final listing = await saved(
        Listing(
          id: id,
          itemId: item.id,
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          photos: [
            ListingPhoto(
              uri: item.photos.photos.single.uri,
              shot: ListingShot.cover,
            ),
          ],
        ),
      );

      await controller().delete(listing);

      expect(await images.read(item.photos.photos.single.uri), isNotNull);
    });

    test(
      'a listing whose garment is gone altogether owns what it shows',
      () async {
        final photos = await controller().storePhotos(id, [
          (photo('A'), ListingShot.cover),
        ]);
        final listing = await saved(
          Listing(
            id: id,
            itemId: const ItemId('gone'),
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
            photos: photos,
          ),
        );

        await controller().delete(listing);

        expect(images.length, 0);
      },
    );

    test('a photograph that will not delete does not stop the rest', () async {
      final stuck = _FlakyStore(images, failsToDelete: {'-flaw-'});
      final container = _container(
        listings: listings,
        wardrobe: wardrobe,
        events: events,
        images: stuck,
        gateway: gateway,
      );
      addTearDown(container.dispose);
      final controller = container.read(listingControllerProvider);
      final photos = await controller.storePhotos(id, [
        (photo('A'), ListingShot.cover),
        (photo('B'), ListingShot.flaw),
        (photo('C'), ListingShot.back),
      ]);
      final listing = await controller.createEmpty(id, photos);

      await controller.delete(listing);

      expect(await listings.byId(id), isNull);
      // Only the one that would not go is left.
      expect(images.length, 1);
    });

    test('deleting one that is not there is not an error', () async {
      final listing = Listing(
        id: const ListingId('never-saved'),
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
      );

      await controller().delete(listing);

      expect(listings.length, 0);
    });

    test('leaves the other listings, and their photographs', () async {
      final mine = await controller().storePhotos(id, [
        (photo('A'), ListingShot.cover),
      ]);
      final other = await controller().storePhotos(const ListingId('l2'), [
        (photo('B'), ListingShot.cover),
      ]);
      final first = await controller().createEmpty(id, mine);
      await controller().createEmpty(const ListingId('l2'), other);

      await controller().delete(first);

      expect(listings.length, 1);
      expect(await images.read(other.single.uri), isNotNull);
    });
  });
}

/// A container with every dependency the controller reads replaced.
ProviderContainer _container({
  required InMemoryListingRepository listings,
  required InMemoryWardrobeRepository wardrobe,
  required InMemoryEventLog events,
  required ImageStore images,
  required _FakeGateway gateway,
}) => ProviderContainer(
  overrides: [
    listingRepositoryProvider.overrideWithValue(listings),
    wardrobeRepositoryProvider.overrideWithValue(wardrobe),
    eventLogProvider.overrideWithValue(events),
    imageStoreProvider.overrideWithValue(images),
    aiGatewayProvider.overrideWithValue(gateway),
    idGeneratorProvider.overrideWithValue(
      SequentialIdGenerator(prefix: 'listing'),
    ),
  ],
);

Uint8List _bytes(String mark) => Uint8List.fromList(utf8.encode(mark));

String _mark(ScanImage image) => utf8.decode(image.bytes);

/// The server, as far as the controller can tell.
///
/// Overrides the two calls and records what it was asked, as the demo's
/// canned gateway does. Never answers from a network.
class _FakeGateway extends AiGateway {
  _FakeGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  /// What a description answers.
  ListingFacts facts = ListingFacts(
    title: 'Nike vintage crewneck sweatshirt grey',
    itemType: ItemType.sweatshirt,
    brand: Confident('Nike', confidence: 0.93, source: Provenance.aiInference),
    colors: const ['Grey'],
    material: '80% cotton, 20% polyester',
    sizeOnTag: Confident('M', confidence: 0.9, source: Provenance.aiInference),
    styleWords: const ['vintage', 'crewneck'],
    era: '90s',
    visibleFlaws: const ['small mark on the left cuff'],
    searchQueries: const SearchQueries(
      depop: 'Nike vintage crewneck sweatshirt grey',
      retail: 'Nike Club Fleece crew sweatshirt grey',
    ),
  );

  /// Thrown instead of answering, when set.
  Object? describeError;

  final described =
      <({List<ScanImage> images, Map<String, Object?>? context})>[];

  @override
  Future<ListingFacts> describeListing(
    List<ScanImage> images, {
    Map<String, Object?>? context,
  }) async {
    described.add((images: images, context: context));
    if (describeError case final Object error) throw error;
    return facts;
  }

  /// What a price search answers.
  PriceSearch search = PriceSearch(
    status: PriceSearchStatus.ok,
    searchedAt: DateTime.utc(2026, 10, 17, 14, 5),
    provider: 'tavily',
    queries: const SearchQueries(
      depop: 'Nike vintage crewneck sweatshirt grey',
      retail: 'Nike Club Fleece crew sweatshirt grey',
    ),
    comparables: [
      SaleComparable(
        title: 'Vintage Nike grey crewneck sweatshirt',
        url: Uri.parse('https://www.depop.com/products/example-1/'),
        priceCents: 3200,
        sold: true,
        match: ComparableMatch.same,
      ),
      SaleComparable(
        title: 'Nike crewneck sweatshirt grey size M',
        url: Uri.parse('https://www.depop.com/products/example-2/'),
        priceCents: 2800,
        sold: false,
        match: ComparableMatch.same,
      ),
    ],
  );

  Object? searchError;

  final searched = <Map<String, Object?>>[];

  @override
  Future<PriceSearch> searchPrices(Map<String, Object?> request) async {
    searched.add(request);
    if (searchError case final Object error) throw error;
    return search;
  }
}

/// A store that cannot keep, or cannot delete, what it is told to.
///
/// Matches on the URI, which carries the name the photograph was given.
class _FlakyStore implements ImageStore {
  _FlakyStore(
    this._inner, {
    this.failsToSave = const {},
    this.failsToDelete = const {},
  });

  final ImageStore _inner;
  final Set<String> failsToSave;
  final Set<String> failsToDelete;

  @override
  Future<String> save(Uint8List bytes, {required String name}) async {
    if (failsToSave.any(name.contains)) {
      throw FileSystemException('No space left on device', name);
    }
    return _inner.save(bytes, name: name);
  }

  @override
  Future<Uint8List?> read(String uri) => _inner.read(uri);

  @override
  Future<void> delete(String uri) async {
    if (failsToDelete.any(uri.contains)) {
      throw FileSystemException('Permission denied', uri);
    }
    return _inner.delete(uri);
  }
}
