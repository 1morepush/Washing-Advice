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
    this.ownedAs,
    this.repeatOf,
  });

  /// The garment as it would be saved.
  final WardrobeItem draft;

  /// This garment's own picture: a cutout where the server made one.
  final ScanImage picture;

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

/// A detection's own picture, or a crop of the photo when it has none.
///
/// An outline or box picture from the server is used as sent. A detection with
/// no picture still has its box, so the photo is cropped by it: a worse
/// picture, never a lost garment.
Future<({ScanImage image, WornPicture kind})> pictureFor(
  WornDetection detection,
  ScanImage photo,
  Future<ui.Image?> Function() decoded,
) async {
  final bytes = detection.cutout;
  if (bytes != null && bytes.isNotEmpty) {
    return (
      image: ScanImage(bytes: bytes, mimeType: 'image/png'),
      // A kind this build does not know was already read as `box` by the core.
      kind: detection.cutoutKind == CutoutKind.outline
          ? WornPicture.outline
          : WornPicture.box,
    );
  }
  return (
    image: await cropToBox(
      photo: photo,
      decoded: await decoded(),
      box: detection.boundingBox,
    ),
    kind: WornPicture.cropped,
  );
}

class WornPhotoController extends StateNotifier<WornPhotoState> {
  WornPhotoController(this._ref) : super(const WornIdle());

  final Ref _ref;

  /// The longest a batch pauses for a rate limit, shared with the bulk scan
  /// so the two agree on what "too long to wait" means.
  static const longestRateLimitWait = BulkController.longestRateLimitWait;

  /// Takes a photo or picks several, then reads them.
  Future<void> start({bool fromGallery = false}) async {
    final List<ScanImage> images;
    try {
      final capture = _ref.read(imageCaptureProvider);
      images = fromGallery
          ? await capture.pickMultiple()
          : [if (await capture.capture() case final ScanImage taken) taken];
    } on CaptureFailure catch (failure) {
      state = WornFailed(failure.message, isRetryable: failure.isRetryable);
      return;
    } on Exception catch (error) {
      state = WornFailed('The camera could not be opened. $error');
      return;
    }

    // Backing out is not a failure.
    if (images.isEmpty) return;
    await scan(images);
  }

  /// Reads [photos] one after another.
  Future<void> scan(List<ScanImage> photos) async {
    final readings = <WornReading>[];

    for (final (index, photo) in photos.indexed) {
      state = WornScanning(current: index + 1, total: photos.length);

      var reading = await _read(photo);
      if (reading.retryAfter case final Duration wait
          when wait <= longestRateLimitWait) {
        state = WornScanning(
          current: index + 1,
          total: photos.length,
          waitingFor: wait,
        );
        await Future<void>.delayed(wait);
        if (!mounted) return;
        state = WornScanning(current: index + 1, total: photos.length);
        reading = await _read(photo);
      }
      if (!mounted) return;
      readings.add(reading);
    }

    final reviewing = await _review(photos, readings);
    if (!mounted) return;
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
    final reviewing = await _review(
      [photo],
      [WornReading.found(WornScanResult(detections: detections))],
    );
    if (!mounted) return;
    state = reviewing;
  }

  /// One request, with the "server is asleep" line armed alongside it.
  Future<WornReading> _read(ScanImage photo) async {
    final timer = Timer(wakingAfter, () {
      if (mounted && state is WornScanning) {
        state = (state as WornScanning).asWaking();
      }
    });
    try {
      return await readWornPhoto(_ref, photo);
    } finally {
      timer.cancel();
    }
  }

  Future<WornReviewing> _review(
    List<ScanImage> photos,
    List<WornReading> readings,
  ) async {
    final intake = _ref.read(garmentIntakeProvider);
    // The whole wardrobe: a garment being in the basket is not evidence that
    // it is not the one in the photo.
    final wardrobe = await _ref
        .read(wardrobeRepositoryProvider)
        .query(const WardrobeQuery());
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
  /// * `uri` holds the cutout's pixels. Not the worn photo: the cutout editor
  ///   and "Clean up" treat `uri` as the picture to cut *from*, and cutting a
  ///   garment out of a whole photo of a person would hand them somebody's
  ///   face. The cutout is the only picture of this garment alone there is.
  /// * `cutoutUri` holds the same cutout again, under its own name, for an
  ///   `outline` cutout. The copy is deliberate. The editor writes its result
  ///   to the cutout's name and then deletes the file the cutout used to be,
  ///   so if both fields named one file, tidying would overwrite the picture it
  ///   was tidying *from* and rubbing out too much could never be undone. With
  ///   two files the original stays put and the editor behaves as it does for
  ///   any other garment. A `box` picture is not stored as a cutout at all: it
  ///   has its background in it, so it sits in `uri` alone, which is exactly
  ///   the shape of a photo whose cutout is missing, and "Clean up" then offers
  ///   to remove the background, as the review screen promised it could.
  /// * `isPrimary` is true. [PhotoSet.displayPhoto] would pick this photo
  ///   anyway when it has a cutout, but not for a `box` picture, and the worn
  ///   photo must never be what a tile shows.
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
  Future<void> saveAccepted() async {
    if (state case final WornReviewing reviewing) {
      final accepted = reviewing.accepted;
      final intake = _ref.read(garmentIntakeProvider);
      final store = _ref.read(imageStoreProvider);
      final batch = DateTime.now();

      // Original URIs by photo index, stored the first time a kept garment
      // needs one. A photo whose garments were all turned down is never stored.
      final originals = <int, String?>{};
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

      var saved = 0;
      for (final (n, find) in accepted.indexed) {
        try {
          final photos = <ItemPhoto>[];
          final id = find.draft.id;
          final capturedAt = batch.add(Duration(microseconds: n));
          final bytes = Uint8List.fromList(find.picture.bytes);

          try {
            var front = ItemPhoto(
              uri: await store.save(
                bytes,
                name: imageName(id, PhotoRole.front, takenAt: capturedAt),
              ),
              role: PhotoRole.front,
              capturedAt: capturedAt,
              width: find.picture.width,
              height: find.picture.height,
              isPrimary: true,
            );
            if (find.pictureKind == WornPicture.outline) {
              front = front.copyWith(
                cutoutUri: await store.save(
                  bytes,
                  name: cutoutNameFor(id, front),
                ),
              );
            }
            photos.add(front);
          } on Exception {
            // No picture is a colour swatch, not a lost garment.
          }

          if (await originalOf(find.photoIndex) case final String uri) {
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
          saved++;
        } on Exception {
          // One garment failing to write must not abandon the rest.
          continue;
        }
      }

      if (!mounted) return;
      state = WornSaved(saved: saved, skipped: accepted.length - saved);
    }
  }

  void reset() => state = const WornIdle();
}

final wornPhotoControllerProvider =
    StateNotifierProvider<WornPhotoController, WornPhotoState>(
      WornPhotoController.new,
    );
