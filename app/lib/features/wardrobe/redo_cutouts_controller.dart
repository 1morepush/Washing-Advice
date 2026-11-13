/// Re-cutting every garment's picture with the current remover.
///
/// Cutouts are derived from the stored photograph, so a better remover on the
/// server means the wardrobe can be re-cut without anyone re-photographing a
/// thing. This does that for the whole wardrobe, as a job rather than a
/// button-press per garment: one at a time, with progress, cancellable, and
/// carrying on past any single failure.
///
/// What it deliberately will not do:
///
/// * **Touch a cutout somebody finished by hand.** A mask painted in the editor
///   is somebody's work, and "improving" it would throw that work away. Those
///   are told apart by the name the editor gives them (see
///   `isHandEditedCutout`); cutouts from before the marker existed read as
///   automatic.
/// * **Replace a cutout with a worse answer.** The server refuses a result that
///   is not plausible rather than returning it, so a garment it cannot separate
///   keeps the cutout it had.
/// * **Cut out a worn photograph.** Those are pictures of somebody *wearing*
///   the garment; there is no board to take away.
/// * **Hammer the server.** The cutout endpoint is rate limited, and the
///   server tells us how long to wait; this waits, as the bulk scan does.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/images/image_store.dart';
import '../../widgets/stored_image.dart';
import 'cutout_controller.dart';

/// Why a garment was left as it was.
enum RedoSkip { handEdited, worn, noPhoto }

sealed class RedoCutoutsState {
  const RedoCutoutsState();
}

class RedoIdle extends RedoCutoutsState {
  const RedoIdle();
}

class RedoRunning extends RedoCutoutsState {
  const RedoRunning({
    required this.finished,
    required this.total,
    this.waiting,
    this.cancelling = false,
  });

  /// Garments dealt with so far, including skipped and failed ones.
  final int finished;
  final int total;

  /// Set while paused for the server's rate limit.
  final Duration? waiting;
  final bool cancelling;
}

class RedoFinished extends RedoCutoutsState {
  const RedoFinished({
    required this.redone,
    required this.kept,
    required this.skippedHandEdited,
    required this.skippedWorn,
    required this.cancelled,
    required this.total,
  });

  /// Garments given a new cutout.
  final int redone;

  /// Garments whose cutout stayed as it was because the server could not make
  /// a better one, or could not be reached.
  final int kept;
  final int skippedHandEdited;
  final int skippedWorn;
  final bool cancelled;

  /// Garments that were looked at, however it ended.
  final int total;
}

class RedoCutoutsController extends StateNotifier<RedoCutoutsState> {
  RedoCutoutsController(this._ref) : super(const RedoIdle());

  final Ref _ref;

  /// The longest a single pause for a rate limit will last before the garment
  /// is given up on and the next one tried.
  static const longestRateLimitWait = Duration(minutes: 2);

  /// How many times one garment is retried after the server says to slow down.
  static const _attemptsPerGarment = 4;

  bool _cancelled = false;
  Completer<void>? _wake;

  /// Why [item] would be left alone, or null when it is a candidate.
  static RedoSkip? skipReason(WardrobeItem item) {
    final photo = item.photos.displayPhoto;
    if (photo == null) return RedoSkip.noPhoto;
    if (photo.role == PhotoRole.worn) return RedoSkip.worn;
    if (isHandEditedCutout(photo.cutoutUri)) return RedoSkip.handEdited;
    return null;
  }

