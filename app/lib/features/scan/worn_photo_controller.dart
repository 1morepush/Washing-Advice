/// Adding clothes from a photo of yourself wearing them.
///
/// The fastest way to record a wardrobe that exists in a phone's camera roll
/// already: ordinary photos of outfits, no laying anything out. The server
/// finds every garment and accessory on the person and cuts each one out of the
/// photo; this layer is what turns that into garments in a wardrobe. It is the
/// lay-flat scan's review-and-save pattern with three differences worth naming.
///
/// **Photos are scanned one at a time, and a busy server is waited for.** Each
/// photo is one request against a free allowance that is metered by the minute,
/// so a camera-roll batch will meet the limit. Sending the next photo straight
/// on fails every one after it the same way; waiting the window out once costs
/// seconds. A photo that fails, or has nobody in it, says so by number and the
/// rest carry on.
///
/// **The same garment turns up in several photos.** People wear their favourite
/// jumper often, so a batch of outfit photos is full of repeats. A garment that
/// matches one found earlier in the same batch is shown, named, and not ticked,
/// exactly as one already in the wardrobe is.
///
/// **Two pictures per garment, and one shared original.** See [saveAccepted]
/// for how the photos are stored, which is the part that has to be right.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show decodeImageFromList;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';
import '../../data/capture/image_capture_source.dart';
import '../../data/images/image_store.dart';
import 'bulk_controller.dart' show BulkController;
import 'crop.dart';
import 'cutout_preview.dart';
import 'garment_intake.dart';
import 'worn_matching.dart';

/// How a garment's picture came to be.
enum WornPicture {
  /// The server cut the garment out along its outline.
  outline,

  /// The server could only crop to the garment's box: the background is still
  /// in it.
  box,

  /// The server sent no picture, so the app cropped the photo by the box.
  cropped,
}

/// A garment seen in the same batch earlier, for labelling a repeat.
final class WornRepeat {
  const WornRepeat({required this.name, required this.photoNumber});

  final String name;

  /// Which photo it was first found in, counted from one.
  final int photoNumber;
}

/// One garment found in a photo.
final class WornFind {
  const WornFind({
    required this.draft,
    required this.picture,
    required this.pictureKind,
    required this.photoIndex,
    this.cutout,
    ScanImage? preview,
    this.ownedAs,
    this.repeatOf,
  }) : preview = preview ?? cutout ?? picture;

  /// The garment as it would be saved.
  final WardrobeItem draft;

  /// The garment's front photo: an opaque crop of the worn photo by the
  /// detection's box. Always whole pixels of the photograph, never cut out.
  final ScanImage picture;

  /// The outline cutout, in the same frame as [picture] (the same box), for an
  /// [WornPicture.outline] find and null otherwise.
  final ScanImage? cutout;

  /// What a tile draws: the cutout trimmed to the garment where there is one,
  /// else [picture].
  final ScanImage preview;

  final WornPicture pictureKind;

  /// Which photo of the batch it was found in, counted from zero.
  final int photoIndex;

  /// The wardrobe item this appears to be already, if any.
  final WardrobeItem? ownedAs;

  /// An earlier find in this batch this appears to be a second sighting of.
  final WornRepeat? repeatOf;

  /// Whether adding it would very likely make a duplicate.
  bool get isDuplicate => ownedAs != null || repeatOf != null;

  WornFind withDraft(WardrobeItem revised) => WornFind(
    draft: revised,
    picture: picture,
    cutout: cutout,
    preview: preview,
    pictureKind: pictureKind,
    photoIndex: photoIndex,
    ownedAs: ownedAs,
    repeatOf: repeatOf,
  );
}

/// A photo that produced nothing, and why, so the person is told which one.
final class WornPhotoNote {
  const WornPhotoNote({required this.photoNumber, required this.message});

  /// Counted from one, as the person counts them.
  final int photoNumber;

  final String message;
}

sealed class WornPhotoState {
  const WornPhotoState();
}

final class WornIdle extends WornPhotoState {
  const WornIdle();
}

final class WornScanning extends WornPhotoState {
  const WornScanning({
    required this.current,
    required this.total,
    this.waking = false,
    this.waitingFor,
  });

  /// The photo being read, counted from one.
  final int current;
  final int total;

  /// Whether the request has run past [wakingAfter]: the server is probably
  /// asleep, and a spinner alone would read as a hang.
  final bool waking;

  /// Set while a rate limit is being waited out.
  final Duration? waitingFor;

