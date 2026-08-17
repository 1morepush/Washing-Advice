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
import '../../data/capture/image_capture_source.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';
import '../../data/images/image_store.dart';
import 'care_label_merge.dart';

sealed class ScanState {
  const ScanState();
}

/// Nothing captured yet.
final class ScanIdle extends ScanState {
  const ScanIdle();
}

/// One photograph, with the part of the garment it shows.
///
/// The role is carried from the moment the shot is taken rather than derived
/// from its position later. Position was doing that job and could only ever
/// express "first is the front, everything else is the back" — which is wrong
/// the moment somebody photographs a back print and a sleeve logo, and wrong
/// again when they photograph the back first.
final class ScanShot {
  const ScanShot({required this.image, required this.role});

  final ScanImage image;
  final PhotoRole role;

  ScanShot withRole(PhotoRole role) => ScanShot(image: image, role: role);
}

/// Photographs taken so far, before any of them has been sent.
///
/// A garment is not always identifiable from one side. A plain navy tee and a
/// navy tee with a large print across the back are different garments to their
/// owner and identical from the front, so the scan has to be able to see both
/// before it decides what this is.
final class ScanCollecting extends ScanState {
  const ScanCollecting(this.shots);

  final List<ScanShot> shots;

  /// What the next photograph is most likely to be.
  ///
  /// Front, then back, then details. A guess the user can override, which is
  /// the right trade for something they would otherwise have to set every
  /// single time.
  PhotoRole get nextRole => switch (shots.length) {
    0 => PhotoRole.front,
    1 => PhotoRole.back,
    _ => PhotoRole.detail,
  };

