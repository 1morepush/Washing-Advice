/// Everything the Sell screens do to a listing.
///
/// The screens are meant to be only screens: they show a listing and say what
/// the person tapped. Starting one, storing its photographs, asking the server
/// to read them, looking up prices, marking it posted or sold, taking the
/// garment out of the wardrobe and deleting it all happen here, in the order
/// they have to happen in.
///
/// This holds no selling rule. Which source wins when a listing starts, what a
/// listing may be searched for, how a sale is recorded — each is the core's,
/// and this calls it. What is left is sequencing, which is the part that is
/// easy to get subtly wrong: a listing that is saved before the server has
/// answered, a photograph deleted that a garment still shows, a sale recorded
/// on the listing and not on the garment.
///
/// Times are stamped in UTC, as the core's clock is, so a listing posted on one
/// side of a time zone is still posted at the same moment on the other. Convert
/// with `toLocal()` to show one.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/images/image_store.dart';
import '../laundry/laundry_controller.dart';

/// The garment a listing was to be made from is not in the wardrobe.
///
/// Deleted, or an address for one that never was. The screen showing the
/// garment will have said so already; this is for the tap that raced it.
class GarmentNotFound implements Exception {
  const GarmentNotFound(this.id);

  final ItemId id;

  String get message => 'That item is no longer in your wardrobe.';

  @override
  String toString() => message;
}

/// What [ListingController.searchPrices] left the listing holding.
///
/// [failedWith] is set only when the look-up did not come back with prices and
/// **the listing already held some**: the earlier ones were kept, and this is
/// the status of the answer that was not, so that a screen can say the new
/// search failed instead of showing old prices as though they were new. It is
/// [PriceSearchStatus.ok] when the search ran and found nothing. Null
/// for every other outcome, including a first look-up that failed, because
/// then the failure is what the listing now holds and says for itself.
typedef PriceLookup = ({Listing listing, PriceSearchStatus? failedWith});

class ListingController {
  const ListingController(this._ref);

  final Ref _ref;

  ListingRepository get _listings => _ref.read(listingRepositoryProvider);

  /// A fresh id for a listing about to be made.
  ///
  /// Minted before anything is stored, because the photographs are named after
  /// the listing they belong to and are stored before the listing exists.
  ListingId newListingId() => ListingId(_ref.read(idGeneratorProvider).next());

  // --- Starting a listing -------------------------------------------------

  /// Stores photographs for the listing [id], in the order given.
  ///
  /// At most [depopPhotoLimit] of them, which is all Depop takes, so the rest
  /// are not kept. Returns what was stored, in order, ready to be handed to
  /// [createFromPhotos] or [createEmpty].
  ///
  /// A photograph that cannot be stored is left out of the result instead of
  /// failing the rest, as it is when a garment is scanned: storage that is full
  /// or refused is no reason to lose the others, and a missing one shows up
  /// where it matters — as a shot the checklist still asks for.
  Future<List<ListingPhoto>> storePhotos(
    ListingId id,
    List<(ScanImage, ListingShot)> shots,
  ) async {
    final store = _ref.read(imageStoreProvider);
    final taken = DateTime.now();
    final stored = <ListingPhoto>[];

    for (final (index, (image, shot)) in shots.take(depopPhotoLimit).indexed) {
      try {
        final uri = await store.save(
          Uint8List.fromList(image.bytes),
          // Distinct per photograph, because the stored name derives from it:
          // two flaws would otherwise resolve to one name and overwrite each
          // other, and a browser's clock is only as fine as a millisecond.
          name: listingImageName(
            id,
            shot,
            takenAt: taken.add(Duration(microseconds: index)),
          ),
        );
        stored.add(ListingPhoto(uri: uri, shot: shot));
      } on Exception {
        continue;
      }
    }
    return stored;
  }