  WornScanning asWaking() => WornScanning(
    current: current,
    total: total,
    waking: true,
    waitingFor: waitingFor,
  );
}

final class WornReviewing extends WornPhotoState {
  const WornReviewing({
    required this.finds,
    required this.photos,
    this.notes = const [],
    this.rejected = const {},
  });

  final List<WornFind> finds;

  /// Every photo of the batch, by index. Kept so the original can be stored
  /// once, for the garments that are kept, and only then.
  final List<ScanImage> photos;

  final List<WornPhotoNote> notes;

  /// Indices turned down, plus the duplicates.
  final Set<int> rejected;

  List<WornFind> get accepted => [
    for (final (index, find) in finds.indexed)
      if (!rejected.contains(index)) find,
  ];

  int get alreadyOwnedCount => finds.where((f) => f.ownedAs != null).length;
  int get repeatCount => finds.where((f) => f.repeatOf != null).length;

  WornReviewing toggling(int index) {
    final next = {...rejected};
    if (!next.remove(index)) next.add(index);
    return _with(rejected: next);
  }

  WornReviewing renaming(int index, String name) => _with(
    finds: [
      for (final (at, find) in finds.indexed)
        if (at == index)
          find.withDraft(find.draft.copyWith(name: name))
        else
          find,
    ],
  );

  WornReviewing _with({List<WornFind>? finds, Set<int>? rejected}) =>
      WornReviewing(
        finds: finds ?? this.finds,
        photos: photos,
        notes: notes,
        rejected: rejected ?? this.rejected,
      );
}

final class WornSaved extends WornPhotoState {
  const WornSaved({required this.saved, required this.skipped});

  final int saved;
  final int skipped;
}

/// The camera or library could not be opened.
final class WornFailed extends WornPhotoState {
  const WornFailed(this.message, {this.isRetryable = true});

  final String message;
  final bool isRetryable;
}

/// What reading one photo came to.
///
/// A value rather than an exception because a failed photo is an ordinary
/// outcome of a batch, and the Worn today flow reads a single photo with the
/// same code.
final class WornReading {
  const WornReading.found(WornScanResult this.result)
    : failure = null,
      isRetryable = false,
      retryAfter = null;

  const WornReading.failed(
    String this.failure, {
    this.isRetryable = true,
    this.retryAfter,
  }) : result = null;

  final WornScanResult? result;
  final String? failure;
  final bool isRetryable;

  /// How long the server asked for, when it said it was too busy.
  final Duration? retryAfter;
}

/// Reads one photo, turning every way it can fail into a [WornReading].
Future<WornReading> readWornPhoto(Ref ref, ScanImage photo) async {
  try {
    return WornReading.found(await ref.read(aiGatewayProvider).scanWorn(photo));
  } on ScanFailure catch (failure) {
    return WornReading.failed(
      failure.message,
      isRetryable: failure.isRetryable,
      retryAfter: failure.retryAfter,
    );
  } on ScanContractError catch (error) {
    return WornReading.failed(
      'The server sent something this version cannot read. $error',
      isRetryable: false,
    );
  }
}

/// What a detection's pictures are: the opaque box crop, the cutout aligned to
/// it, and the tile's framing of the cutout.
typedef WornPictures = ({
  ScanImage image,
  ScanImage? cutout,
  ScanImage preview,
  WornPicture kind,
});

/// A detection's pictures.
///
/// The front photo is always the opaque crop of the photograph by the
/// detection's box ([cropToExactBox]), so the cutout editor has real pixels to
/// restore from. An outline cutout from the server covers that same box and is
/// kept beside it. A `box` picture from the server is just that crop again, so
/// the app's own crop is used and no cutout is kept. A detection with no
/// picture from the server is cropped the same way.
Future<WornPictures> pictureFor(
  WornDetection detection,
  ScanImage photo,
  Future<ui.Image?> Function() decoded,
) async {
  final image = await cropToExactBox(
    photo: photo,
    decoded: await decoded(),
    box: detection.boundingBox,
  );
  final bytes = detection.cutout;
  final hasPicture = bytes != null && bytes.isNotEmpty;

  if (hasPicture && detection.cutoutKind == CutoutKind.outline) {
    final cutout = ScanImage(bytes: bytes, mimeType: 'image/png');
    return (
      image: image,
      cutout: cutout,
      preview: trimmedForTile(cutout),
      kind: WornPicture.outline,
    );
  }
  return (
    image: image,
    cutout: null,
    preview: image,
    // A kind this build does not know was already read as `box` by the core.
    kind: hasPicture ? WornPicture.box : WornPicture.cropped,
  );
}

