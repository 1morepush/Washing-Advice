/// How the editor stores what is typed.
///
/// There is no Save button, so everything here is a promise the screen makes
/// without being asked: that a word typed a moment ago is stored, that leaving
/// does not lose it, that two writes never land in the wrong order, and that a
/// price look-up taking half a minute does not quietly put the listing back
/// as it was when it started. Each is a way a listing loses a sentence somebody
/// wrote, and none of them shows until it has happened.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/sell/editor/edit_session.dart';
import 'package:washing_advice/features/sell/listing_controller.dart';

void main() {
  late _SpyListings listings;
  late _FakeGateway gateway;
  late MemoryImageStore images;
  late ProviderContainer container;
  late ListingEditSession session;

  /// Short, so the tests wait for a real timer without waiting long.
  const pause = Duration(milliseconds: 30);
  const longerThanThePause = Duration(milliseconds: 90);

  Listing draft({String title = 'Nike crewneck'}) => Listing(
    id: const ListingId('l1'),
    createdAt: DateTime.utc(2026, 10, 1),
    updatedAt: DateTime.utc(2026, 10, 1),
    title: title,
    itemType: ItemType.sweatshirt,
    brand: 'Nike',
  );

  /// A session on [listing], which is in the store already.
  Future<ListingEditSession> open(Listing listing) async {
    await listings.save(listing);
    listings.writes.clear();
    final opened = ListingEditSession(
      listing: listing,
      controller: container.read(listingControllerProvider),
      saveAfter: pause,
    );
    addTearDown(opened.dispose);
    return opened;
  }

  Future<String?> storedTitle() async =>
      (await listings.byId(const ListingId('l1')))?.title;

  /// Lets the queue of futures run until [done], or fails.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(done(), isTrue, reason: 'it never happened');
  }

  setUp(() async {
    listings = _SpyListings();
    gateway = _FakeGateway();
    images = MemoryImageStore();
    container = ProviderContainer(
      overrides: [
        listingRepositoryProvider.overrideWithValue(listings),
        wardrobeRepositoryProvider.overrideWithValue(
          InMemoryWardrobeRepository(),
        ),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(images),
        aiGatewayProvider.overrideWithValue(gateway),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'id'),
        ),
      ],
    );
    addTearDown(container.dispose);
    session = await open(draft());
  });

  group('a change', () {
    test('is on the listing at once, and stored after a pause', () async {
      session.edit((l) => l.copyWith(title: 'Nike vintage crewneck'));

      expect(session.listing.title, 'Nike vintage crewneck');
      expect(await storedTitle(), 'Nike crewneck');

      await Future<void>.delayed(longerThanThePause);

      expect(await storedTitle(), 'Nike vintage crewneck');
    });

    test('tells whoever is drawing it', () async {
      var told = 0;
      session.addListener(() => told++);

      session.edit((l) => l.copyWith(title: 'Changed'));

      expect(told, 1);
    });

    test('is one write for a run of them, with the last of them', () async {
      for (final title in ['N', 'Ni', 'Nik', 'Nike', 'Nike v', 'Nike vi']) {
        session.edit((l) => l.copyWith(title: title));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(longerThanThePause);

      expect(listings.writes.map((l) => l.title), ['Nike vi']);
    });

    test('applies to the listing as it stands, not as it was seen', () {
      session
        ..edit((l) => l.copyWith(title: 'A new title'))
        ..edit((l) => l.copyWith(brand: 'Adidas'));

      expect(session.listing.title, 'A new title');
      expect(session.listing.brand, 'Adidas');
    });

    test('that changes nothing stores nothing', () async {
      var told = 0;
      session.addListener(() => told++);

      session.edit((l) => l.copyWith(title: l.title));
      await session.flush();
      await Future<void>.delayed(longerThanThePause);

      expect(told, 0);
      expect(listings.writes, isEmpty);
    });

    test('is stored at once by flush, and not a second time after', () async {
      session.edit((l) => l.copyWith(title: 'Left in a hurry'));

      await session.flush();

      expect(await storedTitle(), 'Left in a hurry');
      await Future<void>.delayed(longerThanThePause);
      expect(listings.writes, hasLength(1));
    });

    test('is stamped as changed when it is stored', () async {
      session.edit((l) => l.copyWith(title: 'Newer'));

      await session.flush();

      final stored = (await listings.byId(const ListingId('l1')))!;
      expect(stored.updatedAt.isAfter(DateTime.utc(2026, 10, 1)), isTrue);
    });

    test('is stored when the session goes before the pause is up', () async {
      // Leaving by a route that is not a pop: the screen is simply gone.
      session.edit((l) => l.copyWith(title: 'Typed, then gone'));

      session.dispose();
      await until(() => listings.writes.isNotEmpty);

      expect(await storedTitle(), 'Typed, then gone');
    });
  });

  group('flushing with nothing to store', () {
    test('writes nothing and completes', () async {
      await session.flush();

      expect(listings.writes, isEmpty);
    });
  });

  group('writes', () {
    test('land in the order they were asked for', () async {
      // The first is held up in the store. The second must not overtake it.
      listings.gate = Completer<void>();
      session.edit((l) => l.copyWith(title: 'First'));
      final first = session.flush();
      await until(() => listings.waiting == 1);

      session.edit((l) => l.copyWith(title: 'Second'));
      final second = session.flush();
      await Future<void>.delayed(longerThanThePause);
      expect(listings.writes, isEmpty);

      listings.gate!.complete();
      await Future.wait([first, second]);

      expect(listings.writes.map((l) => l.title), ['First', 'Second']);
      expect(await storedTitle(), 'Second');
    });
  });

  group('a write that fails', () {
    test('keeps the change, says it is not stored, and tries again', () async {
      listings.failures = 1;
      session.edit((l) => l.copyWith(title: 'Not lost'));

      await session.flush();

      expect(session.saveFailed, isTrue);
      expect(session.listing.title, 'Not lost');
      expect(await storedTitle(), 'Nike crewneck');

      // By itself, after a while, and on the next flush as well.
      await session.flush();
      expect(session.saveFailed, isFalse);
      expect(await storedTitle(), 'Not lost');
    });

    test('is stored with whatever is typed after it', () async {
      listings.failures = 1;
      session.edit((l) => l.copyWith(title: 'Not lost'));
      await session.flush();

      session.edit((l) => l.copyWith(brand: 'Adidas'));
      await session.flush();

      final stored = (await listings.byId(const ListingId('l1')))!;
      expect(stored.title, 'Not lost');
      expect(stored.brand, 'Adidas');
      expect(session.saveFailed, isFalse);
    });
  });

  group('looking up prices', () {
    test('stores what was typed first, and searches for it', () async {
      session
        ..edit(
          (l) => l.copyWith(
            editedQueries: const SearchQueries(
              depop: 'nike 90s crewneck grey',
              retail: 'nike club fleece crew grey',
            ),
          ),
        )
        ..edit((l) => l.copyWith(title: 'Nike 90s crewneck grey'));

      await session.lookUpPrices();

      expect(gateway.searched.single['queries'], {
        'depop': 'nike 90s crewneck grey',
        'retail': 'nike club fleece crew grey',
      });
      expect(await storedTitle(), 'Nike 90s crewneck grey');
    });

    test('puts what it found on the listing, and stores it', () async {
      final lookup = await session.lookUpPrices();

      expect(lookup.failedWith, isNull);
      expect(session.listing.priceSearch, gateway.search);
      final stored = (await listings.byId(const ListingId('l1')))!;
      expect(stored.priceSearch, gateway.search);
    });

    test('is busy while it waits, and not before or after', () async {
      gateway.hold = Completer<void>();
      expect(session.busy, isFalse);

      final lookup = session.lookUpPrices();
      await until(() => gateway.searched.isNotEmpty);
      expect(session.busy, isTrue);

      gateway.hold!.complete();
      await lookup;
      expect(session.busy, isFalse);
    });

    test('keeps what was typed and stored while it was on its way', () async {
      // The look-up is slow, as it is when the server is asleep, and the
      // person goes on writing. What they wrote is stored by the pause. Then
      // the answer comes back, and the controller stores the listing it was
      // handed, with the answer on it, over what they wrote.
      gateway.hold = Completer<void>();
      final lookup = session.lookUpPrices();
      await until(() => gateway.searched.isNotEmpty);

      session.edit((l) => l.copyWith(title: 'Typed while waiting'));
      await until(() => listings.writes.isNotEmpty);
      expect(await storedTitle(), 'Typed while waiting');

      gateway.hold!.complete();
      await lookup;
      await session.flush();

      expect(session.listing.title, 'Typed while waiting');
      expect(session.listing.priceSearch, gateway.search);

      final stored = (await listings.byId(const ListingId('l1')))!;
      expect(stored.title, 'Typed while waiting');
      expect(stored.priceSearch, gateway.search);
    });

    test('keeps what was typed too lately to be stored, too', () async {
      gateway.hold = Completer<void>();
      final lookup = session.lookUpPrices();
      await until(() => gateway.searched.isNotEmpty);

      session
        ..edit((l) => l.copyWith(title: 'Typed while waiting'))
        ..edit((l) => l.copyWith(notes: 'Ships Monday'));
      gateway.hold!.complete();
      await lookup;
      await session.flush();

      final stored = (await listings.byId(const ListingId('l1')))!;
      expect(stored.title, 'Typed while waiting');
      expect(stored.notes, 'Ships Monday');
      expect(stored.priceSearch, gateway.search);
    });

    test('keeps the earlier prices when the new answer is a failure', () async {
      await session.lookUpPrices();
      final earlier = session.listing.priceSearch;
      gateway.search = PriceSearch(
        status: PriceSearchStatus.unavailable,
        queries: earlier!.queries,
      );

      final lookup = await session.lookUpPrices();

      expect(lookup.failedWith, PriceSearchStatus.unavailable);
      expect(session.listing.priceSearch, earlier);
      final stored = (await listings.byId(const ListingId('l1')))!;
      expect(stored.priceSearch, earlier);
    });

    test('does not store a failure over what was typed', () async {
      await session.lookUpPrices();
      gateway.search = PriceSearch(
        status: PriceSearchStatus.quotaExceeded,
        queries: gateway.search.queries,
      );
      gateway.hold = Completer<void>();
      final lookup = session.lookUpPrices();
      await until(() => gateway.searched.length == 2);

      session.edit((l) => l.copyWith(title: 'Typed while waiting'));
      gateway.hold!.complete();
      await lookup;
      await session.flush();

      expect(await storedTitle(), 'Typed while waiting');
    });

    test('throws what the server threw, and changes nothing', () async {
      gateway.error = const ScanFailure('The server is asleep.');

      await expectLater(session.lookUpPrices(), throwsA(isA<ScanFailure>()));

      expect(session.busy, isFalse);
      expect(session.listing, draft());
    });

    test('does nothing for a listing that cannot be searched', () async {
      final blank = await open(draft(title: ' ').copyWith(clearBrand: true));

      final lookup = await blank.lookUpPrices();

      expect(lookup.failedWith, isNull);
      expect(gateway.searched, isEmpty);
    });
  });

  group('where it has got to', () {
    test('is posted, and stored', () async {
      await session.markListed();

      expect(session.listing.status, ListingStatus.listed);
      expect(session.listing.listedAt, isNotNull);
      final stored = (await listings.byId(const ListingId('l1')))!;
      expect(stored.status, ListingStatus.listed);
      expect(stored.listedAt, session.listing.listedAt);
    });

    test('is stored with what was typed before it', () async {
      session.edit((l) => l.copyWith(title: 'Typed, then posted'));

      await session.markListed();

      final stored = (await listings.byId(const ListingId('l1')))!;
      expect(stored.title, 'Typed, then posted');
      expect(stored.status, ListingStatus.listed);
    });

    test('is sold for what it sold for', () async {
      session.edit((l) => l.copyWith(priceCents: 3000));
      await session.markListed();

      await session.markSold(priceCents: 2700);

      expect(session.listing.status, ListingStatus.sold);
      expect(session.listing.soldPriceCents, 2700);
      expect(session.listing.priceCents, 3000);
      expect(session.listing.soldAt, isNotNull);
      final stored = (await listings.byId(const ListingId('l1')))!;
      expect(stored.soldPriceCents, 2700);
    });

    test('is sold for the asking price unless told otherwise', () async {
      session.edit((l) => l.copyWith(priceCents: 3000));

      await session.markSold();

      expect(session.listing.soldPriceCents, 3000);
    });

    test('is back to a draft, forgetting when it was posted', () async {
      await session.markListed();
      await session.markSold(priceCents: 2500);

      await session.backToDraft();

      expect(session.listing.status, ListingStatus.draft);
      expect(session.listing.listedAt, isNull);
      expect(session.listing.soldAt, isNull);
      expect(session.listing.soldPriceCents, isNull);
      final stored = (await listings.byId(const ListingId('l1')))!;
      expect(stored.status, ListingStatus.draft);
      expect(stored.soldPriceCents, isNull);
    });

    test('is the same as the stored listing once it is stored', () async {
      session.edit((l) => l.copyWith(title: 'Typed'));
      await session.markListed();
      await session.flush();

      expect(await listings.byId(const ListingId('l1')), session.listing);
    });
  });

  group('photographs', () {
    ScanImage photo(int mark) => ScanImage(bytes: Uint8List.fromList([mark]));

    test('go last, stored and on the listing', () async {
      session = await open(
        draft().copyWith(
          photos: const [
            ListingPhoto(uri: 'wa-memory:a', shot: ListingShot.cover),
          ],
        ),
      );

      final added = await session.addPhoto(photo(1), ListingShot.brandTag);

      expect(added, isTrue);
      expect(session.listing.photos.map((p) => p.shot), [
        ListingShot.cover,
        ListingShot.brandTag,
      ]);
      expect(images.length, 1);
      expect(await images.read(session.listing.photos.last.uri), [1]);
    });

    test('that are covers go first', () async {
      session = await open(
        draft().copyWith(
          photos: const [
            ListingPhoto(uri: 'wa-memory:a', shot: ListingShot.back),
          ],
        ),
      );

      await session.addPhoto(photo(1), ListingShot.cover);

      expect(session.listing.photos.map((p) => p.shot), [
        ListingShot.cover,
        ListingShot.back,
      ]);
    });

    test('are not kept past what Depop takes', () async {
      session = await open(
        draft().copyWith(
          photos: [
            for (var i = 0; i < depopPhotoLimit; i++)
              ListingPhoto(uri: 'wa-memory:$i', shot: ListingShot.other),
          ],
        ),
      );

      final added = await session.addPhoto(photo(1), ListingShot.flaw);

      expect(added, isFalse);
      expect(session.listing.photos, hasLength(depopPhotoLimit));
      // Not stored either: a file nothing points at would never be deleted.
      expect(images.length, 0);
    });
  });

  group('deleting', () {
    test('removes the listing', () async {
      final deleted = await session.delete();

      expect(deleted, isTrue);
      expect(await listings.byId(const ListingId('l1')), isNull);
    });

    test('is not undone by what was waiting to be stored', () async {
      session.edit((l) => l.copyWith(title: 'Typed, then deleted'));

      await session.delete();
      await Future<void>.delayed(longerThanThePause);

      expect(await listings.byId(const ListingId('l1')), isNull);
      expect(listings.writes, isEmpty);
    });

    test('waits for a write in flight and is not undone by it', () async {
      listings.gate = Completer<void>();
      session.edit((l) => l.copyWith(title: 'First'));
      unawaited(session.flush());
      await until(() => listings.waiting == 1);
      session.edit((l) => l.copyWith(title: 'Second'));

      final deleting = session.delete();
      await Future<void>.delayed(longerThanThePause);
      listings.gate!.complete();
      await deleting;
      await Future<void>.delayed(longerThanThePause);

      expect(await listings.byId(const ListingId('l1')), isNull);
    });

    test('is refused while prices are being looked up', () async {
      // The look-up would store the listing again when it came back.
      gateway.hold = Completer<void>();
      final lookup = session.lookUpPrices();
      await until(() => gateway.searched.isNotEmpty);

      final deleted = await session.delete();
      gateway.hold!.complete();
      await lookup;

      expect(deleted, isFalse);
      expect(await listings.byId(const ListingId('l1')), isNotNull);
    });

    test('takes nothing more from the screen once it is done', () async {
      await session.delete();

      session.edit((l) => l.copyWith(title: 'Too late'));
      await session.flush();
      await Future<void>.delayed(longerThanThePause);

      expect(await listings.byId(const ListingId('l1')), isNull);
    });
  });
}

