/// Saying what you wore by showing the app a mirror photo.
///
/// Worn today is a grid you tap through. This is the same answer reached
/// another way: one photo of you in the clothes, the same scan the add-from-a-
/// photo flow uses, and the detections matched against the wardrobe with the
/// matcher every other flow uses.
///
/// The rule that matters is what is *not* done silently. A confident match is
/// ticked, because the person is about to confirm the list and unticking a
/// wrong one is one tap. An uncertain match is shown and left unticked: a wear
/// recorded against the wrong garment skews its wash count and cost per wear,
/// and nothing downstream can tell. A detection that matches nothing is not
/// dropped either: it is a garment the wardrobe does not have, and the person
/// is offered it as one to add.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/capture/image_capture_source.dart';
import '../history/wear_recorder.dart';
import '../scan/cutout_preview.dart';
import '../scan/worn_matching.dart';
import '../scan/worn_photo_controller.dart';
import 'laundry_controller.dart';

enum Certainty {
  /// Matched confidently: ticked.
  sure,

  /// Plausibly this garment, worth a look: shown, not ticked.
  unsure,

  /// Nothing in the wardrobe: offered as one to add.
  none,
}

/// One garment seen in the photo.
final class Sighting {
  const Sighting({
    required this.detection,
    required this.certainty,
    this.item,
    this.picture,
  });

  final WornDetection detection;
  final Certainty certainty;

  /// The wardrobe garment it matched, or nearly did.
  final WardrobeItem? item;

  /// Its picture from the photo, for a garment with no wardrobe item to show.
  final ScanImage? picture;
}

enum WornPhase { idle, scanning, result, failed, done }

final class WornTodayPhotoState {
  const WornTodayPhotoState({
    this.phase = WornPhase.idle,
    this.sightings = const [],
    this.selected = const {},
    this.saved = 0,
    this.message,
    this.isRetryable = true,
    this.waking = false,
    this.saving = false,
  });

  final WornPhase phase;
  final List<Sighting> sightings;

  /// Indices into [sightings] that will be recorded.
  final Set<int> selected;
  final int saved;
  final String? message;
  final bool isRetryable;
  final bool waking;
  final bool saving;

  WornTodayPhotoState copy({
    WornPhase? phase,
    Set<int>? selected,
    bool? waking,
    bool? saving,
  }) => WornTodayPhotoState(
    phase: phase ?? this.phase,
    sightings: sightings,
    selected: selected ?? this.selected,
    saved: saved,
    message: message,
    isRetryable: isRetryable,
    waking: waking ?? this.waking,
    saving: saving ?? this.saving,
  );

  List<Sighting> get matched => [
    for (final s in sightings)
      if (s.certainty != Certainty.none) s,
  ];
  List<Sighting> get unmatched => [
    for (final s in sightings)
      if (s.certainty == Certainty.none) s,
  ];
}

class WornTodayPhotoController extends StateNotifier<WornTodayPhotoState> {
  WornTodayPhotoController(this._ref) : super(const WornTodayPhotoState());

  final Ref _ref;

  /// The photo that was read, kept to hand to the add flow.
  ScanImage? _photo;

  /// What was found in it, kept to match again after something is added.
  List<WornDetection> _detections = const [];

  /// Bumped by every scan and by [reset]. Work started under an older number
  /// belongs to a screen that has been left: no further request, no write.
  int _generation = 0;

  bool _stale(int generation) => !mounted || generation != _generation;

  /// Takes or picks one photo and reads it.
  Future<void> start({bool fromGallery = false}) async {
    final generation = _generation;
    final ScanImage? image;
    try {
      final capture = _ref.read(imageCaptureProvider);
      image = fromGallery
          ? (await capture.pickMultiple()).firstOrNull
          : await capture.capture();
    } on CaptureFailure catch (failure) {
      if (_stale(generation)) return;
      state = WornTodayPhotoState(
        phase: WornPhase.failed,
        message: failure.message,
        isRetryable: failure.isRetryable,
      );
      return;
    } on Exception catch (error) {
      if (_stale(generation)) return;
      state = WornTodayPhotoState(
        phase: WornPhase.failed,
        message: 'The camera could not be opened. $error',
      );
      return;
    }
    if (_stale(generation)) return;
    // Backing out is not a failure.
    if (image == null) return;
    await scan(image);
  }

  Future<void> scan(ScanImage photo) async {
    final generation = ++_generation;
    _photo = photo;
    _detections = const [];
    state = const WornTodayPhotoState(phase: WornPhase.scanning);

    final timer = Timer(wakingAfter, () {
      if (!_stale(generation) && state.phase == WornPhase.scanning) {
        state = state.copy(waking: true);
      }
    });
    final WornReading reading;
    try {
      reading = await readWornPhoto(_ref, photo);
    } finally {
      timer.cancel();
    }
    if (_stale(generation)) return;

    if (reading.failure case final String problem) {
      state = WornTodayPhotoState(
        phase: WornPhase.failed,
        message: problem,
        isRetryable: reading.isRetryable,
      );
      return;
    }
    final detections = reading.result!.detections;
    if (detections.isEmpty) {
      state = const WornTodayPhotoState(
        phase: WornPhase.failed,
        message:
            'No clothes were found in that photo. Try one where more of '
            'the outfit shows.',
      );
      return;
    }

    _detections = detections;
    final sightings = await _match(detections);
    if (_stale(generation)) return;
    state = WornTodayPhotoState(
      phase: WornPhase.result,
      sightings: sightings,
      selected: {
        for (final (i, s) in sightings.indexed)
          if (s.certainty == Certainty.sure) i,
      },
    );
  }