class WornPhotoController extends StateNotifier<WornPhotoState> {
  WornPhotoController(this._ref) : super(const WornIdle());

  final Ref _ref;

  /// Bumped by every scan and by [reset]. Work that was started under an older
  /// number belongs to a screen that has since been left, and must not call the
  /// server again or write state.
  int _generation = 0;

  bool _stale(int generation) => !mounted || generation != _generation;

  /// The longest a batch pauses for a rate limit, shared with the bulk scan
  /// so the two agree on what "too long to wait" means.
  static const longestRateLimitWait = BulkController.longestRateLimitWait;

  /// Takes a photo or picks several, then reads them.
  Future<void> start({bool fromGallery = false}) async {
    final generation = _generation;
    final List<ScanImage> images;
    try {
      final capture = _ref.read(imageCaptureProvider);
      images = fromGallery
          ? await capture.pickMultiple()
          : [if (await capture.capture() case final ScanImage taken) taken];
    } on CaptureFailure catch (failure) {
      if (_stale(generation)) return;
      state = WornFailed(failure.message, isRetryable: failure.isRetryable);
      return;
    } on Exception catch (error) {
      if (_stale(generation)) return;
      state = WornFailed('The camera could not be opened. $error');
      return;
    }

    if (_stale(generation)) return;
    // Backing out is not a failure.
    if (images.isEmpty) return;
    await scan(images);
  }

  /// Reads [photos] one after another.
  ///
  /// Leaving the screen ([reset]) ends it: the generation is checked after every
  /// await and before every state write, so no further request is sent and
  /// nothing is written once the person has gone.
  Future<void> scan(List<ScanImage> photos) async {
    final generation = ++_generation;
    final readings = <WornReading>[];

    for (final (index, photo) in photos.indexed) {
      state = WornScanning(current: index + 1, total: photos.length);

      var reading = await _read(photo, generation);
      if (_stale(generation)) return;
      if (reading.retryAfter case final Duration wait
          when wait <= longestRateLimitWait) {
        state = WornScanning(
          current: index + 1,
          total: photos.length,
          waitingFor: wait,
        );
        await Future<void>.delayed(wait);
        if (_stale(generation)) return;
        state = WornScanning(current: index + 1, total: photos.length);
        reading = await _read(photo, generation);
        if (_stale(generation)) return;
      }
      readings.add(reading);
    }

    final reviewing = await _review(photos, readings, generation);
    if (reviewing == null || _stale(generation)) return;
    state = reviewing;
  }

  /// Opens the review on detections already in hand, with no server call.
  ///
  /// How Worn today hands over a garment that matched nothing: the photo was
  /// scanned there, and scanning it again would spend a second request to be
  /// told the same thing.
  Future<void> reviewDetections(
    ScanImage photo,
    List<WornDetection> detections,
  ) async {
    final generation = ++_generation;
    final reviewing = await _review(
      [photo],
      [WornReading.found(WornScanResult(detections: detections))],
      generation,
    );
    if (reviewing == null || _stale(generation)) return;
    state = reviewing;
  }

  /// One request, with the "server is asleep" line armed alongside it.
  Future<WornReading> _read(ScanImage photo, int generation) async {
    if (_stale(generation)) return const WornReading.failed('Cancelled');
    final timer = Timer(wakingAfter, () {
      if (!_stale(generation) && state is WornScanning) {
        state = (state as WornScanning).asWaking();
      }
    });
    try {
      return await readWornPhoto(_ref, photo);
    } finally {
      timer.cancel();
    }
  }

