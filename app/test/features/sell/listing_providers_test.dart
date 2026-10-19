/// The listings, as the Sell screens watch them.
///
/// The list on the Sell tab and the editor open on one listing both have to be
/// live: a listing saved from one is the listing the other shows, with nobody
/// refreshing. These hold that against the in-memory repository, whose stream
/// follows the contract the Drift one is held to.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/features/sell/listing_controller.dart';

void main() {
  late InMemoryListingRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = InMemoryListingRepository();
    container = ProviderContainer(
      overrides: [listingRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
  });

  Listing listing(String id, {String title = 'Nike crewneck', int day = 1}) =>
      Listing(
        id: ListingId(id),
        createdAt: DateTime.utc(2026, 10, day),
        updatedAt: DateTime.utc(2026, 10, day),
        title: title,
      );

  group('every listing', () {
    test('is empty before anything is saved', () async {
      expect(await container.read(listingsProvider.future), isEmpty);
    });

    test('is newest first', () async {
      await repository.save(listing('old', day: 1));
      await repository.save(listing('new', day: 9));
      await repository.save(listing('middle', day: 5));

      final all = await container.read(listingsProvider.future);

      expect(all.map((l) => l.id.value), ['new', 'middle', 'old']);
    });

    test('follows a listing being saved, changed and deleted', () async {
      final seen = <List<String>>[];
      container.listen(listingsProvider, (_, next) {
        if (next.valueOrNull case final all?) {
          seen.add([for (final l in all) '${l.id.value}:${l.title}']);
        }
      }, fireImmediately: true);
      await pumpEventQueue();

      await repository.save(listing('a', title: 'First'));
      await pumpEventQueue();
      await repository.save(listing('a', title: 'Second'));
      await pumpEventQueue();
      await repository.delete(const ListingId('a'));
      await pumpEventQueue();

      expect(seen, [
        <String>[],
        ['a:First'],
        ['a:Second'],
        <String>[],
      ]);
    });

    test('follows the controller, which is how the screens save', () async {
      final seen = <int>[];
      container.listen(listingsProvider, (_, next) {
        if (next.valueOrNull case final all?) seen.add(all.length);
      }, fireImmediately: true);
      await pumpEventQueue();

      await container.read(listingControllerProvider).save(listing('a'));
      await pumpEventQueue();

      expect(seen, [0, 1]);
    });
  });

  group('one listing', () {
    const id = ListingId('a');

    test('is loading until the list has arrived', () {
      expect(container.read(listingProvider(id)).isLoading, isTrue);
    });

    test('is nothing for a listing that is not there', () async {
      await container.read(listingsProvider.future);

      final read = container.read(listingProvider(id));

      expect(read.hasValue, isTrue);
      expect(read.value, isNull);
    });

    test('is the listing, when it is', () async {
      await repository.save(listing('a'));
      await repository.save(listing('b', title: 'Other'));
      await container.read(listingsProvider.future);

      expect(container.read(listingProvider(id)).value, listing('a'));
      expect(
        container.read(listingProvider(const ListingId('b'))).value!.title,
        'Other',
      );
    });

    test('follows the listing as it changes', () async {
      await repository.save(listing('a', title: 'First'));
      final titles = <String?>[];
      container.listen(listingProvider(id), (_, next) {
        if (next.hasValue) titles.add(next.value?.title);
      }, fireImmediately: true);
      await pumpEventQueue();

      // Through the controller, as the editor saves.
      await container
          .read(listingControllerProvider)
          .save(listing('a', title: 'Second'));
      await pumpEventQueue();

      expect(titles, ['First', 'Second']);
    });

    test('is nothing once the listing is deleted', () async {
      await repository.save(listing('a'));
      final seen = <Listing?>[];
      container.listen(listingProvider(id), (_, next) {
        if (next.hasValue) seen.add(next.value);
      }, fireImmediately: true);
      await pumpEventQueue();

      await repository.delete(id);
      await pumpEventQueue();

      expect(seen, [listing('a'), null]);
    });

    test('is not told when some other listing changes', () async {
      // The editor open on one listing should not rebuild because another was
      // saved, on this screen or any other.
      await repository.save(listing('a'));
      await repository.save(listing('b'));
      var told = 0;
      container.listen(listingProvider(id), (_, next) {
        if (next.hasValue) told++;
      }, fireImmediately: true);
      await pumpEventQueue();
      expect(told, 1);

      await repository.save(listing('b', title: 'Changed'));
      await repository.save(listing('c'));
      await repository.delete(const ListingId('c'));
      await pumpEventQueue();

      expect(told, 1);
    });

    test('is told when its own listing changes by a hair', () async {
      // Listings are equal by value, so "changed" has to mean something did.
      await repository.save(listing('a'));
      var told = 0;
      container.listen(listingProvider(id), (_, next) {
        if (next.hasValue) told++;
      }, fireImmediately: true);
      await pumpEventQueue();

      await repository.save(listing('a').copyWith(notes: 'Ships Monday'));
      await pumpEventQueue();

      expect(told, 2);
    });

    test('is not told when it is saved as it already was', () async {
      await repository.save(listing('a'));
      var told = 0;
      container.listen(listingProvider(id), (_, next) {
        if (next.hasValue) told++;
      }, fireImmediately: true);
      await pumpEventQueue();

      await repository.save(listing('a'));
      await pumpEventQueue();

      expect(told, 1);
    });
  });
}
