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
  CutoutController(this._ref) : super(CutoutStatus.idle);

  final Ref _ref;

  /// Whether [item] could have a cutout made for it.
  ///
  /// False when there is no photograph to work from, and false when one
  /// already exists — the button should not offer to do something that is
  /// already done.
  static bool isAvailableFor(WardrobeItem item) {
    final photo = item.photos.displayPhoto;
    return photo != null && !photo.hasCutout;
  }

  Future<void> generate(ItemId id) async {
    state = CutoutStatus.working;

    final repository = _ref.read(wardrobeRepositoryProvider);
    final item = await repository.byId(id);
    final photo = item?.photos.displayPhoto;

    if (item == null || photo == null) {
      state = CutoutStatus.failed;
      return;
    }

    final store = _ref.read(imageStoreProvider);
    final source = await store.read(photo.uri);
    if (source == null || source.isEmpty) {
      // The row survived but the file did not — a restored backup, or storage
      // cleared. Nothing to re-cut, and no amount of retrying will change it.
      // Empty counts as gone: zero bytes is not an image, and uploading it
      // would spend a round trip to be told so.
      state = CutoutStatus.failed;
      return;
    }

    final cutout = await _ref
        .read(aiGatewayProvider)
        .cutout(ScanImage(bytes: source));

    if (cutout == null) {
      state = CutoutStatus.failed;
      return;
    }

    final cutoutUri = await store.save(
      cutout,
      name: imageName(item.id, photo.role, cutout: true),
    );

    await repository.save(
      item.copyWith(
        photos: item.photos.withCutout(photo.uri, cutoutUri),
        updatedAt: DateTime.now(),
      ),
    );

    // The detail screen reads through a cached future; without this the user
    // watches the button succeed and the picture not change.
    _ref.invalidate(itemProvider(id));
    state = CutoutStatus.done;
  }

  void reset() => state = CutoutStatus.idle;
}

final cutoutControllerProvider =
    StateNotifierProvider<CutoutController, CutoutStatus>(CutoutController.new);
