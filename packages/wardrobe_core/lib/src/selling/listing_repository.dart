/// Storage for listings.
///
/// Kept separate from `WardrobeRepository`, as saved outfits are. A listing
/// refers to a garment but does not contain it, the two have different
/// lifetimes — a listing outlives the garment it sold — and a wardrobe is
/// perfectly usable with nothing for sale. They are also stored differently:
/// listings live on the phone and are never synced.
///
/// The in-memory implementation below is not only a test double. It is what
/// the operations are *defined* to mean, and the shared contract suite in
/// `test/selling/listing_repository_test.dart` runs the same tests against it
/// and against the app's Drift implementation, so a divergence is a bug in the
/// SQL and not an open question.
library;

import 'dart:async';

import '../shared/ids.dart';
import 'listing.dart';

/// Reads and writes listings.
abstract interface class ListingRepository {
  /// Every listing — drafts, those up for sale and those sold — most recently
  /// updated first.
  ///
  /// Listings updated at the same instant are ordered by id, ascending, so that
  /// two saved in the same millisecond come back in the same order every time.
  /// Every method that returns listings follows this order.
  ///
  /// A person might sell a few hundred things over several years, and there is
  /// no query language and no paging here. If that assumption ever breaks,
  /// this is the one method that changes.
  Future<List<Listing>> all();

  /// One listing, or null when nothing has that id.
  Future<Listing?> byId(ListingId id);

  /// The listings made from one garment, most recently updated first.
  ///
  /// A garment can have several over time — one that sold, and a draft for
  /// something that came back — and listings with no garment never match.
  /// "Sell this" asks for these so that it can reopen an unsold listing instead
  /// of making a duplicate; see [UnsoldListings.unsoldFor].
  Future<List<Listing>> forItem(ItemId id);

  /// Inserts or replaces.
  Future<void> save(Listing listing);

  /// Removes a listing. Removing one that is not there is not an error.
  Future<void> delete(ListingId id);

  /// Every listing, most recently updated first, re-emitted whenever any of
  /// them changes.
  ///
  /// The current contents are delivered as soon as somebody listens, not only
  /// on the next change, so a screen that subscribes to an existing list does
  /// not wait for an edit to see it.
  Stream<List<Listing>> watchAll();
}

/// Lookups built on [ListingRepository.forItem].
extension UnsoldListings on ListingRepository {
  /// The listing for [id] that has not sold, or null when there is none.
  ///
  /// The newest if there are several. A draft or a listing that is up for sale
  /// is work in progress, and starting another for the same garment would leave
  /// two to keep in step; a sold one is finished, and selling the garment
  /// again — it came back, or it was bought a second time — starts afresh.
  Future<Listing?> unsoldFor(ItemId id) async {
    for (final listing in await forItem(id)) {
      if (listing.status != ListingStatus.sold) return listing;
    }
    return null;
  }
}

/// Holds listings in a map.
final class InMemoryListingRepository implements ListingRepository {
  InMemoryListingRepository([Iterable<Listing> initial = const []]) {
    for (final listing in initial) {
      _listings[listing.id] = listing;
    }
  }

  final Map<ListingId, Listing> _listings = {};
  final List<StreamController<List<Listing>>> _watchers = [];

  int get length => _listings.length;

  @override
  Future<List<Listing>> all() async => _newestFirst();

  @override
  Future<Listing?> byId(ListingId id) async => _listings[id];

  @override
  Future<List<Listing>> forItem(ItemId id) async => [
        for (final listing in _newestFirst())
          if (listing.itemId == id) listing,
      ];

  @override
  Future<void> save(Listing listing) async {
    _listings[listing.id] = listing;
    _notify();
  }

  @override
  Future<void> delete(ListingId id) async {
    _listings.remove(id);
    _notify();
  }

  @override
  Stream<List<Listing>> watchAll() {
    // Single-subscription rather than broadcast, for the reason spelled out on
    // `InMemoryWardrobeRepository.watch`: a broadcast controller drops the
    // snapshot pushed from `onListen`, which left a screen spinning forever.
    late final StreamController<List<Listing>> controller;
    controller = StreamController<List<Listing>>(
      onListen: () => controller.add(_newestFirst()),
      onCancel: () => _watchers.remove(controller),
    );
    _watchers.add(controller);
    return controller.stream;
  }

  /// Most recently updated first, with the id as a tie-break so two listings
  /// saved in the same millisecond still come back in a stable order.
  List<Listing> _newestFirst() {
    final listings = _listings.values.toList()
      ..sort((a, b) {
        final byDate = b.updatedAt.compareTo(a.updatedAt);
        return byDate != 0 ? byDate : a.id.value.compareTo(b.id.value);
      });
    return listings;
  }

  void _notify() {
    for (final controller in _watchers) {
      if (!controller.isClosed) controller.add(_newestFirst());
    }
  }
}