  /// Asks the run to stop after the garment in flight. Whatever has been
  /// redone stays redone.
  void cancel() {
    if (state is! RedoRunning) return;
    _cancelled = true;
    final running = state as RedoRunning;
    state = RedoRunning(
      finished: running.finished,
      total: running.total,
      cancelling: true,
    );
    // A pause for a rate limit should not have to run out before cancelling.
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  void dismiss() {
    if (state is RedoFinished) state = const RedoIdle();
  }

  Future<void> run() async {
    if (state is RedoRunning) return;
    _cancelled = false;

    try {
      final repository = _ref.read(wardrobeRepositoryProvider);
      final items = await repository.query(const WardrobeQuery.owned());
      if (!mounted) return;

      var redone = 0;
      var kept = 0;
      var handEdited = 0;
      var worn = 0;
      var looked = 0;

      state = RedoRunning(finished: 0, total: items.length);

      for (final (index, listed) in items.indexed) {
        if (_cancelled || !mounted) break;

        // Re-read each one: the list was taken before the first garment's
        // network round trip, and the person may have edited a mask since.
        final item = await repository.byId(listed.id) ?? listed;
        switch (skipReason(item)) {
          case RedoSkip.handEdited:
            handEdited++;
          case RedoSkip.worn:
            worn++;
          case RedoSkip.noPhoto:
            break;
          case null:
            looked++;
            if (await _redo(item)) {
              redone++;
            } else {
              kept++;
            }
        }
        if (!mounted) return;
        state = RedoRunning(
          finished: index + 1,
          total: items.length,
          cancelling: _cancelled,
        );
      }

      if (!mounted) return;
      state = RedoFinished(
        redone: redone,
        kept: kept,
        skippedHandEdited: handEdited,
        skippedWorn: worn,
        cancelled: _cancelled,
        total: looked,
      );
    } on Exception {
      if (mounted) {
        state = const RedoFinished(
          redone: 0,
          kept: 0,
          skippedHandEdited: 0,
          skippedWorn: 0,
          cancelled: false,
          total: 0,
        );
      }
    }
  }

  /// Re-cuts one garment. True when it now has a new cutout.
  ///
  /// Every failure — an unreadable file, the server refusing, storage full — is
  /// a false rather than an exception: one garment must never stop the rest.
  Future<bool> _redo(WardrobeItem item) async {
    try {
      final photo = item.photos.displayPhoto!;
      final store = _ref.read(imageStoreProvider);
      final source = await store.read(photo.uri);
      if (source == null || source.isEmpty) return false;

      Uint8List? cutout;
      for (var attempt = 0; attempt < _attemptsPerGarment; attempt++) {
        if (_cancelled || !mounted) return false;
        final result = await _ref
            .read(aiGatewayProvider)
            .cutoutAttempt(ScanImage(bytes: source));
        cutout = result.bytes;
        final wait = result.retryAfter;
        if (cutout != null || wait == null) break;
        if (wait > longestRateLimitWait) return false;
        await _pause(wait);
      }

      // Cancelled while the request was out: drop the answer rather than
      // change a garment after the person said stop.
      if (cutout == null || _cancelled || !mounted) return false;

      final name = cutoutNameFor(item.id, photo);
      final uri = await store.save(cutout, name: name);
      await discardSupersededCutout(store, photo.cutoutUri, uri);

      // Saved against the *current* row, not the one read before the upload:
      // the garment may have been edited while the server was working.
      final repository = _ref.read(wardrobeRepositoryProvider);
      final latest = await repository.byId(item.id) ?? item;
      await repository.save(
        latest.copyWith(
          photos: latest.photos.withCutout(photo.uri, uri),
          updatedAt: DateTime.now(),
        ),
      );

      if (!mounted) return true;
      _ref.invalidate(itemProvider(item.id));
      _ref.invalidate(imageBytesProvider(uri));
      forgetDecodedImages();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<void> _pause(Duration wait) async {
    if (!mounted) return;
    final running = state;
    if (running is RedoRunning) {
      state = RedoRunning(
        finished: running.finished,
        total: running.total,
        waiting: wait,
        cancelling: _cancelled,
      );
    }
    final wake = _wake = Completer<void>();
    await Future.any([Future<void>.delayed(wait), wake.future]);
    _wake = null;
    final after = state;
    if (mounted && after is RedoRunning) {
      state = RedoRunning(
        finished: after.finished,
        total: after.total,
        cancelling: _cancelled,
      );
    }
  }
}

/// App-wide, because the job outlives the screen that started it: leaving
/// Settings should not abandon half a wardrobe.
final redoCutoutsProvider =
    StateNotifierProvider<RedoCutoutsController, RedoCutoutsState>(
      RedoCutoutsController.new,
    );
