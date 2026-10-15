/// Capture → analysing → review → saved.
///
/// The review step is the reason the rest of the system tracks confidence. A
/// scan produces beliefs of varying strength, and this screen shows them as
/// what they are: settled facts stay quiet, uncertain ones are marked, and a
/// care profile that needs a label says so before anything gets washed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../data/api/ai_gateway.dart';
import '../../widgets/back_navigation.dart';
import '../../widgets/collected_photos.dart';
import '../../widgets/state_view.dart';
import 'crop_screen.dart';
import 'scan_controller.dart';
import 'scan_review.dart';
import 'shot_tile.dart';

class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanControllerProvider);
    final controller = ref.read(scanControllerProvider.notifier);

    return LeaveScope(
      onLeave: controller.reset,
      child: Scaffold(
        appBar: AppBar(
          leading: backLeading(context, '/', onLeave: controller.reset),
          title: const Text('Scan a garment'),
        ),
        body: switch (state) {
          ScanIdle() => _Capture(controller: controller),
          ScanCollecting(:final shots) => _Collected(
            shots: shots,
            controller: controller,
          ),
          ScanAnalysing(:final imageCount) => _Analysing(
            imageCount: imageCount,
          ),
          ScanReviewing() => ScanReview(state: state, controller: controller),
          ScanSaved(:final item) => _Saved(item: item, controller: controller),
          ScanError(:final message, :final isRetryable) => FailureView(
            message: message,
            // "Try again" is offered only when trying again could work. A 422
            // means this photograph will never parse, and inviting a retry
            // would just waste the user's time.
            actionLabel: isRetryable ? 'Try again' : 'Take another photo',
            onAction: controller.reset,
          ),
        },
      ),
    );
  }
}

class _Capture extends StatelessWidget {
  const _Capture({required this.controller});

  final ScanController controller;

  @override
  Widget build(BuildContext context) => IntroView(
    icon: Icons.checkroom_outlined,
    title: 'Photograph the garment',
    message:
        'Lay it flat against a plain background. Take the back too if '
        'there is a print on it — a plain navy tee and one with a design '
        'across the back look the same from the front, to you and to the '
        'app.',
    actions: [
      FilledButton.icon(
        onPressed: controller.capture,
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Take a photo'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: () => controller.capture(fromGallery: true),
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('Choose from library'),
      ),
    ],
  );
}

/// The wait, with an explanation once it stops looking like a normal one.
///
/// A free-tier server sleeps when idle, so the first scan after a quiet spell
/// spends tens of seconds waking it before any reading happens. A spinner
/// alone makes that look like a hang and invites the user to kill the app
/// mid-request; saying so costs nothing and is true.
class _Analysing extends StatefulWidget {
  const _Analysing({required this.imageCount});

  final int imageCount;

  @override
  State<_Analysing> createState() => _AnalysingState();
}

class _AnalysingState extends State<_Analysing> {
  bool _slow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(wakingAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    // A scan that finishes quickly disposes this while the timer is pending;
    // left running it would call setState on a dead State.
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            widget.imageCount == 1
                ? 'Reading the photo…'
                : 'Reading ${widget.imageCount} photos…',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (_slow) ...[
            const SizedBox(height: 12),
            Text(
              'The server sleeps when it is not in use, so the first scan in a '
              'while takes longer while it wakes up.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    ),
  );
}

class _Saved extends StatelessWidget {
  const _Saved({required this.item, required this.controller});

  final WardrobeItem item;
  final ScanController controller;

  @override
  Widget build(BuildContext context) => SuccessView(
    title: '${item.displayName} added',
    actions: [
      FilledButton(
        onPressed: () {
          controller.reset();
          context.pushReplacement('/item/${item.id.value}');
        },
        child: const Text('View it'),
      ),
      TextButton(
        onPressed: controller.reset,
        child: const Text('Scan another'),
      ),
    ],
  );
}

class _Collected extends StatelessWidget {
  const _Collected({required this.shots, required this.controller});

  final List<ScanShot> shots;
  final ScanController controller;

  bool get hasCareTag => shots.any((shot) => shot.role == PhotoRole.careTag);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CollectedPhotos(
      heading: shots.length == 1 ? 'One photo' : '${shots.length} photos',
      body:
          'All of one garment, read together. Tap a photo to say what it '
          'shows. Nothing has been sent yet.',
      // Said here rather than discovered afterwards: somebody who does
      // not know they can include the tag keeps making a second trip.
      extra: Text(
        hasCareTag
            ? 'The care label is in here too, so it will be read in '
                  'the same pass — no need to scan it separately after.'
            : 'Photograph the care label too and mark it "Care label", '
                  'and it is read in the same pass.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: hasCareTag
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      tiles: [
        for (final (index, shot) in shots.indexed)
          ShotTile(
            shot: shot,
            onRole: (role) => controller.setRole(index, role),
            onCrop: () async {
              final cropped = await showCropper(context, shot.image);
              if (cropped != null) {
                controller.replaceShot(index, cropped);
              }
            },
          ),
      ],
      addLabel: 'Add another photo',
      onAdd: controller.capture,
      onUndo: controller.discardLast,
      primaryLabel: switch ((shots.length, hasCareTag)) {
        (1, _) => 'Identify it',
        (final n, true) => 'Identify and read the label ($n)',
        (final n, false) => 'Identify from these $n',
      },
      primaryIcon: Icons.auto_awesome_outlined,
      onPrimary: controller.scanCollected,
    );
  }
}
