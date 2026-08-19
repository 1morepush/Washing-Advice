/// Adding a whole wardrobe in one sitting.
///
/// The single scan flow interleaves photograph → wait → review → save per
/// garment, which is right for one and unbearable for forty. This inverts it:
/// photograph everything with nothing sent, hand the lot over, walk away.
///
/// Two decisions worth keeping in mind. The boundary between garments is the
/// user's tap rather than an inference — merging two loses a garment outright
/// and splitting one puts a phantom in the wardrobe, and the tap costs less
/// than either. And review is batched rather than skipped: forty unreviewed
/// garments is forty wrong names to find later.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/capture/image_capture_source.dart';
import 'garment_intake.dart';
import 'scan_controller.dart' show ScanShot;

/// One garment's photographs, before anything has been sent.
final class PendingGarment {
  const PendingGarment(this.shots);

  final List<ScanShot> shots;

  bool get isEmpty => shots.isEmpty;

  bool get hasCareTag => shots.any((shot) => shot.role == PhotoRole.careTag);

  /// Front, then back, then details — the same guess the single flow makes,
  /// and a wrong one costs a tap to fix.
  PhotoRole get nextRole => switch (shots.length) {
    0 => PhotoRole.front,
    1 => PhotoRole.back,
    _ => PhotoRole.detail,
  };

  PendingGarment withShot(ScanShot shot) => PendingGarment([...shots, shot]);

  PendingGarment withRole(int index, PhotoRole role) {
    if (index < 0 || index >= shots.length) return this;
    final next = [...shots];
    next[index] = next[index].withRole(role);
    return PendingGarment(next);
  }

  PendingGarment withoutLast() =>
      shots.isEmpty ? this : PendingGarment(shots.sublist(0, shots.length - 1));
}

/// What became of one garment once it was sent.
final class BulkOutcome {
  const BulkOutcome({required this.index, this.read, this.failure});

  /// Which garment in the batch this was, so a failure can be named rather
  /// than left for the user to work out.
  final int index;

  /// The reading, when it worked.
  final GarmentDraft? read;

  /// Why it did not, when it did not.
  final String? failure;

  bool get succeeded => read != null;
}

sealed class BulkState {
  const BulkState();
}

/// Photographing, with nothing sent.
final class BulkCollecting extends BulkState {
  const BulkCollecting({
    this.done = const [],
    this.current = const PendingGarment([]),
  });

  /// Garments finished with, oldest first.
  final List<PendingGarment> done;

  /// The one being photographed now.
  final PendingGarment current;

  /// Everything that would be sent, in order.
  List<PendingGarment> get all => [...done, if (!current.isEmpty) current];

  int get garmentCount => all.length;

  int get photoCount =>
      all.fold(0, (total, garment) => total + garment.shots.length);

  bool get isEmpty => all.isEmpty;
}

/// With the server, one garment at a time.
final class BulkProcessing extends BulkState {
  const BulkProcessing({required this.finished, required this.total});

  final int finished;
  final int total;
}

/// Everything came back and is waiting to be looked at.
final class BulkReviewing extends BulkState {
  const BulkReviewing({required this.outcomes, this.rejected = const {}});

  final List<BulkOutcome> outcomes;

  /// Indices the user has turned down. Kept on screen rather than vanishing:
  /// a garment that disappeared on a mistaken tap is a photo session you
  /// cannot get back.
  final Set<int> rejected;

  List<BulkOutcome> get readable => [
    for (final outcome in outcomes)
      if (outcome.succeeded) outcome,
  ];

  List<BulkOutcome> get failed => [
    for (final outcome in outcomes)
      if (!outcome.succeeded) outcome,
  ];

  /// The ones that would be saved if the user committed now.
  List<BulkOutcome> get accepted => [
    for (final outcome in readable)
      if (!rejected.contains(outcome.index)) outcome,
  ];

  BulkReviewing toggling(int index) {
    final next = {...rejected};
    if (!next.remove(index)) next.add(index);
    return BulkReviewing(outcomes: outcomes, rejected: next);
  }

  BulkReviewing replacing(int index, GarmentDraft read) => BulkReviewing(
    outcomes: [
      for (final outcome in outcomes)
        if (outcome.index == index)
          BulkOutcome(index: index, read: read)
        else
          outcome,
    ],
    rejected: rejected,
  );
}

/// Written to the wardrobe.
final class BulkSaved extends BulkState {
  const BulkSaved({required this.saved, required this.skipped});

  final int saved;
  final int skipped;
}

final class BulkFailed extends BulkState {
  const BulkFailed(this.message);

  final String message;
}

class BulkController extends StateNotifier<BulkState> {
  BulkController(this._ref) : super(const BulkCollecting());

  final Ref _ref;

