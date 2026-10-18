/// The editor's working copy of one listing, and how it gets saved.
///
/// A screen that wrote every keystroke to the database would be slow and a
/// screen that wrote nothing until Save was tapped would lose what was typed
/// the moment somebody pressed Back. The editor has no Save button, so this is
/// the other thing: the listing is changed here, in memory, as fast as it is
/// typed, and stored a moment after the last change ([saveAfter]), or at once
/// when the person leaves ([flush]).
///
/// **Why a working copy, and not the stored listing.** The screen watches the
/// stored listing to know it exists, but it does not draw from it. Drawing from
/// the store would feed every save back into the text boxes a moment after it
/// was typed, and a box that is rewritten while somebody is typing in it moves
/// the cursor. The boxes are built once from the listing as it was loaded and
/// are edited from there; this is where their edits go.
///
/// **Writes are queued, never raced.** A save that is still being written when
/// the next one starts would let the older land second and put the older text
/// back. Each write waits for the one before, and each is the listing as it
/// stood when [flush] asked for it, so the last write is always the newest.
///
/// **Actions fold back, they do not replace.** Looking up prices can take half
/// a minute, and the person does not stop editing while it does. The
/// controller writes the listing it was handed, with the answer on it, which
/// by then is older than what is on screen. So what an action changed — the
/// prices found, the status — is taken from its result and put onto the
/// working copy, and if the working copy has moved on since, it is stored again
/// over the action's write. The edit typed during the wait survives it.
///
/// This holds no selling rule. What a status change means, how a sale is
/// recorded and what a look-up keeps are the controller's and the core's; this
/// decides only when what was typed is written.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../data/api/ai_gateway.dart' show ScanFailure;
import '../listing_controller.dart';

class ListingEditSession extends ChangeNotifier {
  ListingEditSession({
    required this._listing,
    required this._controller,
    this.saveAfter = const Duration(milliseconds: 600),
  });

  /// How long after the last change it is stored.
  ///
  /// Long enough that typing a sentence is one write and not forty, short
  /// enough that the window in which an interruption could lose a word is
  /// under a second.
  final Duration saveAfter;

  /// How long to wait before trying again after a write failed.
  static const Duration retryAfter = Duration(seconds: 5);

  final ListingController _controller;

  Listing _listing;

  Timer? _timer;
  bool _dirty = false;
  bool _disposed = false;
  bool _deleted = false;
  bool _saveFailed = false;
  int _running = 0;

  /// Every write waits on this one, so they land in the order they were asked.
  Future<void> _writing = Future<void>.value();

  /// The listing as it is on screen: the stored one, with what has been typed.
  Listing get listing => _listing;

  /// Whether the last write failed, and what was typed is not stored yet.
  ///
  /// It is tried again by itself, and on the next change or on leaving. Said
  /// to the person because the alternative is a screen that looks saved and
  /// is not.
  bool get saveFailed => _saveFailed;

  /// Whether a look-up, a status change or a sale is in flight.
  ///
  /// The listing is not to be deleted while one is: the controller writes the
  /// listing it was handed, and one that is written after it was deleted
  /// would be a listing nobody asked for.
  bool get busy => _running > 0;

  /// Changes the listing and stores it soon.
  ///
  /// [change] is given the listing as it stands now, not as it was when the
  /// caller last looked, so two changes in a row both apply. A change that
  /// leaves it as it was stores nothing.
  void edit(Listing Function(Listing listing) change) {
    if (_deleted) return;
    final next = change(_listing);
    if (next == _listing) return;

    _listing = next;
    _dirty = true;
    _schedule(saveAfter);
    _notify();
  }

  /// Stores whatever has not been, and completes once everything is stored.
  ///
  /// For leaving the screen, and before any action that reads the stored
  /// listing: the controller is handed the listing as it is now, so it has to
  /// have been written first for the two to agree.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;

