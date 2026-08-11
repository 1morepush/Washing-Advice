/// Photographing a garment again, and asking what it is a second time.
///
/// The other half of the bad-cutout problem. The mask editor fixes a cutout
/// that is nearly right; this is for the photograph that was wrong to begin
/// with — the garment held against a wall in a similar tone, with a hand and a
/// shadow in shot. No amount of masking rescues that, and re-running the
/// remover on the same pixels returns the same answer, because it is
/// deterministic. A different photograph is the only thing that changes it.
///
/// Since the picture is being taken anyway, the identification is redone too:
/// a better shot usually means a better answer, and the *first* scan was made
/// under exactly the conditions that produced the bad cutout.
///
/// What it must not do is overwrite the user. Folding the new answer in is
/// [MergeGarmentScan.mergeScan]'s job, in the core, where the provenance rules
/// already live.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';
import '../../data/images/image_store.dart';

sealed class RetakeState {
  const RetakeState();
}

final class RetakeIdle extends RetakeState {
  const RetakeIdle();
}

final class RetakeIdentifying extends RetakeState {
  const RetakeIdentifying();
}

/// The new photograph was read, and the user is confirming what changed.
final class RetakeReviewing extends RetakeState {
  const RetakeReviewing({
    required this.before,
    required this.after,
    required this.image,
  });

  /// The item as it stands, for showing what the re-scan would change.
  final WardrobeItem before;

  /// The item as it would be saved: [before] with the scan merged in.
  final WardrobeItem after;

  /// The photograph itself, attached to the item only on save — a review the
  /// user abandons must leave nothing behind.
  final ScanImage image;

  /// The fields the re-scan would actually change, as `(label, was, now)`.
  ///
  /// Shown rather than a full attribute list because the answer to "should I
  /// keep this?" is the difference, not the item. An empty list is a real and
  /// useful outcome: the new photograph agreed with the old one.
  List<(String, String, String)> get changes => [
    if (before.type.value != after.type.value)
      ('Type', before.type.value.label, after.type.value.label),
    if (before.colors.value.dominant?.name != after.colors.value.dominant?.name)
      (
        'Color',
        before.colors.value.dominant?.name ?? 'Unknown',
        after.colors.value.dominant?.name ?? 'Unknown',
      ),
    if (before.composition.value != after.composition.value)
      ('Fabric', before.composition.value.label, after.composition.value.label),
    if (before.brand?.value != after.brand?.value)
      ('Brand', before.brand?.value ?? 'Not known', after.brand?.value ?? '—'),
    if (before.pattern?.value != after.pattern?.value)
      (
        'Pattern',
        before.pattern?.value.label ?? 'Not known',
        after.pattern?.value.label ?? '—',
      ),
  ];
}

final class RetakeSaved extends RetakeState {
  const RetakeSaved(this.item);

  final WardrobeItem item;
}

final class RetakeFailed extends RetakeState {
  const RetakeFailed(this.message, {this.isRetryable = true});

  final String message;
  final bool isRetryable;
}

class RetakeController extends StateNotifier<RetakeState> {
  RetakeController(this._ref, this.itemId) : super(const RetakeIdle());

  final Ref _ref;
  final ItemId itemId;

  Future<void> captureAndIdentify() async {
    final ScanImage? image;
    try {
      image = await _ref.read(imageCaptureProvider).capture();
    } on Exception catch (error) {
      state = RetakeFailed('The camera could not be opened. $error');
      return;
    }

    // Null is a cancelled picker, not a failure. Going back to idle puts the
    // user in front of the button they meant to press.
    if (image == null) {
      state = const RetakeIdle();
      return;
    }
    await identify(image);
  }

  Future<void> identify(ScanImage image) async {
    final item = await _ref.read(wardrobeRepositoryProvider).byId(itemId);
    if (item == null) {
      state = const RetakeFailed(
        'That item is no longer in your wardrobe.',
        isRetryable: false,
      );
      return;
    }

    state = const RetakeIdentifying();

    final GarmentScanResult result;
    try {
      result = await _ref.read(aiGatewayProvider).scanGarment([image]);
    } on ScanFailure catch (failure) {
      state = RetakeFailed(failure.message, isRetryable: failure.isRetryable);
      return;
    } on ScanContractError catch (error) {
      state = RetakeFailed(
        'The server sent something this version cannot read. $error',
        isRetryable: false,
      );
      return;
    }

    final merged = item.mergeScan(result, at: DateTime.now());

    state = RetakeReviewing(
      before: item,
      // Care is re-derived through `forItem`, which carries the scanned care
      // label. Deriving it from the fabric alone would throw away the
      // manufacturer's instruction whenever a re-scan revised the composition
      // — which is exactly when the derived answer matters most.
      after: merged.copyWith(
        care: _ref.read(careResolverProvider).forItem(merged).profile,
      ),
      image: image,
    );
  }

  /// Files the new photograph and writes the merged item.
  Future<void> save() async {
    if (state case final RetakeReviewing reviewing) {
      final withPhoto = await _withRetakenPhoto(
        reviewing.after,
        reviewing.image,
      );

      await _ref.read(wardrobeRepositoryProvider).save(withPhoto);
      // The detail screen reads the item through a cached future, so without
      // this the user returns to the picture and the values they just replaced.
      _ref.invalidate(itemProvider(itemId));
      state = RetakeSaved(withPhoto);
    }
  }

  void reset() => state = const RetakeIdle();

  /// Stores the new photograph, cuts it out, and makes it the one shown.
  ///
  /// Failures are swallowed for the reason the garment scan already documents:
  /// a picture that will not store is a cosmetic loss, and refusing to save
  /// over it would discard a re-identification the user has just approved.
  Future<WardrobeItem> _withRetakenPhoto(
    WardrobeItem item,
    ScanImage image,
  ) async {
    final store = _ref.read(imageStoreProvider);
    // One instant for the file name and the record, so the cutout for this
    // photograph can be named from the photograph alone later on.
    final capturedAt = DateTime.now();

    try {
      final uri = await store.save(
        Uint8List.fromList(image.bytes),
        name: imageName(item.id, PhotoRole.front, takenAt: capturedAt),
      );

      var photo = ItemPhoto(
        uri: uri,
        role: PhotoRole.front,
        capturedAt: capturedAt,
        width: image.width,
        height: image.height,
      );

      // A cutout failing is not a reason to lose the photograph — the item
      // still gets the new picture, and the editor can mark it out by hand.
      try {
        final cutout = await _ref.read(aiGatewayProvider).cutout(image);
        if (cutout != null) {
          final cutoutUri = await store.save(
            cutout,
            name: cutoutNameFor(item.id, photo),
          );
          photo = photo.copyWith(cutoutUri: cutoutUri);
        }
      } on Exception {
        // Keep the photograph.
      }

      // `withPrimary`, not just `add`: `displayPhoto` prefers whichever photo
      // has a cutout, so without this a retake whose own cutout failed would
      // lose to the bad mask it was taken to replace, and the screen would not
      // visibly change at all.
      return item.copyWith(photos: item.photos.add(photo).withPrimary(uri));
    } on Exception {
      return item;
    }
  }
}

/// Keyed by item, so an abandoned review on one garment is not waiting on
/// another.
final retakeControllerProvider =
    StateNotifierProvider.family<RetakeController, RetakeState, ItemId>(
      RetakeController.new,
    );
