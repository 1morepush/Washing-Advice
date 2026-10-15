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

import '../../core/theme.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';
import '../../widgets/confidence_chip.dart';
import 'crop_screen.dart';
import 'scan_controller.dart';
import '../../widgets/back_navigation.dart';
import '../../widgets/state_view.dart';
import '../../widgets/notice.dart';
import '../../widgets/collected_photos.dart';
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
          ScanReviewing() => _Review(state: state, controller: controller),
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

class _Review extends StatelessWidget {
  const _Review({required this.state, required this.controller});

  final ScanReviewing state;
  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    final draft = state.draft;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Bounded, because this is a heading and a heading that grows
              // without limit is not a heading. The server now trims a
              // runaway name, but this screen is the one that showed a
              // four-hundred-character one filling the phone and pushing
              // every other reading off the bottom — the place a name is
              // *drawn* should not depend on something upstream having
              // behaved.
              Text(
                draft.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              _Reading(label: 'Type', belief: draft.type, show: (t) => t.label),
              if (draft.brand case final Confident<String> brand)
                _Reading(label: 'Brand', belief: brand, show: (b) => b),
              _Reading(
                label: 'Fabric',
                belief: draft.composition,
                show: (c) => c.isEmpty ? 'Not readable' : c.label,
              ),
              _Reading(
                label: 'Color',
                belief: draft.colors,
                show: (c) => c.isEmpty
                    ? 'Not readable'
                    : c.colors.map((x) => x.name ?? x.hex).join(', '),
              ),
              if (draft.pattern case final Confident<Pattern> pattern)
                _Reading(
                  label: 'Pattern',
                  belief: pattern,
                  show: (p) => p.label,
                ),
              const SizedBox(height: 8),
              // Before the care card, because it changes how that card should
              // be read.
              if (state.label != null || state.labelUnread)
                _LabelOutcome(read: state.label != null),
              _CareSummary(item: draft),
              if (state.diagnostics case final ScanDiagnostics diagnostics)
                _Diagnostics(diagnostics: diagnostics),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: controller.reset,
                    child: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () async {
                      await controller.save();
                    },
                    child: const Text('Add to wardrobe'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One thing the scan believes, with how strongly.
class _Reading<T extends Object> extends StatelessWidget {
  const _Reading({
    required this.label,
    required this.belief,
    required this.show,
  });

  final String label;
  final Confident<T> belief;
  final String Function(T value) show;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final band = ConfidenceThresholds.bandFor(belief.confidence);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        // Top-aligned, because a long fabric list wraps to two lines and a
        // centred chip then floats beside the middle of the text it qualifies.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text(
                show(belief.value),
                style: theme.textTheme.bodyLarge?.copyWith(
                  // Uncertain readings are tinted rather than annotated. The
                  // chip beside this already says "Please check", and adding a
                  // second line saying the same thing made the row noisier
                  // without making it any clearer.
                  color: band == ConfidenceBand.high
                      ? null
                      : theme.colorScheme.confidenceColor(band),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ConfidenceChip.of(belief),
          ],
        ),
      ),
    );
  }
}

class _LabelOutcome extends StatelessWidget {
  const _LabelOutcome({required this.read});

  final bool read;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return NoteRow(
      icon: read ? Icons.check_circle_outline : Icons.error_outline,
      color: read ? scheme.primary : scheme.error,
      text: read
          ? 'The care label was read from your photo, so the washing '
                'below comes from the manufacturer rather than a guess.'
          : 'The care label photo could not be read, so the washing '
                'below is worked out from the fabric. You can scan the '
                'label again from the item once it is saved.',
    );
  }
}

class _CareSummary extends StatelessWidget {
  const _CareSummary({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wash = item.effectiveCare.wash;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'How it will be washed',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                ConfidenceChip(
                  confidence: item.care.confidence,
                  source: item.care.source,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              wash.method == WashMethod.doNotWash
                  ? 'Do not wash'
                  : '${wash.method.label}'
                        '${wash.maxTempC == null ? '' : ', up to ${wash.maxTempC}°C'}'
                        ', ${wash.agitation.label.toLowerCase()}',
              style: theme.textTheme.bodyMedium,
            ),
            if (item.needsCareTagScan) ...[
              const SizedBox(height: 12),
              Text(
                // The honest statement of what just happened: the fabric was
                // read from a photograph and the care follows from a rule, not
                // from the manufacturer.
                'This is derived from the fabric, not from a care label. '
                'Scan the label to be certain.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// How the answer was produced.
///
/// Shown in the app, not buried in a log. "Answered from memory in 4 ms" is the
/// visible evidence that the cost-ordered pipeline works, and during a build it
/// is the difference between trusting the cache and hoping.
class _Diagnostics extends StatelessWidget {
  const _Diagnostics({required this.diagnostics});

  final ScanDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        [
          if (diagnostics.servedFromCache)
            'Answered from memory'
          else if (diagnostics.stageAnswered case final String stage)
            'Answered by $stage',
          '${diagnostics.elapsedMs} ms',
        ].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
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
