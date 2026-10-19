/// The `ListingRepository` contract.
///
/// Exported rather than kept private so the app's Drift implementation runs
/// the same tests. Two implementations of one interface that are only ever
/// tested separately drift apart — that has happened to the wardrobe
/// repository, the event log and the outfit repository already — and the
/// failure is silent until somebody opens the Sell tab.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/selling_fixtures.dart';

typedef ListingRepositoryFactory = FutureOr<ListingRepository> Function();

void main() {
  runListingRepositoryContractTests(
    'InMemoryListingRepository',
    InMemoryListingRepository.new,
  );

  group('InMemoryListingRepository', () {
    test('starts with the listings it is given', () async {
      final repository = InMemoryListingRepository([
        draftListing(id: 'a'),
        draftListing(id: 'b'),
      ]);

      expect(repository.length, 2);
      expect(await repository.all(), hasLength(2));
    });
  });
}

/// A listing for the contract tests, with only what each test is about.
Listing buildListing({
  required String id,
  String? itemId,
  ListingStatus status = ListingStatus.draft,
  String title = 'Nike crewneck',
  DateTime? updatedAt,
}) {
  final listing = draftListing(
    id: id,
    title: title,
    updatedAt: updatedAt ?? DateTime.utc(2026, 10, 10),
    itemId: itemId == null ? null : ItemId(itemId),
  );
  return switch (status) {
    ListingStatus.draft => listing,
    ListingStatus.listed => listing.markListed(DateTime.utc(2026, 10, 2)),
    ListingStatus.sold => listing.copyWith(
        status: ListingStatus.sold,
        soldAt: DateTime.utc(2026, 10, 9),
        soldPriceCents: 2800,
      ),
  }
      .copyWith(updatedAt: updatedAt ?? DateTime.utc(2026, 10, 10));
}

List<String> ids(Iterable<Listing> listings) => [
      for (final listing in listings) listing.id.value,
    ];