  /// Whether a care label is among these shots.
  ///
  /// Drives the one thing the screen has to say differently: that pressing the
  /// button will read the tag as well, rather than leaving it for a second
  /// trip through a different scanner.
  bool get hasCareTag => shots.any((shot) => shot.role == PhotoRole.careTag);
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
    required this.shots,
    this.label,
    this.labelUnread = false,
    this.diagnostics,
  });

  /// The care label read from the same batch, if one was photographed.
  ///
  /// Null when no tag was among the shots — the ordinary case — and also when
  /// one was and could not be read, which [labelUnread] tells apart.
  final CareTagScanResult? label;

  /// Whether a label was photographed and came back with nothing usable.
  ///
  /// Worth its own flag rather than being inferred from a null [label]. The
  /// user took that photograph on purpose, and silently saving a garment with
  /// rule-derived care would leave them believing the manufacturer's
  /// instructions were in hand when they are not.
  final bool labelUnread;

  /// The photographs the reading came from, each with what it shows.
  ///
  /// Held so they can be stored when the user commits. Uploading them again
  /// for the cutout would be a second transfer of bytes already in hand.
  final List<ScanShot> shots;

  /// The item as it would be saved, already run through the care resolver.
  final WardrobeItem draft;

  /// What the vision layer actually returned, kept so the review screen can
  /// show the reading itself rather than only its consequences.
  final GarmentScanResult result;

  final ScanDiagnostics? diagnostics;

  ScanReviewing withDraft(WardrobeItem draft) => ScanReviewing(
    draft: draft,
    result: result,
    shots: shots,
    label: label,
    labelUnread: labelUnread,
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

  /// Takes one photograph and holds it, without scanning yet.
  ///
  /// Deliberately does not scan. Somebody photographing a shirt with a print
  /// across the back has to be able to turn it around first, and a flow that
  /// sent the first shot immediately would identify a plain navy tee.
  Future<void> capture({bool fromGallery = false}) async {
    final existing = switch (state) {
      ScanCollecting(:final shots) => shots,
      _ => const <ScanShot>[],
    };
    final List<ScanImage> images;
    try {
      images = fromGallery
          ? await _ref.read(imageCaptureProvider).pickMultiple()
          : [?await _ref.read(imageCaptureProvider).capture()];
    } on CaptureFailure catch (failure) {
      // The capture layer already decided whether trying again could work, so
      // this passes that through rather than assuming every camera problem is
      // temporary — a denied permission is not.
      state = ScanError(failure.message, isRetryable: failure.isRetryable);
      return;
    } on Exception catch (error) {
      state = ScanError('The camera could not be opened. $error');
      return;
    }

    if (images.isEmpty) {
      // The user backed out. Not an error, and showing one would be rude —
      // and whatever was already taken is kept, because losing the front
      // because the back was cancelled would be its own small disaster.
      state = existing.isEmpty ? const ScanIdle() : ScanCollecting(existing);
      return;
    }

    final added = <ScanShot>[];
    for (final (index, image) in images.indexed) {
      added.add(
        ScanShot(
          image: image,
          role: switch (existing.length + index) {
            0 => PhotoRole.front,
            1 => PhotoRole.back,
            _ => PhotoRole.detail,
          },
        ),
      );
    }

    state = ScanCollecting([...existing, ...added]);
  }

  /// Says what part of the garment one of the collected shots shows.
  void setRole(int index, PhotoRole role) {
    if (state case ScanCollecting(
      :final shots,
    ) when index >= 0 && index < shots.length) {
      final next = [...shots];
      next[index] = next[index].withRole(role);
      state = ScanCollecting(next);
    }
  }

  /// Drops the last photograph taken, for a shot that came out unusable.
  void discardLast() {
    if (state case ScanCollecting(:final shots) when shots.isNotEmpty) {
      final kept = shots.sublist(0, shots.length - 1);
      state = kept.isEmpty ? const ScanIdle() : ScanCollecting(kept);
    }
  }

  /// Sends everything collected so far as one garment.
  Future<void> scanCollected() async {
    if (state case ScanCollecting(:final shots)) {
      await scanShots(shots);
    }
  }

  /// Scans images that are already in hand.
  ///
  /// Separate from capture so tests and the screenshot run can supply bytes
  /// directly — the whole reason capture is behind an interface.
  Future<void> scanImages(List<ScanImage> images) async => scanShots([
    for (final (index, image) in images.indexed)
      ScanShot(
        image: image,
        role: switch (index) {
          0 => PhotoRole.front,
          1 => PhotoRole.back,
          _ => PhotoRole.detail,
        },
      ),
  ]);

  /// Sends photographs that are already in hand, each with what it shows.
  ///
  /// Shots marked as the care label are split off and read by the label
  /// scanner rather than being handed to the garment one. They are different
  /// questions — what is this, and what does the manufacturer say about washing
  /// it — and a photograph of a tag tells the garment reader almost nothing.
  ///
  /// Doing both here is what saves the second trip. Somebody adding a jumper
  /// used to photograph it, wait, save it, open it again, and start a separate
  /// scanner for the label sewn into the same garment they were already
  /// holding. Now the tag is one more shot in the same handful.
  Future<void> scanShots(List<ScanShot> shots) async {
    final garment = [
      for (final shot in shots)
        if (shot.role != PhotoRole.careTag) shot.image,
    ];
    final label = [
      for (final shot in shots)
        if (shot.role == PhotoRole.careTag) shot.image,
    ];

    if (garment.isEmpty) {
      // A label on its own identifies nothing. Worth saying plainly rather
      // than sending it to the garment reader and relaying whatever it makes
      // of a photograph of a tag.
      state = const ScanError(
        'There is no photo of the garment itself here — only its label. Add a '
        'photo of the garment so it can be identified.',
        isRetryable: false,
      );
      return;
    }

    state = ScanAnalysing(shots.length);

    final gateway = _ref.read(aiGatewayProvider);
    try {
      final result = await gateway.scanGarment(garment);
      var draft = _draftFrom(result);

      CareTagScanResult? reading;
      if (label.isNotEmpty) {
        // After the garment rather than alongside it, and deliberately: the
        // label is laid over a draft that has to exist first, and running them
        // together would save a few seconds in exchange for having to hold a
        // half-built item while one of two calls is still out.
        reading = await _readLabel(label);
        if (reading != null) {
          draft = withCareLabel(
            draft,
            reading,
            resolver: _ref.read(careResolverProvider),
          ).item;
        }
      }

      state = ScanReviewing(
        draft: draft,
        result: result,
        shots: shots,
        label: reading,
        labelUnread: label.isNotEmpty && reading == null,
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

  /// Reads the label shots, or returns null if they said nothing usable.
  ///
  /// Failure here never fails the scan. The garment has already been
  /// identified and is worth saving; an unreadable tag costs the user the care
  /// instructions, which they can scan again from the item screen at their
  /// leisure. Throwing away a good garment reading because the label photo was
  /// blurred would be the tail wagging the dog — so this reports by returning
  /// nothing and the review screen says so.
  Future<CareTagScanResult?> _readLabel(List<ScanImage> images) async {
    try {
      final reading = await _ref.read(aiGatewayProvider).scanCareTag(images);
      // A label stating nothing must not be attached. It would replace a
      // rule-derived profile with an empty one recorded at `tagScan`
      // provenance, making the app more confident about care it learned
      // nothing new about.
      return reading.instructions.statesNothing ? null : reading;
    } on ScanFailure {
      return null;
    } on ScanContractError {
      return null;
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
      final item = await _withPhotos(reviewing.draft, reviewing.shots);

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
    List<ScanShot> shots,
  ) async {
    if (shots.isEmpty) return item;

    final store = _ref.read(imageStoreProvider);
    final gateway = _ref.read(aiGatewayProvider);
    final now = DateTime.now();

    var photos = item.photos;
    // The front is cut out, and only once. Two photographs both marked front —
    // which the user is free to do — would otherwise mean two uploads and a
    // second file overwriting the first.
    var cutoutDone = false;

    for (final (index, shot) in shots.indexed) {
      final role = shot.role;
      // Distinct per photograph, because the stored name is derived from it.
      // Without this two details, or two backs, resolve to one name: the
      // second overwrites the first and the set ends up with two records
      // pointing at one file, carrying the wrong dimensions for one of them.
      final capturedAt = now.add(Duration(microseconds: index));

      try {
        final uri = await store.save(
          Uint8List.fromList(shot.image.bytes),
          name: imageName(item.id, role, takenAt: capturedAt),
        );

        String? cutoutUri;
        if (role == PhotoRole.front && !cutoutDone) {
          cutoutDone = true;
          final cutout = await gateway.cutout(shot.image);
          if (cutout != null) {
            cutoutUri = await store.save(
              cutout,
              name: imageName(item.id, role, takenAt: capturedAt, cutout: true),
            );
          }
        }

        photos = photos.add(
          ItemPhoto(
            uri: uri,
            cutoutUri: cutoutUri,
            role: role,
            capturedAt: capturedAt,
            width: shot.image.width,
            height: shot.image.height,
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