  /// A draft listing from photographs the server reads.
  ///
  /// [photos] are the stored ones from [storePhotos] and [shots] the same
  /// photographs as they were taken. Both, because storing and reading are
  /// separate steps on purpose: when the server cannot read them the
  /// photographs are already kept, and the person can try again with the same
  /// [id] and [photos], or [createEmpty] and write it themselves.
  ///
  /// Only the photographs most worth reading go up: at most
  /// [AiGateway.describePhotoLimit], the cover first, then the brand tag, the
  /// size label, a flaw, the back, the care label and anything else. Nothing
  /// else is known about the garment, since it is not in the wardrobe.
  ///
  /// Throws [ScanFailure] when the server cannot be reached or its answer
  /// cannot be used, **and saves nothing**: a listing is only made once there
  /// is something to put in it.
  Future<Listing> createFromPhotos(
    ListingId id,
    List<ListingPhoto> photos,
    List<(ScanImage, ListingShot)> shots,
  ) async {
    final toRead = _inReadingOrder(
      shots,
      (shot) => shot.$2,
    ).take(AiGateway.describePhotoLimit);
    final facts = await _describe([for (final (image, _) in toRead) image]);

    return _put(
      Listing.fromFacts(id: id, now: _now(), facts: facts, photos: photos),
    );
  }

  /// A blank draft, for writing the listing by hand.
  ///
  /// For when the server cannot read the photographs, or the person would
  /// rather not ask it. The photographs are kept: they are the one part of the
  /// listing nobody has to type.
  Future<Listing> createEmpty(ListingId id, List<ListingPhoto> photos) =>
      _put(Listing.empty(id: id, now: _now(), photos: photos));

  /// The listing for a garment in the wardrobe: the unsold one it already has,
  /// or a new one.
  ///
  /// **Reused** when the garment has a draft or a listing up for sale
  /// (`reused`). Starting another would leave two to keep in step, so "Sell
  /// this" on a garment that is already being sold opens the one that is.
  ///
  /// Otherwise the garment's own photographs go to the server — up to
  /// [AiGateway.describePhotoLimit], the most telling first, as for
  /// [createFromPhotos] — with what the wardrobe knows of it, and the listing
  /// is made from both, the wardrobe's word winning where they differ. That is
  /// `Listing.fromGarment`'s rule, not this file's.
  ///
  /// **Reading the photographs is the one step that may fail without failing
  /// the listing.** When the server cannot be reached, answers with something
  /// unusable, or the garment has no photographs to send, the listing is made
  /// from the wardrobe alone and `describeFailed` says so, so the screen can
  /// tell the person what is missing instead of refusing to start. The
  /// wardrobe already knows the brand, the size and the fabric.
  ///
  /// Throws [GarmentNotFound] for a garment that is not in the wardrobe.
  Future<({Listing listing, bool reused, bool describeFailed})>
  openOrCreateForGarment(ItemId id) async {
    final existing = await _listings.unsoldFor(id);
    if (existing != null) {
      return (listing: existing, reused: true, describeFailed: false);
    }

    final item = await _ref.read(wardrobeRepositoryProvider).liveById(id);
    if (item == null) throw GarmentNotFound(id);

    ListingFacts? facts;
    final images = await _photosOf(item);
    if (images.isNotEmpty) {
      try {
        facts = await _describe(images, context: describeContextForItem(item));
      } on ScanFailure {
        // The wardrobe alone will do; `describeFailed` says what was missed.
        facts = null;
      }
    }

    final listing = await _put(
      Listing.fromGarment(
        id: newListingId(),
        now: _now(),
        item: item,
        facts: facts,
      ),
    );
    return (listing: listing, reused: false, describeFailed: facts == null);
  }

  // --- Changing a listing -------------------------------------------------

  /// Saves [listing], stamping when it was last changed.
  ///
  /// Returns what was saved, which is [listing] with its new time. The core
  /// never stamps a change by itself — the caller owns the clock — so every
  /// edit comes through here.
  Future<Listing> save(Listing listing) =>
      _put(listing.copyWith(updatedAt: _now()));

