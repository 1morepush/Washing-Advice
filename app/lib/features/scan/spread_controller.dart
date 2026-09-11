/// Laying several garments out and photographing them together.
///
/// The fastest way to record a wardrobe, and the one that needs no new model
/// work: the pile scanner already looks at one photograph and comes back with
/// several garments, each identified and each with a box saying where in the
/// frame it sits. That capability has been in the app since the laundry
/// planner shipped; it has just never been pointed at the wardrobe.
///
/// So this is mostly plumbing, and the plumbing has two parts worth naming.
///
/// **Each garment gets its own picture.** A detection carries a bounding box,
/// so the photograph is cut into one image per garment before anything is
/// saved. Without that, six garments would share one picture of a heap, and a
/// wardrobe grid where every tile is the same photograph of six things is
/// worse than no picture at all.
///
/// **Garments already owned are found and left alone.** The same matcher the
/// pile planner uses runs here, because the likeliest second use of this
/// screen is somebody photographing a drawer they have already done half of.
/// A recognised garment is shown, named, and *not* ticked — rather than
/// hidden, which would look like the app had missed it.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Rect;
import 'package:flutter/widgets.dart' show decodeImageFromList;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';
import '../../data/capture/image_capture_source.dart';
import 'crop.dart';
import 'garment_intake.dart';
import 'scan_controller.dart' show ScanShot;

/// One garment found in the photograph.
final class SpreadFind {
  const SpreadFind({
    required this.draft,
    required this.image,
    required this.ownedAs,
  });

  /// The garment as it would be saved.
  final WardrobeItem draft;

  /// This garment alone, cut out of the photograph.
  final ScanImage image;

  /// The wardrobe item this appears to be already, if any.
  ///
  /// Set only where the match was strong enough to act on. The ambiguous
  /// middle — three identical black t-shirts — is deliberately left null and
  /// offered as new, because adding a duplicate costs a tap to delete and
  /// silently skipping a real garment costs a garment.
  final WardrobeItem? ownedAs;

  bool get isAlreadyOwned => ownedAs != null;
}

sealed class SpreadState {
  const SpreadState();
}

final class SpreadIdle extends SpreadState {
  const SpreadIdle();
}

final class SpreadAnalysing extends SpreadState {
  const SpreadAnalysing();
}

final class SpreadReviewing extends SpreadState {
  const SpreadReviewing({required this.finds, this.rejected = const {}});

  final List<SpreadFind> finds;

  /// Indices the user has turned down, plus the ones already owned.
  final Set<int> rejected;

  List<SpreadFind> get accepted => [
    for (final (index, find) in finds.indexed)
      if (!rejected.contains(index)) find,
  ];

  int get alreadyOwnedCount => finds.where((f) => f.isAlreadyOwned).length;

  SpreadReviewing toggling(int index) {
    final next = {...rejected};
    if (!next.remove(index)) next.add(index);
    return SpreadReviewing(finds: finds, rejected: next);
  }

  SpreadReviewing renaming(int index, String name) => SpreadReviewing(
    finds: [
      for (final (at, find) in finds.indexed)
        if (at == index)
          SpreadFind(
            draft: find.draft.copyWith(name: name),
            image: find.image,
            ownedAs: find.ownedAs,
          )
        else
          find,
    ],
    rejected: rejected,
  );
}

final class SpreadSaved extends SpreadState {
  const SpreadSaved({required this.saved, required this.skipped});

  final int saved;
  final int skipped;
}

final class SpreadFailed extends SpreadState {
  const SpreadFailed(this.message, {this.isRetryable = true});

  final String message;
  final bool isRetryable;
}

class SpreadController extends StateNotifier<SpreadState> {
  SpreadController(this._ref) : super(const SpreadIdle());

  final Ref _ref;

  /// Photographs a spread of garments and reads it.
  Future<void> capture({bool fromGallery = false}) async {
    final ScanImage? image;
    try {
      image = fromGallery
          ? (await _ref.read(imageCaptureProvider).pickMultiple()).firstOrNull
          : await _ref.read(imageCaptureProvider).capture();
    } on CaptureFailure catch (failure) {
      state = SpreadFailed(failure.message, isRetryable: failure.isRetryable);
      return;
    } on Exception catch (error) {
      state = SpreadFailed('The camera could not be opened. $error');
      return;
    }

    // Backing out is not a failure.
    if (image == null) return;
    await readFrom(image);
  }

  /// Reads a photograph that has already been taken.
  Future<void> readFrom(ScanImage image) async {
    state = const SpreadAnalysing();

    final PileScanResult reading;
    try {
      reading = await _ref.read(aiGatewayProvider).scanPile(image);
    } on ScanFailure catch (failure) {
      state = SpreadFailed(failure.message, isRetryable: failure.isRetryable);
      return;
    } on ScanContractError catch (error) {
      state = SpreadFailed(
        'The server sent something this version cannot read. $error',
        isRetryable: false,
      );
      return;
    }

    if (reading.items.isEmpty) {
      // The two cases read very differently to somebody holding a phone, and
      // the advice differs: one is "try again", the other is "move them
      // apart".
      state = SpreadFailed(
        reading.partiallyObscuredCount > 0
            ? 'Clothes were visible but none could be made out. Spread them '
                  'apart so each one is separate and try again.'
            : 'No clothes were found in that photo.',
      );
      return;
    }

    if (!mounted) return;
    state = await _review(image, reading);
  }