    if (_dirty && !_deleted) {
      _dirty = false;
      final snapshot = _listing;
      _writing = _writing.then((_) => _write(snapshot));
    }
    return _writing;
  }

  Future<void> _write(Listing snapshot) async {
    if (_deleted) return;
    try {
      await _controller.save(snapshot);
      if (_saveFailed) {
        _saveFailed = false;
        _notify();
      }
    } on Object {
      // Kept dirty so that the next flush tries again. Nothing typed is
      // dropped because the disk said no once.
      _dirty = true;
      if (!_disposed) _schedule(retryAfter);
      if (!_saveFailed) {
        _saveFailed = true;
        _notify();
      }
    }
  }

  void _schedule(Duration after) {
    _timer?.cancel();
    _timer = Timer(after, () => unawaited(flush()));
  }

  // --- Actions ------------------------------------------------------------

  /// Looks up prices for the listing as it stands.
  ///
  /// Everything typed so far is stored first, so the phrases searched are the
  /// phrases in the boxes. The answer is put onto the working copy when the
  /// controller kept it; when it kept the earlier prices instead
  /// ([PriceLookup.failedWith]) nothing on the working copy changes.
  ///
  /// Throws [ScanFailure] when the server could not be reached or its answer
  /// could not be read.
  Future<PriceLookup> lookUpPrices() async {
    await flush();
    final sent = _listing;
    final lookup = await _during(() => _controller.searchPrices(sent));

    if (lookup.failedWith == null && lookup.listing != sent) {
      final written = lookup.listing;
      _fold(
        written,
        (now) => now.copyWith(
          priceSearch: written.priceSearch,
          updatedAt: written.updatedAt,
        ),
      );
    }
    return lookup;
  }

  /// Records that it was posted on Depop, now. Posted again, it is a refresh.
  Future<void> markListed() => _changeStatus(_controller.markListed);

  /// Records that it sold, for [priceCents] if given and for the asking price
  /// if not.
  Future<void> markSold({int? priceCents}) => _changeStatus(
    (listing) => _controller.markSold(listing, priceCents: priceCents),
  );

  /// Takes it back to a draft.
  Future<void> backToDraft() => _changeStatus(_controller.backToDraft);

  Future<void> _changeStatus(Future<Listing> Function(Listing) change) async {
    await flush();
    final sent = _listing;
    final written = await _during(() => change(sent));

    _fold(
      written,
      (now) => now.copyWith(
        status: written.status,
        listedAt: written.listedAt,
        clearListedAt: written.listedAt == null,
        soldAt: written.soldAt,
        clearSoldAt: written.soldAt == null,
        soldPriceCents: written.soldPriceCents,
        clearSoldPrice: written.soldPriceCents == null,
        updatedAt: written.updatedAt,
      ),
    );
  }

  /// Marks the garment this was made from as sold, and says whether it is.
  Future<bool> markGarmentSold() =>
      _during(() => _controller.markGarmentSold(_listing));

  /// Stores [image] as a photograph of [shot] and puts it on the listing.
  ///
  /// A cover goes first and anything else last, so the first photograph is
  /// the one a buyer sees first. False when it was not kept: the listing
  /// already holds as many as Depop takes, or the store would not keep it.
  Future<bool> addPhoto(ScanImage image, ListingShot shot) async {
    if (_listing.photos.length >= depopPhotoLimit) return false;

    final stored = await _controller.storePhotos(_listing.id, [(image, shot)]);
    if (stored.isEmpty) return false;

    final photo = stored.single;
    edit(
      (listing) => listing.copyWith(
        photos: [
          if (shot == ListingShot.cover) photo,
          ...listing.photos,
          if (shot != ListingShot.cover) photo,
        ],
      ),
    );
    return true;
  }

  /// Deletes the listing, and the photographs that were its own.
  ///
  /// From here nothing more is written: a change still waiting for its turn
  /// to be stored would put the listing back. What is already being written
  /// finishes first, for the same reason. False, and nothing done, while an
  /// action is running (see [busy]).
  Future<bool> delete() async {
    if (_deleted || busy) return false;

    _deleted = true;
    _timer?.cancel();
    _timer = null;
    try {
      await _writing;
      await _controller.delete(_listing);
    } on Object {
      _deleted = false;
      _dirty = true;
      rethrow;
    }
    _notify();
    return true;
  }

  // --- Behind the scenes --------------------------------------------------

  /// Runs [action], counting it as in flight while it does.
  Future<T> _during<T>(Future<T> Function() action) async {
    _running++;
    _notify();
    try {
      return await action();
    } finally {
      _running--;
      _notify();
    }
  }

  /// Puts what an action changed onto the working copy.
  ///
  /// [written] is the listing the action stored. If the working copy, once
  /// changed, is not that — the person typed while it was on its way — then
  /// the action's write has gone over their edit, and the working copy is
  /// stored again.
  void _fold(Listing written, Listing Function(Listing now) change) {
    if (_deleted) return;

    final folded = change(_listing);
    final moved = folded != _listing;
    _listing = folded;

    if (folded != written) {
      _dirty = true;
      unawaited(flush());
    }
    if (moved) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    // Once. A screen that is torn down while its session is being closed by
    // something else must not be told off for closing it twice.
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    // Whatever was typed last is stored even though nobody is looking.
    if (_dirty && !_deleted) unawaited(flush());
    super.dispose();
  }
}
