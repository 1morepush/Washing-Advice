/// Capture → analysing → review → saved.
///
/// The review step is the reason the rest of the system tracks confidence. A
/// scan produces beliefs of varying strength, and this screen shows them as
/// what they are: settled facts stay quiet, uncertain ones are marked, and a
/// care profile that needs a label says so before anything gets washed.
library;

import 'dart:async';

import 'dart:typed_data';

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

class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanControllerProvider);
    final controller = ref.read(scanControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            controller.reset();
            context.go('/');
          },
        ),
        title: const Text('Scan a garment'),
      ),
      body: switch (state) {
        ScanIdle() => _Capture(controller: controller),
        ScanCollecting(:final shots) => _Collected(
          shots: shots,
          controller: controller,
        ),
        ScanAnalysing(:final imageCount) => _Analysing(imageCount: imageCount),
        ScanReviewing() => _Review(state: state, controller: controller),
        ScanSaved(:final item) => _Saved(item: item, controller: controller),
        ScanError(:final message, :final isRetryable) => _Failed(
          message: message,
          isRetryable: isRetryable,
          controller: controller,
        ),
      },
    );
  }
}

class _Capture extends StatelessWidget {
  const _Capture({required this.controller});

  final ScanController controller;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.checkroom_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Photograph the garment',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Lay it flat against a plain background. Take the back too if '
            'there is a print on it — a plain navy tee and one with a design '
            'across the back look the same from the front, to you and to the '
            'app.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
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
      ),
    ),
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

/// What the rule table concluded from the reading.
/// What became of a care label photographed alongside the garment.
///
/// The failure matters more than the success: the user took that photograph
/// deliberately, and a silent screen would leave them believing the
/// manufacturer's instructions were in hand when a guess is showing.
class _LabelOutcome extends StatelessWidget {
  const _LabelOutcome({required this.read});

  final bool read;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = read ? theme.colorScheme.primary : theme.colorScheme.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            read ? Icons.check_circle_outline : Icons.error_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              read
                  ? 'The care label was read from your photo, so the washing '
                        'below comes from the manufacturer rather than a guess.'
                  : 'The care label photo could not be read, so the washing '
                        'below is worked out from the fabric. You can scan the '
                        'label again from the item once it is saved.',
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            '${item.displayName} added',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              controller.reset();
              context.go('/item/${item.id.value}');
            },
            child: const Text('View it'),
          ),
          TextButton(
            onPressed: controller.reset,
            child: const Text('Scan another'),
          ),
        ],
      ),
    ),
  );
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.message,
    required this.isRetryable,
    required this.controller,
  });

  final String message;
  final bool isRetryable;
  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            // "Try again" is offered only when trying again could work. A 422
            // means this photograph will never parse, and inviting a retry
            // would just waste the user's time.
            FilledButton(
              onPressed: controller.reset,
              child: Text(isRetryable ? 'Try again' : 'Take another photo'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The photographs taken so far, with what each one shows.
///
/// The reason this screen exists is the shirt with a print across the back. It
/// is identical to a plain one from the front, so a flow that identified the
/// first shot the moment it was taken would confidently call it plain — and
/// there would be nothing on the result to suggest otherwise.
class _Collected extends StatelessWidget {
  const _Collected({required this.shots, required this.controller});

  final List<ScanShot> shots;
  final ScanController controller;

  bool get hasCareTag => shots.any((shot) => shot.role == PhotoRole.careTag);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                shots.length == 1 ? 'One photo' : '${shots.length} photos',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'All of one garment, read together. Tap a photo to say what it '
                'shows. Nothing has been sent yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              // Said here rather than discovered afterwards: somebody who does
              // not know they can include the tag keeps making a second trip.
              Text(
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
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (index, shot) in shots.indexed)
                    _ShotTile(
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
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: controller.capture,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('Add another photo'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: controller.discardLast,
                      icon: const Icon(Icons.undo),
                      tooltip: 'Remove the last photo',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: controller.scanCollected,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(switch ((shots.length, hasCareTag)) {
                      (1, _) => 'Identify it',
                      (final n, true) => 'Identify and read the label ($n)',
                      (final n, false) => 'Identify from these $n',
                    }),
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

/// One collected photograph, labelled with the part of the garment it shows.
///
/// The label is a guess — front, then back, then details — and tapping it
/// changes it. Guessing and letting the user correct is the right trade for
/// something they would otherwise have to set on every single shot, and the
/// order people photograph a garment in is genuinely predictable.
class _ShotTile extends StatelessWidget {
  const _ShotTile({
    required this.shot,
    required this.onRole,
    required this.onCrop,
  });

  final ScanShot shot;
  final ValueChanged<PhotoRole> onRole;
  final VoidCallback onCrop;

  /// The parts worth offering. `condition` and `worn` are left out: filing a
  /// stain photo is a different question with its own screen. The care label
  /// is included, and is read in the same pass by the label reader.
  static const _offered = [
    PhotoRole.front,
    PhotoRole.back,
    PhotoRole.careTag,
    PhotoRole.detail,
    PhotoRole.logo,
    PhotoRole.brandTag,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 108,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tapping the picture crops it, with the badge saying so — an
          // affordance that has to be visible, because nobody taps a
          // thumbnail to find out what happens.
          InkWell(
            onTap: onCrop,
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    Uint8List.fromList(shot.image.bytes),
                    width: 108,
                    height: 108,
                    fit: BoxFit.cover,
                    // A thumbnail that will not decode must not take the
                    // screen with it — the photograph is still perfectly good
                    // to the server.
                    errorBuilder: (_, _, _) => Container(
                      width: 108,
                      height: 108,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.crop, size: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          PopupMenuButton<PhotoRole>(
            onSelected: onRole,
            tooltip: 'What this photo shows',
            itemBuilder: (_) => [
              for (final role in _offered)
                PopupMenuItem(value: role, child: Text(role.label)),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(shot.role.label, style: theme.textTheme.labelMedium),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
