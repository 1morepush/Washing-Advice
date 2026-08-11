/// Making a cutout for an item that does not have one.
///
/// Needed because cutouts are derived, and derived things go missing. An item
/// added before the feature existed has a photograph and no cutout; so does one
/// whose scan happened while the server was unreachable, or whose background
/// defeated the remover that day. Without a way to try again, those items keep
/// a colour swatch forever while everything scanned afterwards has a picture —
/// and the wardrobe ends up half one thing and half the other.
///
/// It re-reads the stored photograph rather than asking for a new one. The
/// bytes are already on the device, and making someone re-photograph a garment
/// to fix a background is asking them to do the app's work.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/images/image_store.dart';

enum CutoutStatus { idle, working, failed, done }

class CutoutController extends StateNotifier<CutoutStatus> {
  CutoutController(this._ref, this.itemId) : super(CutoutStatus.idle);

  final Ref _ref;

  /// Which garment this controller belongs to.
  ///
  /// The provider used to be a single app-wide notifier, so one failed cutout
  /// left every *other* garment's screen showing "could not be told apart from
  /// its background" in error red until the app was restarted.
  final ItemId itemId;

  /// Whether [item] could have a cutout made for it.
  ///
  /// Only requires a photograph to work from. It used to also require that no
  /// cutout existed yet — "the button should not offer to do something that is
  /// already done" — but that made a *bad* cutout permanent, and a bad cutout
  /// is worse than none: `PhotoSet.displayPhoto` prefers a photo that has one
  /// and `ItemPhoto.displayUri` returns it, so a mask that ate half the
  /// garment outranks the good original everywhere in the app.
  static bool isAvailableFor(WardrobeItem item) =>
      item.photos.displayPhoto != null;

  /// Every failure lands on [CutoutStatus.failed], including the ones nothing
  /// here predicts.
  ///
  /// The gateway already answers `null` rather than throwing when the server
  /// is unreachable, but the storage either side of it can still fail — a
  /// browser refusing a write because the origin is out of quota is the
  /// realistic one, and it happens precisely when saving an image. Left
  /// uncaught the state stayed `working`, which replaces the button with a
  /// spinner: the screen would have spun forever with nothing left to press.
  /// Every other controller in the app ends its risky work on a failure state
  /// for the same reason.
  Future<void> generate() async {
    state = CutoutStatus.working;

    try {
      final repository = _ref.read(wardrobeRepositoryProvider);
      final item = await repository.byId(itemId);
      final photo = item?.photos.displayPhoto;

      if (!mounted) return;
      if (item == null || photo == null) {
        state = CutoutStatus.failed;
        return;
      }

      final store = _ref.read(imageStoreProvider);
      final source = await store.read(photo.uri);
      if (!mounted) return;
      if (source == null || source.isEmpty) {
        // The row survived but the file did not — a restored backup, or
        // storage cleared. Nothing to re-cut, and no amount of retrying will
        // change it. Empty counts as gone: zero bytes is not an image, and
        // uploading it would spend a round trip to be told so.
        state = CutoutStatus.failed;
        return;
      }

      final cutout = await _ref
          .read(aiGatewayProvider)
          .cutout(ScanImage(bytes: source));

      if (!mounted) return;
      if (cutout == null) {
        state = CutoutStatus.failed;
        return;
      }

      // The name is a pure function of the photo, and both stores key by name,
      // so re-cutting the same photograph overwrites the previous mask rather
      // than leaking a file per attempt.
      final cutoutUri = await store.save(
        cutout,
        name: cutoutNameFor(item.id, photo),
      );
      await discardSupersededCutout(store, photo.cutoutUri, cutoutUri);

      await repository.save(
        item.copyWith(
          photos: item.photos.withCutout(photo.uri, cutoutUri),
          updatedAt: DateTime.now(),
        ),
      );

      if (!mounted) return;
      // The detail screen reads through a cached future; without this the user
      // watches the button succeed and the picture not change.
      _ref.invalidate(itemProvider(itemId));
      state = CutoutStatus.done;
    } on Exception {
      state = CutoutStatus.failed;
    }
  }

  void reset() => state = CutoutStatus.idle;
}

/// Deletes a cutout the new one has replaced under a different name.
///
/// Cutouts written before names carried a timestamp do not collide with the
/// ones written now, so overwriting no longer cleans up after itself. Failures
/// are swallowed: an orphaned file is a few hundred kilobytes, and refusing to
/// record a mask the user can see because a stale one would not delete is a
/// much worse trade.
Future<void> discardSupersededCutout(
  ImageStore store,
  String? previous,
  String current,
) async {
  if (previous == null || previous == current) return;
  try {
    await store.delete(previous);
  } on Exception {
    return;
  }
}

/// Keyed by item, so one garment's failure is not another garment's error.
///
/// Not `autoDispose`: a status is one enum value, and disposing the notifier
/// while a cutout is in flight would mean writing to a disposed notifier the
/// moment the request came back. Keeping it costs nothing and removes a whole
/// class of race.
final cutoutControllerProvider =
    StateNotifierProvider.family<CutoutController, CutoutStatus, ItemId>(
      CutoutController.new,
    );
