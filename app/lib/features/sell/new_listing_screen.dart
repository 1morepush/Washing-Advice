/// Starting a listing from photographs, or by writing it by hand.
///
/// A checklist of shots, a button that is ready once the cover is taken, and
/// then the server reads what it can see and the draft opens in the editor. The
/// photographs are held in memory until that button is pressed: nothing is stored
/// or sent while somebody is still turning the garment over, as the scan flows
/// already promise.
///
/// **The server being unable to read them is not the end of the listing.** It
/// sleeps, it is busy, it is out of reach, and a seller with a garment in one
/// hand should not be stopped by that. So the photographs are stored *before*
/// they are sent, and when the reading fails the person is offered the two things
/// that follow: try again with the same photographs, or write it themselves, with
/// the same photographs, from a blank draft. Either way the photographs taken are
/// never taken again.
///
/// The screen replaces itself with the editor, so Back from the editor is Sell
/// and not a camera pointing at nothing.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart' show ScanFailure;
import '../../data/capture/image_capture_source.dart' show CaptureFailure;
import '../../widgets/back_navigation.dart';
import '../../widgets/rinse_kit.dart';
import '../scan/scan_parts.dart' show ScanActionBar;
import 'listing_controller.dart';
import 'start/listing_wait.dart';
import 'start/photo_checklist.dart';
import 'start/photo_set.dart';

/// Where the person is: taking photographs, waiting on the server, or told it
/// could not read them.
enum _Phase { collecting, writing, failed }

class NewListingScreen extends ConsumerStatefulWidget {
  const NewListingScreen({super.key});

  @override
  ConsumerState<NewListingScreen> createState() => _NewListingScreenState();
}

class _NewListingScreenState extends ConsumerState<NewListingScreen> {
  ListingPhotoSet _photos = const ListingPhotoSet.empty();
  _Phase _phase = _Phase.collecting;

  /// Whether the camera is open. A second request while it is would be refused
  /// by the platform, so the buttons wait.
  bool _camera = false;

  /// Whether a local save is under way, so a second tap cannot make a second
  /// listing.
  bool _saving = false;

  /// What the last attempt failed with, while [_phase] is [_Phase.failed].
  ({String message, bool retryable})? _failure;

  /// The listing being made and the photographs stored for it, kept from the
  /// first attempt so that a retry makes the same listing from the same files
  /// and not a second set.
  ListingId? _id;
  List<ListingPhoto>? _stored;

  /// Whether the stored photographs now belong to a listing, or have been let go.
  bool _handedOver = false;

  ListingController get _controller => ref.read(listingControllerProvider);

  // --- Photographs --------------------------------------------------------

  /// Takes a photograph for [shot], keeping what is already there if the person
  /// backs out of the camera.
  Future<void> _take(ListingShot shot) async {
    if (_camera || _phase != _Phase.collecting) return;
    setState(() => _camera = true);

    try {
      final image = await ref.read(imageCaptureProvider).capture();
      if (!mounted || image == null) return;

      final next = _photos.taking(shot, image);
      if (next == null) {
        _say('Depop takes $depopPhotoLimit photos. Remove one to add another.');
      } else {
        setState(() => _photos = next);
      }
    } on CaptureFailure catch (failure) {
      // A message and the checklist as it was: the photographs already taken
      // are not lost to a camera that would not open.
      if (mounted) _say(failure.message);
    } on Exception catch (error) {
      if (mounted) _say('The camera could not be opened. $error');
    } finally {
      if (mounted) setState(() => _camera = false);
    }
  }

  /// Adds photographs from the library, as many as there is room for.
  Future<void> _addMore() async {
    if (_camera || _phase != _Phase.collecting) return;
    setState(() => _camera = true);

    try {
      final images = await ref.read(imageCaptureProvider).pickMultiple();
      if (!mounted || images.isEmpty) return;

      final added = _photos.takingAll(ListingShot.other, images);
      setState(() => _photos = added.photos);
      if (added.left > 0) {
        _say(
          'Depop takes $depopPhotoLimit photos, so '
          '${added.left == 1 ? 'one was' : '${added.left} were'} left out.',
        );
      }
    } on CaptureFailure catch (failure) {
      if (mounted) _say(failure.message);
    } on Exception catch (error) {
      if (mounted) _say('The photos could not be opened. $error');
    } finally {
      if (mounted) setState(() => _camera = false);
    }
  }

  void _remove(ListingShot shot, int index) =>
      setState(() => _photos = _photos.without(shot, index: index));

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  // --- Making the listing -------------------------------------------------

  /// Stores the photographs, has the server read them, and opens the draft.
  Future<void> _write() async {
    if (_phase == _Phase.writing || !_photos.hasCover) return;
    final shots = _photos.shots;
    setState(() {
      _phase = _Phase.writing;
      _failure = null;
    });

    try {
      final id = _id ??= _controller.newListingId();
      // Once. Storing again on a retry would keep a second copy of each
      // photograph under a new name, and the first set would belong to nobody.
      final stored = _stored ??= await _controller.storePhotos(id, shots);

      final listing = await _controller.createFromPhotos(id, stored, shots);
      _open(listing);
    } on ScanFailure catch (failure) {
      _fail(failure.message, retryable: failure.isRetryable);
    } on Exception catch (error) {
      // Not the server: the phone could not keep the draft. Trying again can
      // work, and so can writing it by hand, which is the same kind of save.
      _fail(
        'The listing could not be saved on this phone. $error',
        retryable: true,
      );
    }
  }