void runListingRepositoryContractTests(
  String name,
  ListingRepositoryFactory create,
) {
  group('$name: storage', () {
    late ListingRepository repository;

    setUp(() async => repository = await create());

    test('an unknown id is null rather than an error', () async {
      expect(await repository.byId(const ListingId('nope')), isNull);
    });

    test('saves and reads back', () async {
      await repository.save(buildListing(id: 'a', title: 'Levi\'s 501'));

      final stored = await repository.byId(const ListingId('a'));
      expect(stored!.title, 'Levi\'s 501');
      expect(stored.id, const ListingId('a'));
    });

    test('saving the same id twice replaces rather than duplicates', () async {
      await repository.save(buildListing(id: 'a', title: 'First'));
      await repository.save(buildListing(id: 'a', title: 'Second'));

      expect((await repository.byId(const ListingId('a')))!.title, 'Second');
      expect(await repository.all(), hasLength(1));
    });

    test('every field survives a round trip', () async {
      final listing = fullListing();

      await repository.save(listing);

      final stored = (await repository.byId(listing.id))!;
      expect(stored.toJson(), listing.toJson());
      expect(stored, listing);
    });

    test('a listing with almost nothing in it survives too', () async {
      final blank = Listing.empty(
        id: const ListingId('blank'),
        now: DateTime.utc(2026, 10, 1),
      );

      await repository.save(blank);

      expect(await repository.byId(const ListingId('blank')), blank);
    });

    test('photographs keep their order, because the first is the cover',
        () async {
      final listing = draftListing(
        id: 'a',
        photos: const [
          ListingPhoto(uri: 'store://3.jpg', shot: ListingShot.back),
          ListingPhoto(uri: 'store://1.jpg', shot: ListingShot.cover),
          ListingPhoto(uri: 'store://2.jpg', shot: ListingShot.flaw),
        ],
      );

      await repository.save(listing);

      final stored = (await repository.byId(const ListingId('a')))!;
      expect([
        for (final p in stored.photos) p.uri
      ], [
        'store://3.jpg',
        'store://1.jpg',
        'store://2.jpg',
      ]);
    });

    test('saving one listing leaves the others alone', () async {
      await repository.save(buildListing(id: 'a', title: 'A'));
      await repository.save(buildListing(id: 'b', title: 'B'));
      await repository.save(buildListing(id: 'a', title: 'A again'));

      expect((await repository.byId(const ListingId('b')))!.title, 'B');
    });

    test('deleting removes it', () async {
      await repository.save(buildListing(id: 'a'));
      await repository.delete(const ListingId('a'));

      expect(await repository.byId(const ListingId('a')), isNull);
      expect(await repository.all(), isEmpty);
    });

    test('deleting something absent is not an error', () async {
      await repository.delete(const ListingId('nope'));

      expect(await repository.all(), isEmpty);
    });

    test('deleting one leaves the others', () async {
      await repository.save(buildListing(id: 'a'));
      await repository.save(buildListing(id: 'b'));

      await repository.delete(const ListingId('a'));

      expect(ids(await repository.all()), ['b']);
    });
  });

  group('$name: listing', () {
    late ListingRepository repository;

    setUp(() async => repository = await create());

    test('is empty before anything is saved', () async {
      expect(await repository.all(), isEmpty);
    });

    test('most recently updated first', () async {
      await repository.save(
        buildListing(id: 'old', updatedAt: DateTime.utc(2026, 1, 5)),
      );
      await repository.save(
        buildListing(id: 'new', updatedAt: DateTime.utc(2026, 8, 5)),
      );
      await repository.save(
        buildListing(id: 'middle', updatedAt: DateTime.utc(2026, 4, 5)),
      );

      expect(ids(await repository.all()), ['new', 'middle', 'old']);
    });

    test('puts a listing back at the top when it is saved again', () async {
      await repository.save(
        buildListing(id: 'a', updatedAt: DateTime.utc(2026, 1, 5)),
      );
      await repository.save(
        buildListing(id: 'b', updatedAt: DateTime.utc(2026, 2, 5)),
      );
      await repository.save(
        buildListing(id: 'a', updatedAt: DateTime.utc(2026, 3, 5)),
      );

      expect(ids(await repository.all()), ['a', 'b']);
    });

    test('a tie is broken stably rather than arbitrarily', () async {
      // Two listings saved in the same millisecond must not reorder
      // themselves between reads.
      final at = DateTime.utc(2026, 8, 5);
      await repository.save(buildListing(id: 'b', updatedAt: at));
      await repository.save(buildListing(id: 'a', updatedAt: at));
      await repository.save(buildListing(id: 'c', updatedAt: at));

      expect(ids(await repository.all()), ['a', 'b', 'c']);
      expect(ids(await repository.all()), ids(await repository.all()));
    });

    test('lists drafts, listings up for sale and sold ones together', () async {
      await repository.save(buildListing(id: 'draft'));
      await repository.save(
        buildListing(id: 'listed', status: ListingStatus.listed),
      );
      await repository.save(
        buildListing(id: 'sold', status: ListingStatus.sold),
      );

      final all = await repository.all();
      expect(all, hasLength(3));
      expect({for (final l in all) l.status}, ListingStatus.values.toSet());
    });
  });

  group('$name: for one garment', () {
    late ListingRepository repository;

    setUp(() async => repository = await create());

    test('finds the listings made from it', () async {
      await repository.save(buildListing(id: 'a', itemId: 'hoodie'));
      await repository.save(buildListing(id: 'b', itemId: 'jeans'));
      await repository.save(buildListing(id: 'c', itemId: 'hoodie'));

      final found = await repository.forItem(const ItemId('hoodie'));
      expect(ids(found)..sort(), ['a', 'c']);
    });

    test('most recently updated first', () async {
      await repository.save(
        buildListing(
          id: 'old',
          itemId: 'hoodie',
          updatedAt: DateTime.utc(2026, 1, 5),
        ),
      );
      await repository.save(
        buildListing(
          id: 'new',
          itemId: 'hoodie',
          updatedAt: DateTime.utc(2026, 8, 5),
        ),
      );

      expect(
        ids(await repository.forItem(const ItemId('hoodie'))),
        ['new', 'old'],
      );
    });

    test('a garment with none yields an empty list', () async {
      await repository.save(buildListing(id: 'a', itemId: 'hoodie'));

      expect(await repository.forItem(const ItemId('scarf')), isEmpty);
    });

    test('a listing made without a garment never matches one', () async {
      await repository.save(buildListing(id: 'a'));

      expect(await repository.forItem(const ItemId('hoodie')), isEmpty);
    });

    test('includes a garment\'s sold listings as well as its open ones',
        () async {
      await repository.save(
        buildListing(id: 'sold', itemId: 'hoodie', status: ListingStatus.sold),
      );
      await repository.save(buildListing(id: 'draft', itemId: 'hoodie'));

      expect(
        ids(await repository.forItem(const ItemId('hoodie')))..sort(),
        ['draft', 'sold'],
      );
    });

    test('follows a listing that is deleted', () async {
      await repository.save(buildListing(id: 'a', itemId: 'hoodie'));
      await repository.delete(const ListingId('a'));

      expect(await repository.forItem(const ItemId('hoodie')), isEmpty);
    });
  });

  group('$name: the unsold listing for a garment', () {
    late ListingRepository repository;

    setUp(() async => repository = await create());

    test('is a draft, if that is all there is', () async {
      await repository.save(buildListing(id: 'draft', itemId: 'hoodie'));

      expect(
        (await repository.unsoldFor(const ItemId('hoodie')))!.id.value,
        'draft',
      );
    });

    test('is a listing up for sale', () async {
      await repository.save(
        buildListing(id: 'up', itemId: 'hoodie', status: ListingStatus.listed),
      );

      expect(
        (await repository.unsoldFor(const ItemId('hoodie')))!.id.value,
        'up',
      );
    });

    test('is not a sold listing', () async {
      await repository.save(
        buildListing(id: 'sold', itemId: 'hoodie', status: ListingStatus.sold),
      );

      expect(await repository.unsoldFor(const ItemId('hoodie')), isNull);
    });

    test('is the open one, even when a newer one has sold', () async {
      await repository.save(
        buildListing(
          id: 'open',
          itemId: 'hoodie',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repository.save(
        buildListing(
          id: 'sold',
          itemId: 'hoodie',
          status: ListingStatus.sold,
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      );

      expect(
        (await repository.unsoldFor(const ItemId('hoodie')))!.id.value,
        'open',
      );
    });

    test('is the newest when there are several', () async {
      await repository.save(
        buildListing(
          id: 'older',
          itemId: 'hoodie',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repository.save(
        buildListing(
          id: 'newer',
          itemId: 'hoodie',
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      );

      expect(
        (await repository.unsoldFor(const ItemId('hoodie')))!.id.value,
        'newer',
      );
    });

    test('is nothing for a garment with no listings', () async {
      expect(await repository.unsoldFor(const ItemId('hoodie')), isNull);
    });

    test('is not another garment\'s', () async {
      await repository.save(buildListing(id: 'a', itemId: 'jeans'));

      expect(await repository.unsoldFor(const ItemId('hoodie')), isNull);
    });
  });

  group('$name: watching', () {
    late ListingRepository repository;

    setUp(() async => repository = await create());

    test('emits the current contents on subscribe', () async {
      // Not only on the next change. A screen that subscribes to an existing
      // list and is told nothing shows a spinner forever.
      await repository.save(buildListing(id: 'a'));

      expect(await repository.watchAll().first, hasLength(1));
    });

    test('emits an empty list on subscribe when there is nothing', () async {
      expect(await repository.watchAll().first, isEmpty);
    });

    test('emits the listings newest first', () async {
      await repository.save(
        buildListing(id: 'old', updatedAt: DateTime.utc(2026, 1, 5)),
      );
      await repository.save(
        buildListing(id: 'new', updatedAt: DateTime.utc(2026, 8, 5)),
      );

      expect(ids(await repository.watchAll().first), ['new', 'old']);
    });

    test('re-emits when something is saved', () async {
      final seen = <int>[];
      final subscription = repository.watchAll().listen(
            (list) => seen.add(list.length),
          );

      await pumpEventQueue();
      await repository.save(buildListing(id: 'a'));
      await pumpEventQueue();

      expect(seen.last, 1);
      await subscription.cancel();
    });

    test('re-emits when something already saved is changed', () async {
      await repository.save(buildListing(id: 'a', title: 'First'));

      final seen = <String>[];
      final subscription = repository.watchAll().listen(
            (list) => seen.add(list.single.title),
          );

      await pumpEventQueue();
      await repository.save(buildListing(id: 'a', title: 'Second'));
      await pumpEventQueue();

      expect(seen, ['First', 'Second']);
      await subscription.cancel();
    });

    test('re-emits when something is deleted', () async {
      await repository.save(buildListing(id: 'a'));

      final seen = <int>[];
      final subscription = repository.watchAll().listen(
            (list) => seen.add(list.length),
          );

      await pumpEventQueue();
      await repository.delete(const ListingId('a'));
      await pumpEventQueue();

      expect(seen.last, 0);
      await subscription.cancel();
    });

    test('tells every watcher', () async {
      final first = <int>[];
      final second = <int>[];
      final a = repository.watchAll().listen((l) => first.add(l.length));
      final b = repository.watchAll().listen((l) => second.add(l.length));

      await pumpEventQueue();
      await repository.save(buildListing(id: 'x'));
      await pumpEventQueue();

      expect(first.last, 1);
      expect(second.last, 1);
      await a.cancel();
      await b.cancel();
    });

    test('stops telling a watcher that has gone', () async {
      final seen = <int>[];
      final gone = repository.watchAll().listen((l) => seen.add(l.length));
      final stays = <int>[];
      final other = repository.watchAll().listen((l) => stays.add(l.length));

      await pumpEventQueue();
      await gone.cancel();
      final before = seen.length;
      await repository.save(buildListing(id: 'x'));
      await pumpEventQueue();

      expect(seen.length, before);
      expect(stays.last, 1);
      await other.cancel();
    });
  });
}
