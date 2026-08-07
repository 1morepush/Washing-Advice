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
            'Lay it flat against a plain background. A front and a back '
            'read better than one shot.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: controller.captureAndScan,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Take a photo'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => controller.captureAndScan(fromGallery: true),
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
              Text(
                draft.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
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
                label: 'Colour',
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