/// A repository that records what it is asked to store, and can be made to
/// hold a write up or refuse one.
class _SpyListings implements ListingRepository {
  final InMemoryListingRepository _inner = InMemoryListingRepository();

  /// What was stored, in order, since it was last cleared.
  final List<Listing> writes = [];

  /// While set, a write waits for it to complete before it lands.
  Completer<void>? gate;

  /// How many writes are waiting on [gate].
  int waiting = 0;

  /// How many of the next writes fail.
  int failures = 0;

  @override
  Future<void> save(Listing listing) async {
    if (failures > 0) {
      failures--;
      throw StateError('the disk is full');
    }
    if (gate case final Completer<void> held) {
      waiting++;
      await held.future;
      waiting--;
    }
    writes.add(listing);
    await _inner.save(listing);
  }

  @override
  Future<List<Listing>> all() => _inner.all();

  @override
  Future<Listing?> byId(ListingId id) => _inner.byId(id);

  @override
  Future<List<Listing>> forItem(ItemId id) => _inner.forItem(id);

  @override
  Future<void> delete(ListingId id) => _inner.delete(id);

  @override
  Stream<List<Listing>> watchAll() => _inner.watchAll();
}

/// The server, as far as the editor can tell: it answers what it is told to,
/// when it is let to.
class _FakeGateway extends AiGateway {
  _FakeGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  PriceSearch search = PriceSearch(
    status: PriceSearchStatus.ok,
    searchedAt: DateTime.utc(2026, 10, 17, 14, 5),
    provider: 'tavily',
    queries: const SearchQueries(
      depop: 'Nike crewneck',
      retail: 'Nike Club Fleece crew',
    ),
    comparables: [
      SaleComparable(
        title: 'Nike crewneck sweatshirt',
        url: Uri.parse('https://www.depop.com/products/example-1/'),
        priceCents: 3200,
        sold: true,
        match: ComparableMatch.same,
      ),
    ],
  );

  /// While set, a look-up waits for it to complete before it answers.
  Completer<void>? hold;

  /// Thrown instead of answering, when set.
  Object? error;

  final List<Map<String, Object?>> searched = [];

  @override
  Future<PriceSearch> searchPrices(Map<String, Object?> request) async {
    searched.add(request);
    if (hold case final Completer<void> held) await held.future;
    if (error case final Object thrown) throw thrown;
    return search;
  }
}