  /// Null when the screen was left part way through.
  Future<WornReviewing?> _review(
    List<ScanImage> photos,
    List<WornReading> readings,
    int generation,
  ) async {
    final intake = _ref.read(garmentIntakeProvider);
    // The whole wardrobe: a garment being in the basket is not evidence that
    // it is not the one in the photo.
    final wardrobe = await _ref
        .read(wardrobeRepositoryProvider)
        .query(const WardrobeQuery());
    if (_stale(generation)) return null;
    final matcher = _ref.read(itemMatcherProvider);
    final resolver = _ref.read(matchResolverProvider);
    final byId = {for (final item in wardrobe) item.id: item};

    final finds = <WornFind>[];
    final notes = <WornPhotoNote>[];
    // New garments found so far, which later photos are matched against too.
    final batch = <ItemId, ({String name, int photoNumber})>{};
    final batchItems = <WardrobeItem>[];

    for (final (index, reading) in readings.indexed) {
      final number = index + 1;

      if (reading.failure case final String problem) {
        notes.add(WornPhotoNote(photoNumber: number, message: problem));
        continue;
      }
      final detections = reading.result!.detections;
      if (detections.isEmpty) {
        notes.add(
          WornPhotoNote(
            photoNumber: number,
            message:
                'No clothes were found. Try a photo where more of the outfit '
                'shows.',
          ),
        );
        continue;
      }

      final photo = photos[index];
      // Decoded at most once, and only if a crop is needed.
      ui.Image? decoded;
      var decodeTried = false;
      Future<ui.Image?> decode() async {
        if (!decodeTried) {
          decodeTried = true;
          try {
            decoded = await decodeImageFromList(
              Uint8List.fromList(photo.bytes),
            );
          } on Exception {
            decoded = null;
          }
        }
        return decoded;
      }

      final decisions = resolveAgainst(
        scans: [for (final d in detections) d.scan],
        pool: [...wardrobe, ...batchItems],
        matcher: matcher,
        resolver: resolver,
      );

      final fresh = <WardrobeItem>[];
      for (final (at, detection) in detections.indexed) {
        final draft = intake.draftFrom(detection.scan);
        final picture = await pictureFor(detection, photo, decode);
        if (_stale(generation)) {
          decoded?.dispose();
          return null;
        }

        WardrobeItem? owned;
        WornRepeat? repeat;
        if (decisions[at] case RecognizedItem(:final itemId)) {
          owned = byId[itemId];
          if (batch[itemId] case final seen?) {
            repeat = WornRepeat(name: seen.name, photoNumber: seen.photoNumber);
          }
        }

        finds.add(
          WornFind(
            draft: draft,
            picture: picture.image,
            cutout: picture.cutout,
            preview: picture.preview,
            pictureKind: picture.kind,
            photoIndex: index,
            ownedAs: owned,
            repeatOf: repeat,
          ),
        );
        if (owned == null && repeat == null) fresh.add(draft);
      }
      decoded?.dispose();

      // Added after the photo, not during it: two garments in one frame are two
      // garments, however alike. Only a later photo can be a second sighting.
      for (final draft in fresh) {
        batch[draft.id] = (name: draft.displayName, photoNumber: number);
        batchItems.add(draft);
      }
    }

    return WornReviewing(
      finds: finds,
      photos: photos,
      notes: notes,
      // Garments that are probably already known start unticked, shown rather
      // than hidden so it is clear the app found them rather than missed them.
      rejected: {
        for (final (index, find) in finds.indexed)
          if (find.isDuplicate) index,
      },
    );
  }

  void toggle(int index) {
    if (state case final WornReviewing reviewing) {
      state = reviewing.toggling(index);
    }
  }

  void rename(int index, String name) {
    if (state case final WornReviewing reviewing) {
      state = reviewing.renaming(index, name);
    }
  }