  /// Looks up what [listing] sells for and keeps the answer on it.
  ///
  /// Does nothing, and asks the server nothing, unless
  /// [Listing.canLookUpPrices]: the server needs a title and two phrases, and
  /// the core knows the rule.
  ///
  /// **Every status is kept**, not only a good one: a search with no key, no
  /// allowance left or no luck is an answer, and it carries the phrases that
  /// were tried, so they survive for the next look-up. An answer replaces
  /// whatever the listing found last time.
  ///
  /// **With one exception: prices are never lost to a failure.** When the
  /// listing already holds a search that found prices ([PriceSearchStatus.ok]
  /// with a comparable or a shop price) and the new answer did not, whether by
  /// another status or by an `ok` with nothing in it, the earlier search stays
  /// as it is and nothing is saved. The server being asleep, or the free allowance
  /// being spent, says nothing about what the listing sold for last week, and
  /// a person who looks again to refresh a price should not lose the evidence
  /// they had. [PriceLookup.failedWith] says what the new answer was.
  ///
  /// Throws [ScanFailure] when the server cannot be reached, answers with an
  /// error, or answers with something that cannot be read. Nothing is changed
  /// then.
  Future<PriceLookup> searchPrices(Listing listing) async {
    final queries = listing.searchQueries;
    if (!listing.canLookUpPrices || queries == null) {
      return (listing: listing, failedWith: null);
    }

    final request = priceSearchRequestJson(
      queries: queries,
      itemType: listing.itemType,
      title: listing.title,
      brand: listing.brand,
      colors: [for (final colour in listing.colours) colour.label],
    );
    final search = await _asking(
      () => _ref.read(aiGatewayProvider).searchPrices(request),
    );

    final held = listing.priceSearch;
    if (held != null && _foundPrices(held) && !_foundPrices(search)) {
      return (listing: listing, failedWith: search.status);
    }

    final saved = await _put(
      listing.copyWith(priceSearch: search, updatedAt: _now()),
    );
    return (listing: saved, failedWith: null);
  }

  /// Whether [search] answered with something to show: it ran, and came back
  /// with at least one comparable or one shop price.
  ///
  /// The server says `ok` for a search that ran and found nothing usable, and
  /// for a half-answered one, so the status alone is no measure of whether a
  /// search is worth holding on to.
  static bool _foundPrices(PriceSearch search) =>
      search.status == PriceSearchStatus.ok &&
      (search.comparables.isNotEmpty || search.retail.isNotEmpty);

  /// Keeps the two search phrases the person wrote, to be used from now on.
  ///
  /// Before the first search as well as after one: a wrong guess at the brand
  /// is a typo to fix and not a wasted search, and what was typed has to
  /// outlast the screen it was typed on.
  Future<Listing> editQueries(Listing listing, SearchQueries queries) =>
      save(listing.copyWith(editedQueries: queries));

  /// Records that it was posted on Depop, now.
  ///
  /// Doing it to a listing that is up already is how a refresh is recorded.
  Future<Listing> markListed(Listing listing) =>
      _put(listing.markListed(_now()));

  /// Records that it sold, now, for [priceCents] if given and the asking price
  /// if not.
  Future<Listing> markSold(Listing listing, {int? priceCents}) =>
      _put(listing.markSold(_now(), priceCents: priceCents));

  /// Takes it back to a draft: taken down, or "It sold" tapped by mistake.
  Future<Listing> backToDraft(Listing listing) =>
      _put(listing.backToDraft(at: _now()));

  /// Marks the garment [listing] was made from as sold, and says whether it is.
  ///
  /// Through the wardrobe's own way of moving a garment between states, so the
  /// move is recorded in its history and the garment leaves the wardrobe as
  /// any sold garment does. The answer is read back from the wardrobe rather
  /// than assumed: false when the listing has no garment, the garment has been
  /// deleted, or it has already left the wardrobe some other way (given away,
  /// say) and cannot be sold from there.
  Future<bool> markGarmentSold(Listing listing) async {
    final id = listing.itemId;
    if (id == null) return false;

    await _ref.read(laundryControllerProvider).move([id], LifecycleState.sold);

    final item = await _ref.read(wardrobeRepositoryProvider).byId(id);
    return item?.lifecycle == LifecycleState.sold;
  }