  Future<List<Sighting>> _match(List<WornDetection> detections) async {
    // Everything owned, not only what is clean: a garment in the basket can
    // still be the one in the mirror, and calling it "not in your wardrobe"
    // would offer a duplicate.
    final owned = await _ref
        .read(wardrobeRepositoryProvider)
        .query(const WardrobeQuery.owned());
    final byId = {for (final item in owned) item.id: item};
    final decisions = resolveAgainst(
      scans: [for (final d in detections) d.scan],
      pool: owned,
      matcher: _ref.read(itemMatcherProvider),
      resolver: _ref.read(matchResolverProvider),
    );

    final sightings = <Sighting>[];
    for (final (i, detection) in detections.indexed) {
      switch (decisions[i]) {
        case RecognizedItem(:final itemId):
          sightings.add(
            Sighting(
              detection: detection,
              certainty: Certainty.sure,
              item: byId[itemId],
            ),
          );
        case NeedsConfirmation(:final best):
          sightings.add(
            Sighting(
              detection: detection,
              certainty: Certainty.unsure,
              item: byId[best.itemId],
            ),
          );
        case UnrecognizedItem():
          // The server's picture where there is one. A detection without one
          // is shown as words only here; the add flow crops it from the photo
          // if the person takes it up.
          final cutout = detection.cutout;
          sightings.add(
            Sighting(
              detection: detection,
              certainty: Certainty.none,
              picture: cutout == null || cutout.isEmpty
                  ? null
                  : _tile(cutout, detection.cutoutKind),
            ),
          );
      }
    }
    return sightings;
  }

  /// An outline cutout covers its whole box, so it is trimmed to the garment
  /// for the tile; a box crop is shown as it is.
  static ScanImage _tile(List<int> bytes, CutoutKind? kind) {
    final picture = ScanImage(bytes: bytes, mimeType: 'image/png');
    return kind == CutoutKind.outline ? trimmedForTile(picture) : picture;
  }

  /// Matches what was found again, after the person has added a garment.
  ///
  /// The garment they added is in the wardrobe now, so it matches its own
  /// detection and moves up out of "Not in your wardrobe", ticked to be logged
  /// like any confident match. What was ticked or unticked by hand stays so.
  Future<void> rematch() async {
    final generation = _generation;
    if (state.phase != WornPhase.result || _detections.isEmpty) return;
    final before = state;
    final sightings = await _match(_detections);
    if (_stale(generation) || state.phase != WornPhase.result) return;

    final selected = {...before.selected};
    for (final (i, now) in sightings.indexed) {
      final was = before.sightings[i];
      if (was.certainty == Certainty.none && now.certainty == Certainty.sure) {
        selected.add(i);
      }
    }
    state = WornTodayPhotoState(
      phase: WornPhase.result,
      sightings: sightings,
      selected: selected,
    );
  }

  void toggle(int index) {
    if (state.phase != WornPhase.result || state.saving) return;
    final selected = {...state.selected};
    if (!selected.remove(index)) selected.add(index);
    state = state.copy(selected: selected);
  }

  /// Records the ticked garments as worn and puts them in the basket.
  ///
  /// The same two steps as Worn today's own Log button, for the same reason:
  /// the wear is the record, and moving the garment keeps the wardrobe from
  /// claiming it is available. One occasion, so the co-wear graph sees an
  /// outfit.
  Future<void> confirm() async {
    final ids = <ItemId>{
      for (final i in state.selected)
        if (state.sightings[i].item case final WardrobeItem item) item.id,
    }.toList();
    if (state.saving || ids.isEmpty) return;

    final generation = _generation;
    state = state.copy(saving: true);
    try {
      await _ref.read(wearRecorderProvider).recordOutfit(ids);
      await _ref
          .read(laundryControllerProvider)
          .move(ids, LifecycleState.inLaundry);
    } on Exception {
      if (_stale(generation)) return;
      // Back to the list with the ticks as they were, so it can be tried again.
      state = WornTodayPhotoState(
        phase: WornPhase.result,
        sightings: state.sightings,
        selected: state.selected,
        message:
            'Could not record what you wore. Nothing was logged; try again.',
      );
      return;
    }
    if (_stale(generation)) return;
    state = WornTodayPhotoState(phase: WornPhase.done, saved: ids.length);
  }

  /// Hands a garment the wardrobe does not have to the add flow, preselected.
  ///
  /// Not re-scanned: the photo was read here already.
  Future<void> addToWardrobe(Sighting sighting) async {
    final photo = _photo;
    if (photo == null) return;
    await _ref.read(wornPhotoControllerProvider.notifier).reviewDetections(
      photo,
      [sighting.detection],
    );
  }

  void reset() {
    _generation++;
    _photo = null;
    _detections = const [];
    if (mounted) state = const WornTodayPhotoState();
  }
}

final wornTodayPhotoControllerProvider =
    StateNotifierProvider.autoDispose<
      WornTodayPhotoController,
      WornTodayPhotoState
    >(WornTodayPhotoController.new);
