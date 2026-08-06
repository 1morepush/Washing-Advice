/// The scan flow's state machine.
///
/// Modelled as a sealed union rather than a bag of nullable fields and an
/// `isLoading` boolean. With a union the impossible states — "loading, and also
/// holding an error, and also showing a result" — cannot be constructed, and
/// the screen's `switch` is exhaustive, so adding a step later is a compile
/// error at every place that has to handle it rather than a blank screen.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';
import '../../data/images/image_store.dart';

sealed class ScanState {
  const ScanState();
}

/// Nothing captured yet.
final class ScanIdle extends ScanState {
  const ScanIdle();
}

/// Images are with the server.
final class ScanAnalysing extends ScanState {
  const ScanAnalysing(this.imageCount);

  final int imageCount;
}

/// The server answered and the user is checking the reading.
final class ScanReviewing extends ScanState {
  const ScanReviewing({
    required this.draft,
    required this.result,
    required this.images,
    this.diagnostics,
  });

  /// The photographs the reading came from.
  ///
  /// Held so they can be stored when the user commits. Uploading them again
  /// for the cutout would be a second transfer of bytes already in hand.
  final List<ScanImage> images;

  /// The item as it would be saved, already run through the care resolver.
  final WardrobeItem draft;

  /// What the vision layer actually returned, kept so the review screen can
  /// show the reading itself rather than only its consequences.
  final GarmentScanResult result;

  final ScanDiagnostics? diagnostics;

  ScanReviewing withDraft(WardrobeItem draft) => ScanReviewing(
    draft: draft,
    result: result,
    images: images,
    diagnostics: diagnostics,
  );
}

/// The item was written to the wardrobe.
final class ScanSaved extends ScanState {
  const ScanSaved(this.item);

  final WardrobeItem item;
}

final class ScanError extends ScanState {
  const ScanError(this.message, {this.isRetryable = true});

  final String message;
  final bool isRetryable;
}

class ScanController extends StateNotifier<ScanState> {
  ScanController(this._ref) : super(const ScanIdle());

  final Ref _ref;

  /// Captures a photo and scans it.
  Future<void> captureAndScan({bool fromGallery = false}) async {
    final capture = _ref.read(imageCaptureProvider);

    final List<ScanImage> images;
    try {
      images = fromGallery
          ? await capture.pickMultiple()
          : [?await capture.capture()];
    } on Exception catch (error) {
      state = ScanError('The camera could not be opened. $error');
      return;
    }

    if (images.isEmpty) {
      // The user backed out. Not an error, and showing one would be rude.
      state = const ScanIdle();
      return;
    }

    await scanImages(images);
  }

  /// Scans images that are already in hand.
  ///
  /// Separate from capture so tests and the screenshot run can supply bytes
  /// directly — the whole reason capture is behind an interface.
  Future<void> scanImages(List<ScanImage> images) async {
    state = ScanAnalysing(images.length);

    final gateway = _ref.read(aiGatewayProvider);
    try {
      final result = await gateway.scanGarment(images);
      state = ScanReviewing(
        draft: _draftFrom(result),
        result: result,
        images: images,
        diagnostics: gateway.lastDiagnostics,
      );
    } on ScanFailure catch (failure) {
      state = ScanError(failure.message, isRetryable: failure.isRetryable);
    } on ScanContractError catch (error) {
      // Deliberately distinct wording. This is the app and the server
      // disagreeing about the contract, and no amount of retrying fixes it.
      state = ScanError(
        'The server sent something this version cannot read. $error',
        isRetryable: false,
      );
    }
  }

  /// Applies a user correction on the review screen.
  void reviseDraft(WardrobeItem Function(WardrobeItem draft) revise) {
    if (state case final ScanReviewing reviewing) {
      final revised = revise(reviewing.draft);
      // Re-resolve: changing the fabric changes what the rules say about it,
      // and a review screen still showing care derived from the old fibre
      // would be quietly wrong in exactly the way that damages clothes.
      state = reviewing.withDraft(_reresolveCare(revised));
    }
  }