  /// Deletes [listing], and the photographs that were its own.
  ///
  /// **Never a garment's.** A listing made from a garment points at the
  /// garment's stored images instead of copying them, so deleting the listing
  /// leaves every image the garment holds, cutouts included. Only photographs
  /// taken for the listing go.
  ///
  /// A photograph taken for a listing is named after it, and no other listing
  /// holds it, so the garment is the only other owner there is to check. That
  /// stops being true the day a listing is made by copying another's
  /// photographs, and this is where to look then.
  ///
  /// The listing goes first. A photograph that will not delete is left where it
  /// is, which costs a few hundred kilobytes, and does not stop the rest.
  Future<void> delete(Listing listing) async {
    await _listings.delete(listing.id);

    final garmentId = listing.itemId;
    final garment = garmentId == null
        ? null
        : await _ref.read(wardrobeRepositoryProvider).byId(garmentId);
    final theirs = {
      for (final photo in garment?.photos.photos ?? const <ItemPhoto>[]) ...[
        photo.uri,
        ?photo.cutoutUri,
      ],
    };

    final store = _ref.read(imageStoreProvider);
    for (final photo in listing.photos) {
      if (theirs.contains(photo.uri)) continue;
      try {
        await store.delete(photo.uri);
      } on Exception {
        continue;
      }
    }
  }

  // --- Behind the scenes --------------------------------------------------

  DateTime _now() => DateTime.now().toUtc();

  Future<Listing> _put(Listing listing) async {
    await _listings.save(listing);
    return listing;
  }

  /// Asks the server to read [images].
  Future<ListingFacts> _describe(
    List<ScanImage> images, {
    Map<String, Object?>? context,
  }) => _asking(
    () =>
        _ref.read(aiGatewayProvider).describeListing(images, context: context),
  );

  /// A call to the server, whatever goes wrong becoming a [ScanFailure].
  ///
  /// The gateway already says "could not reach the server" and "that photo
  /// could not be read" as one. What it lets through is an answer it could not
  /// make sense of — a body that is not JSON, a draft with no title — and to a
  /// screen deciding whether to offer a retry that is the same thing: the
  /// request got nowhere, and sending it again will not change what the server
  /// sends back. So the screens catch one kind of failure from here, not three.
  Future<T> _asking<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ScanFailure {
      rethrow;
    } on Exception catch (error) {
      throw ScanFailure(
        'The server sent something this version cannot read. $error',
        isRetryable: false,
      );
    }
  }

  /// The garment's own photographs worth sending, read from the store.
  ///
  /// In [_readingOrder], originals and not cutouts — a model reads a label from
  /// the photograph, not from a silhouette of the garment — and stopping once
  /// there are enough. One whose file is gone is passed over for the next, so
  /// a wardrobe restored without its pictures still sends what survived.
  Future<List<ScanImage>> _photosOf(WardrobeItem item) async {
    final store = _ref.read(imageStoreProvider);
    final images = <ScanImage>[];

    for (final photo in _inReadingOrder(
      item.photos.photos,
      (photo) => ListingShot.fromPhotoRole(photo.role),
    )) {
      final bytes = await store.read(photo.uri);
      if (bytes == null || bytes.isEmpty) continue;

      images.add(ScanImage(bytes: bytes));
      if (images.length == AiGateway.describePhotoLimit) break;
    }
    return images;
  }

  /// [items] with the ones most worth the server's reading first.
  ///
  /// The server reads a handful of photographs, and a listing can have eight,
  /// so which go is a choice. The cover says what the thing is. Brand tag and
  /// size label come next because they are what a model can only read off a
  /// label and what buyers search by. A pictured flaw is what a description has
  /// to own up to. The back and the care label tell it least, and anything else
  /// is last. Photographs of one kind keep the order they were given in.
  List<T> _inReadingOrder<T>(
    Iterable<T> items,
    ListingShot Function(T item) shotOf,
  ) => [
    // A kind of shot the core adds later comes last, and is not left out.
    for (final shot in [
      ..._readingOrder,
      ...ListingShot.values.where((shot) => !_readingOrder.contains(shot)),
    ])
      for (final item in items)
        if (shotOf(item) == shot) item,
  ];

  static const _readingOrder = [
    ListingShot.cover,
    ListingShot.brandTag,
    ListingShot.sizeLabel,
    ListingShot.flaw,
    ListingShot.back,
    ListingShot.careLabel,
    ListingShot.other,
  ];
}

final listingControllerProvider = Provider<ListingController>(
  ListingController.new,
);