  /// Adds a photograph to the garment being worked on.
  Future<void> capture({bool fromGallery = false}) async {
    if (state case final BulkCollecting collecting) {
      final List<ScanImage> images;
      try {
        images = fromGallery
            ? await _ref.read(imageCaptureProvider).pickMultiple()
            : [?await _ref.read(imageCaptureProvider).capture()];
      } on CaptureFailure catch (failure) {
        state = BulkFailed(failure.message);
        return;
      } on Exception catch (error) {
        state = BulkFailed('The camera could not be opened. $error');
        return;
      }

      // Backing out is not an error, and whatever was already taken stays.
      if (images.isEmpty) return;

      var current = collecting.current;
      for (final image in images) {
        current = current.withShot(
          ScanShot(image: image, role: current.nextRole),
        );
      }
      state = BulkCollecting(done: collecting.done, current: current);
    }
  }

  /// Says what part of the current garment one of its shots shows.
  void setRole(int index, PhotoRole role) {
    if (state case final BulkCollecting collecting) {
      state = BulkCollecting(
        done: collecting.done,
        current: collecting.current.withRole(index, role),
      );
    }
  }

  /// Finishes this garment and starts the next.
  void nextGarment() {
    if (state case final BulkCollecting collecting) {
      if (collecting.current.isEmpty) return;
      state = BulkCollecting(
        done: [...collecting.done, collecting.current],
        current: const PendingGarment([]),
      );
    }
  }

  /// Drops the last photograph, reopening the previous garment once this one
  /// is empty so an accidental "Next garment" is recoverable.
  void discardLast() {
    if (state case final BulkCollecting collecting) {
      if (!collecting.current.isEmpty) {
        state = BulkCollecting(
          done: collecting.done,
          current: collecting.current.withoutLast(),
        );
        return;
      }
      if (collecting.done.isNotEmpty) {
        state = BulkCollecting(
          done: collecting.done.sublist(0, collecting.done.length - 1),
          current: collecting.done.last,
        );
      }
    }
  }

  /// Sends every garment collected, one after another.
  ///
  /// Sequential rather than parallel: forty simultaneous uploads from a phone
  /// is a good way to have most of them time out, and an honest "9 of 40" is
  /// worth more than shaving time off a wait meant to be walked away from.
  ///
  /// One garment failing never stops the rest — a batch this size will hit a
  /// blurred photo somewhere.
  Future<void> submit() async {
    if (state case final BulkCollecting collecting) {
      final garments = collecting.all;
      if (garments.isEmpty) return;

      state = BulkProcessing(finished: 0, total: garments.length);

      final intake = _ref.read(garmentIntakeProvider);
      final outcomes = <BulkOutcome>[];

      for (final (index, garment) in garments.indexed) {
        try {
          outcomes.add(
            BulkOutcome(index: index, read: await intake.read(garment.shots)),
          );
        } on IntakeFailure catch (failure) {
          outcomes.add(BulkOutcome(index: index, failure: failure.message));
        }

        if (!mounted) return;
        state = BulkProcessing(
          finished: outcomes.length,
          total: garments.length,
        );
      }

      if (!mounted) return;
      state = BulkReviewing(outcomes: outcomes);
    }
  }

  /// Turns one garment down, or takes it back.
  void toggle(int index) {
    if (state case final BulkReviewing reviewing) {
      state = reviewing.toggling(index);
    }
  }

  /// Applies a correction to one garment in the review list.
  void revise(int index, WardrobeItem Function(WardrobeItem draft) revise) {
    if (state case final BulkReviewing reviewing) {
      final outcome = reviewing.outcomes.firstWhere(
        (candidate) => candidate.index == index,
        orElse: () => const BulkOutcome(index: -1),
      );
      if (outcome.read case final GarmentDraft read) {
        // Re-resolved because changing the fabric changes what the rules say
        // about washing it.
        state = reviewing.replacing(
          index,
          read.withDraft(
            _ref.read(garmentIntakeProvider).reresolveCare(revise(read.draft)),
          ),
        );
      }
    }
  }

  /// Writes every accepted garment to the wardrobe.
  Future<void> saveAccepted() async {
    if (state case final BulkReviewing reviewing) {
      final accepted = reviewing.accepted;
      final total = reviewing.readable.length;

      final intake = _ref.read(garmentIntakeProvider);
      var saved = 0;
      for (final outcome in accepted) {
        final read = outcome.read!;
        try {
          await intake.commit(read.draft, read.shots);
          saved++;
        } on Exception {
          // One garment failing to write must not abandon the rest.
          continue;
        }
      }

      if (!mounted) return;
      state = BulkSaved(saved: saved, skipped: total - saved);
    }
  }

  void reset() => state = const BulkCollecting();
}

final bulkControllerProvider = StateNotifierProvider<BulkController, BulkState>(
  BulkController.new,
);