  /// Writes every ticked garment to the wardrobe.
  ///
  /// ## How the photos are stored
  ///
  /// Each garment ends up with two photos, and which field holds what is
  /// decided by what the rest of the app does with a photo, not by tidiness.
  ///
  /// **The front photo** is the garment's own picture:
  ///
  /// * `uri` holds an **opaque crop of the worn photo by the detection's box**
  ///   ([cropToExactBox]). Not the cutout: the cutout editor's "add back" brush
  ///   restores real pixels from `uri`, and a `uri` that was itself the cutout
  ///   would have nothing behind its transparent pixels to restore. It is a
  ///   box, not the whole photograph, so "Clean up" and the editor work on the
  ///   garment's frame rather than somebody's face and the room.
  /// * `cutoutUri` holds the server's outline cutout, for an `outline` find. The
  ///   server cuts it to the same box, pixel for pixel (see the contract), so
  ///   the editor's mask lines up with `uri`. It is a separate file, which is
  ///   also what the editor wants: it writes its result under the cutout's name
  ///   and deletes the file the cutout used to be, so with two files the box
  ///   crop stays put and rubbing out too much can always be undone. A `box`
  ///   find has no cutout; it is the box crop alone, which is exactly the shape
  ///   of a photo whose cutout is missing.
  /// * `isPrimary` is true, so the worn photo is never what a tile shows.
  ///
  /// **The worn photo** is the original, role [PhotoRole.worn], never primary
  /// and never given a cutout. The photo viewer pages through photos by `uri`,
  /// so it shows the whole photograph there. It is stored once per photo and
  /// every garment found in it references the same URI, so six garments from
  /// one picture cost one file. That makes it shared, which is why deleting a
  /// garment leaves a file another garment still points at (see
  /// `urisHeldByOthers`).
  ///
  /// Retaking a photo adds a new primary front photo and leaves these alone,
  /// so the worn photo survives it.
  ///
  /// A garment whose row cannot be written has the files stored for it deleted,
  /// the shared original only when no saved garment holds it.
  Future<void> saveAccepted() async {
    if (state case final WornReviewing reviewing) {
      final accepted = reviewing.accepted;
      final intake = _ref.read(garmentIntakeProvider);
      final store = _ref.read(imageStoreProvider);
      final batch = DateTime.now();

      // Original URIs by photo index, stored the first time a kept garment
      // needs one. A photo whose garments were all turned down is never stored.
      final originals = <int, String?>{};
      // Photo indices whose original a saved garment points at.
      final originalKept = <int>{};
      Future<String?> originalOf(int photoIndex) async {
        if (originals.containsKey(photoIndex)) return originals[photoIndex];
        final photo = reviewing.photos[photoIndex];
        try {
          return originals[photoIndex] = await store.save(
            Uint8List.fromList(photo.bytes),
            name: wornPhotoName(batch, photoIndex + 1),
          );
        } on Exception {
          // A missing worn photo is cosmetic; the garment is still worth it.
          return originals[photoIndex] = null;
        }
      }

      Future<void> forget(String? uri) async {
        if (uri == null) return;
        try {
          await store.delete(uri);
        } on Exception {
          // Nothing more can be done about a file that will not go.
        }
      }

      var saved = 0;
      for (final (n, find) in accepted.indexed) {
        final stored = <String>[];
        int? usedOriginal;
        try {
          final photos = <ItemPhoto>[];
          final id = find.draft.id;
          final capturedAt = batch.add(Duration(microseconds: n));

          try {
            var front = ItemPhoto(
              uri: await store.save(
                Uint8List.fromList(find.picture.bytes),
                name: imageName(id, PhotoRole.front, takenAt: capturedAt),
              ),
              role: PhotoRole.front,
              capturedAt: capturedAt,
              width: find.picture.width,
              height: find.picture.height,
              isPrimary: true,
            );
            stored.add(front.uri);
            if (find.cutout case final ScanImage cutout) {
              front = front.copyWith(
                cutoutUri: await store.save(
                  Uint8List.fromList(cutout.bytes),
                  name: cutoutNameFor(id, front),
                ),
              );
              stored.add(front.cutoutUri!);
            }
            photos.add(front);
          } on Exception {
            // No picture is a colour swatch, not a lost garment.
          }

          if (await originalOf(find.photoIndex) case final String uri) {
            usedOriginal = find.photoIndex;
            final original = reviewing.photos[find.photoIndex];
            photos.add(
              ItemPhoto(
                uri: uri,
                role: PhotoRole.worn,
                capturedAt: batch,
                width: original.width,
                height: original.height,
              ),
            );
          }

          await intake.saveItem(find.draft.copyWith(photos: PhotoSet(photos)));
          if (usedOriginal != null) originalKept.add(usedOriginal);
          saved++;
        } on Exception {
          // The row may have been written before the failure (the log entry
          // after it is what threw). A garment that is in the wardrobe keeps
          // its files; deleting them would leave it pointing at nothing.
          if (await _isInWardrobe(find.draft.id)) {
            if (usedOriginal != null) originalKept.add(usedOriginal);
            saved++;
            continue;
          }
          // One garment failing to write must not abandon the rest, and must
          // not leave its files behind.
          for (final uri in stored) {
            await forget(uri);
          }
          if (usedOriginal != null && !originalKept.contains(usedOriginal)) {
            await forget(originals.remove(usedOriginal));
          }
          continue;
        }
      }

      if (!mounted) return;
      state = WornSaved(saved: saved, skipped: accepted.length - saved);
    }
  }

  Future<bool> _isInWardrobe(ItemId id) async {
    try {
      return await _ref.read(wardrobeRepositoryProvider).byId(id) != null;
    } on Exception {
      return false;
    }
  }

  /// Back to a fresh start, and anything still running is abandoned.
  void reset() {
    _generation++;
    if (mounted) state = const WornIdle();
  }
}

final wornPhotoControllerProvider =
    StateNotifierProvider<WornPhotoController, WornPhotoState>(
      WornPhotoController.new,
    );
