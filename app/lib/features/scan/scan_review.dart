/// The review step of a garment scan: the beliefs the scan produced.
///
/// Settled facts stay quiet and uncertain ones are marked. Split from the
/// screen, which is the state switch around it.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/theme.dart';
import '../../data/api/scan_dto.dart';
import '../../widgets/confidence_chip.dart';
import '../../widgets/notice.dart';
import 'scan_controller.dart';

class ScanReview extends StatelessWidget {
  const ScanReview({required this.state, required this.controller, super.key});

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