  Future<SpreadReviewing> _review(
    ScanImage photo,
    PileScanResult reading,
  ) async {
    final intake = _ref.read(garmentIntakeProvider);
    // The whole wardrobe rather than a filtered slice: a garment being in the
    // basket is not evidence that it is not the one on the bed.
    final wardrobe = await _ref
        .read(wardrobeRepositoryProvider)
        .query(const WardrobeQuery());
    final matcher = _ref.read(itemMatcherProvider);
    final resolver = _ref.read(matchResolverProvider);
    final byId = {for (final item in wardrobe) item.id: item};

    final decoded = await _decode(photo);
    final finds = <SpreadFind>[];
    final claimed = <ItemId>{};

    for (final detected in reading.items) {
      // Items already claimed by an earlier detection are out of the running
      // for the next. Two identical socks in one frame must not both resolve
      // to the same wardrobe row, which would record one and skip the other.
      final available = [
        for (final item in wardrobe)
          if (!claimed.contains(item.id)) item,
      ];
      final decision = resolver.resolve(
        matcher.rank(_fingerprintOf(detected.scan), available),
      );

      final owned = switch (decision) {
        RecognizedItem(:final itemId) => byId[itemId],
        NeedsConfirmation() || UnrecognizedItem() => null,
      };
      if (owned != null) claimed.add(owned.id);

      finds.add(
        SpreadFind(
          draft: intake.draftFrom(detected.scan),
          image: await _cutOut(photo, decoded, detected.boundingBox),
          ownedAs: owned,
        ),
      );
    }

    decoded?.dispose();

    return SpreadReviewing(
      finds: finds,
      // Already-owned garments start unticked. Shown rather than hidden, so
      // somebody photographing a drawer they half-did last week can see that
      // the app found them rather than missed them.
      rejected: {
        for (final (index, find) in finds.indexed)
          if (find.isAlreadyOwned) index,
      },
    );
  }

  /// Decodes the photograph once, for every crop to share.
  ///
  /// Null when the bytes cannot be decoded, which is survivable: the readings
  /// are already in hand, and a garment saved with the whole photograph is a
  /// worse picture rather than a lost garment.
  Future<ui.Image?> _decode(ScanImage photo) async {
    try {
      return await decodeImageFromList(Uint8List.fromList(photo.bytes));
    } on Exception {
      return null;
    }
  }

  /// Cuts one garment out of the photograph.
  Future<ScanImage> _cutOut(
    ScanImage photo,
    ui.Image? decoded,
    BoundingBox box,
  ) async {
    if (decoded == null) return photo;

    // The box is normalised, so it survives the image being resized between
    // here and the model. Multiplying it back up is the only place this flow
    // touches pixels.
    final width = decoded.width.toDouble();
    final height = decoded.height.toDouble();
    final crop = Rect.fromLTWH(
      box.left * width,
      box.top * height,
      box.width * width,
      box.height * height,
    );

    try {
      return await cropScanImage(image: photo, decoded: decoded, crop: crop);
    } on Exception {
      // A crop that fails is a worse picture, not a lost garment.
      return photo;
    }
  }

  GarmentFingerprint _fingerprintOf(GarmentScanResult scan) =>
      GarmentFingerprint(
        type: scan.type.value,
        colors: scan.colors.value,
        composition: scan.composition?.value ?? FabricComposition.unknown(),
        brand: scan.brand?.value,
        pattern: scan.pattern?.value,
        distinguishingText: scan.distinguishingText,
      );

  /// Turns one garment down, or takes it back.
  void toggle(int index) {
    if (state case final SpreadReviewing reviewing) {
      state = reviewing.toggling(index);
    }
  }

  /// Fixes a name before saving.
  void rename(int index, String name) {
    if (state case final SpreadReviewing reviewing) {
      state = reviewing.renaming(index, name);
    }
  }

  /// Writes every ticked garment to the wardrobe.
  Future<void> saveAccepted() async {
    if (state case final SpreadReviewing reviewing) {
      final accepted = reviewing.accepted;
      final intake = _ref.read(garmentIntakeProvider);

      var saved = 0;
      for (final find in accepted) {
        try {
          await intake.commit(find.draft, [
            ScanShot(image: find.image, role: PhotoRole.front),
          ]);
          saved++;
        } on Exception {
          // One garment failing to write must not abandon the rest.
          continue;
        }
      }

      if (!mounted) return;
      state = SpreadSaved(saved: saved, skipped: accepted.length - saved);
    }
  }

  void reset() => state = const SpreadIdle();
}

final spreadControllerProvider =
    StateNotifierProvider<SpreadController, SpreadState>(SpreadController.new);