  /// A blank draft with the photographs, for when the server cannot read them.
  Future<void> _writeItMyself() async {
    final id = _id;
    final stored = _stored;
    if (_saving || id == null || stored == null) return;
    setState(() => _saving = true);

    try {
      _open(await _controller.createEmpty(id, stored));
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _say('The listing could not be saved on this phone. $error');
    }
  }

  void _fail(String message, {required bool retryable}) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _failure = (message: message, retryable: retryable);
    });
  }

  /// Replaces this screen with the draft.
  ///
  /// Replaces and does not push, so that Back from the editor lands on Sell and
  /// not on a checklist whose photographs have just been made into a listing.
  void _open(Listing listing) {
    // The listing exists whether or not anyone is still here to see it, and the
    // photographs are now its own.
    _handedOver = true;
    if (!mounted) return;
    context.pushReplacement('/listing/${listing.id.value}');
  }

  /// Backing out of the failure screen, which gives the photographs up.
  ///
  /// Stored but never made into a listing, they would stay on the phone with
  /// nothing pointing at them. Deleted through the controller's own way of
  /// deleting a listing's photographs, which knows not to touch a garment's.
  /// Not while the server is still reading them: that listing is about to exist,
  /// and will want them.
  void _leave() {
    final id = _id;
    final stored = _stored;
    if (_phase != _Phase.failed ||
        _handedOver ||
        id == null ||
        stored == null) {
      return;
    }
    _handedOver = true;
    unawaited(
      _controller.delete(
        Listing.empty(id: id, now: DateTime.now().toUtc(), photos: stored),
      ),
    );
  }

  // --- Screen -------------------------------------------------------------

  @override
  Widget build(BuildContext context) => LeaveScope(
    onLeave: _leave,
    child: Scaffold(
      appBar: AppBar(
        leading: backLeading(context, '/sell', onLeave: _leave),
        title: const AppBarTitle('New listing'),
      ),
      body: switch (_phase) {
        _Phase.collecting => PhotoChecklist(
          photos: _photos,
          busy: _camera,
          onTake: _take,
          onRemove: _remove,
          onAddMore: _addMore,
        ),
        _Phase.writing => const ListingWait(
          title: 'Writing the listing…',
          detail:
              'Reading your photos for the brand, the size and anything a '
              'buyer should know.',
        ),
        _Phase.failed => _Failed(
          message: _failure?.message ?? '',
          retryable: _failure?.retryable ?? false,
          busy: _saving,
          onTryAgain: _write,
          onWriteItMyself: _writeItMyself,
        ),
      },
      // The button is the Scaffold's bottom bar and not the last thing in the
      // body, so that a message about a photograph floats above it instead of
      // over it: a note that covered the one button on the screen for four
      // seconds would be a note about something else.
      bottomNavigationBar: _phase == _Phase.collecting
          ? _WriteBar(
              hasCover: _photos.hasCover,
              enabled: _photos.hasCover && !_camera,
              onWrite: _write,
            )
          : null,
    ),
  );
}

/// The button that writes the listing, and why it is not ready when it is not.
class _WriteBar extends StatelessWidget {
  const _WriteBar({
    required this.hasCover,
    required this.enabled,
    required this.onWrite,
  });

  final bool hasCover;
  final bool enabled;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ScanActionBar(
      children: [
        // Said beside the button that is not ready, because a disabled button
        // with no reason is a button people tap again.
        if (!hasCover)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Take the cover photo to write the listing.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: enabled ? onWrite : null,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Write the listing'),
          ),
        ),
      ],
    );
  }
}

/// The server could not read the photographs, and what to do next.
///
/// The two buttons are stacked and full width, not set side by side: with
/// words of different lengths they wrap to different heights on a narrow phone.
class _Failed extends StatelessWidget {
  const _Failed({
    required this.message,
    required this.retryable,
    required this.busy,
    required this.onTryAgain,
    required this.onWriteItMyself,
  });

  final String message;
  final bool retryable;
  final bool busy;
  final VoidCallback onTryAgain;
  final VoidCallback onWriteItMyself;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconBadge(Icons.error_outline, size: 80, error: true),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Your photos are kept, so you can still write the listing '
              'yourself.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            // Offered only where trying again could work: a photograph the
            // server will never read is not helped by sending it again.
            if (retryable) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : onTryAgain,
                  child: const Text('Try again'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: retryable
                  ? FilledButton.tonal(
                      onPressed: busy ? null : onWriteItMyself,
                      child: const Text('Write it myself'),
                    )
                  : FilledButton(
                      onPressed: busy ? null : onWriteItMyself,
                      child: const Text('Write it myself'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