  /// Writes the reviewed item to the wardrobe.
  Future<void> save() async {
    if (state case final ScanReviewing reviewing) {
      final ids = _ref.read(idGeneratorProvider);
      final item = await _withPhotos(reviewing.draft, reviewing.images);

      await _ref.read(wardrobeRepositoryProvider).save(item);
      // The item row and the event are two records of the same happening. The
      // row is what the wardrobe screen reads; the event is what makes the
      // history replayable, and without it "added on" would be a field nobody
      // could verify.
      await _ref
          .read(eventLogProvider)
          .append(
            ItemAdded(
              id: EventId(ids.next()),
              itemId: item.id,
              occurredAt: item.addedAt,
              recordedAt: DateTime.now(),
            ),
          );
      state = ScanSaved(item);
    }
  }

  void reset() => state = const ScanIdle();

  /// Stores the captured photographs and asks the server for a cutout.
  ///
  /// Failures here are swallowed on purpose. A missing picture is a cosmetic
  /// loss; refusing to save the garment over it would throw away a scan the
  /// user has already reviewed and approved, which is a far worse outcome than
  /// a row that falls back to its colour swatch.
  Future<WardrobeItem> _withPhotos(
    WardrobeItem item,
    List<ScanImage> images,
  ) async {
    if (images.isEmpty) return item;

    final store = _ref.read(imageStoreProvider);
    final gateway = _ref.read(aiGatewayProvider);
    final now = DateTime.now();

    var photos = item.photos;

    for (final (index, image) in images.indexed) {
      // The first shot is the front; anything after it is the back. More than
      // two would need the user to say, and the capture flow does not ask.
      final role = index == 0 ? PhotoRole.front : PhotoRole.back;

      try {
        final uri = await store.save(
          Uint8List.fromList(image.bytes),
          name: imageName(item.id, role),
        );

        String? cutoutUri;
        if (role == PhotoRole.front) {
          final cutout = await gateway.cutout(image);
          if (cutout != null) {
            cutoutUri = await store.save(
              cutout,
              name: imageName(item.id, role, cutout: true),
            );
          }
        }

        photos = photos.add(
          ItemPhoto(
            uri: uri,
            cutoutUri: cutoutUri,
            role: role,
            capturedAt: now,
            width: image.width,
            height: image.height,
          ),
        );
      } on Exception {
        // Storage full, permission revoked, disk error. Keep going: the other
        // photographs and the item itself are still worth saving.
        continue;
      }
    }

    return item.copyWith(photos: photos);
  }

  /// Turns a scan result into a saveable item.
  ///
  /// The care profile is *derived*, not carried over: the vision layer reports
  /// what it saw, and the core's rule table decides what that means for washing
  /// it. Letting a model state care directly would put laundry judgement in the
  /// provider, which is exactly what the rule table exists to prevent.
  WardrobeItem _draftFrom(GarmentScanResult result) {
    final now = DateTime.now();
    final draft = WardrobeItem(
      id: ItemId(_ref.read(idGeneratorProvider).next()),
      name: result.suggestedName ?? result.type.value.label,
      type: result.type,
      composition:
          result.composition ??
          Confident(
            FabricComposition(const {}),
            confidence: 0,
            source: Provenance.fallbackDefault,
          ),
      colors: result.colors,
      brand: result.brand,
      pattern: result.pattern,
      sleeveLength: result.sleeveLength?.value,
      fit: result.fit?.value,
      styleCut: result.styleCut?.value,
      seasons: result.seasons,
      distinguishingText: result.distinguishingText,
      care: const CareProfile.unknown(),
      addedAt: now,
      updatedAt: now,
    );
    return _reresolveCare(draft);
  }

  /// Recomputes the care profile from the item's own facts.
  ///
  /// No label constraint is passed: a garment scan reads the *garment*, not its
  /// care tag. That is a separate scan with a separate provenance, and pretending
  /// a photo of a hoodie told us its wash temperature would put a guess where the
  /// user expects a manufacturer's instruction.
  WardrobeItem _reresolveCare(WardrobeItem item) => item.copyWith(
    care: _ref
        .read(careResolverProvider)
        .resolve(
          facts: item.facts,
          // Passing this is what makes a rule fired on a guessed fabric
          // report itself as a guess, which in turn is what raises the
          // "scan the label" prompt on exactly the items that need it.
          factsConfidence: item.factsConfidence,
        )
        .profile,
  );
}

final scanControllerProvider = StateNotifierProvider<ScanController, ScanState>(
  ScanController.new,
);
