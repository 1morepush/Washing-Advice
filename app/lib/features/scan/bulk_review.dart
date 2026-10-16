/// The review step of a bulk scan: what each photograph came to.
///
/// One card per garment, with the ones that need another look first. Split from
/// the screen because it is where the screen's complexity lives — the
/// collecting, processing and finished views are short.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/theme.dart';
import '../../widgets/notice.dart';
import '../../widgets/rinse_kit.dart';
import 'bulk_controller.dart';
import 'scan_controller.dart' show ScanShot;
import 'scan_parts.dart';

class BulkReviewList extends StatelessWidget {
  const BulkReviewList({
    required this.state,
    required this.controller,
    super.key,
  });

  final BulkReviewing state;
  final BulkController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accepted = state.accepted.length;

    if (state.readable.isEmpty) {
      // Still a list rather than a single message: even when every one of
      // them failed, which garment was which is the thing the user has to
      // work out before they can do anything about it.
      return Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const ScanHeading(
                  'None of them could be read',
                  body:
                      'Here is what you photographed, so you can find them '
                      'again.',
                ),
                const SizedBox(height: 16),
                for (final outcome in state.failed)
                  _FailureCard(outcome: outcome),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: controller.reset,
                  child: const Text('Start again'),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ScanHeading(
                '${state.readable.length} read',
                body:
                    'Everything is ticked. Untick anything you do not want, '
                    'fix a name if it is wrong, then save the lot.',
              ),

              // Said at the top and shown before the successes. Anything that
              // needs the user to walk back to the pile has to be seen before
              // they press Save and put the phone down — under forty cards it
              // may as well not be there.
              if (state.failed.isNotEmpty || state.labelUnread.isNotEmpty) ...[
                const SizedBox(height: 16),
                _NeedsAnotherLook(
                  failed: state.failed.length,
                  labelUnread: state.labelUnread.length,
                ),
              ],

              if (state.failed.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionLabel(
                  state.failed.length == 1
                      ? '1 could not be read'
                      : '${state.failed.length} could not be read',
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                ),
                for (final outcome in state.failed)
                  _FailureCard(outcome: outcome),
                Text(
                  'These are not saved. Photograph them again — the pictures '
                  'above are here to help you find them, and go when you '
                  'leave this screen.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],

              const SizedBox(height: 16),
              for (final outcome in state.readable)
                _OutcomeCard(
                  outcome: outcome,
                  accepted: !state.rejected.contains(outcome.index),
                  onToggle: () => controller.toggle(outcome.index),
                  onRename: (name) => controller.revise(
                    outcome.index,
                    (draft) => draft.copyWith(name: name),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: accepted == 0 ? null : controller.saveAccepted,
                icon: const Icon(Icons.check),
                label: Text(
                  accepted == 1 ? 'Save 1 garment' : 'Save $accepted garments',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({
    required this.outcome,
    required this.accepted,
    required this.onToggle,
    required this.onRename,
  });

  final BulkOutcome outcome;
  final bool accepted;
  final VoidCallback onToggle;
  final ValueChanged<String> onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final read = outcome.read!;
    final draft = read.draft;
    final front = read.shots.isEmpty ? null : read.shots.first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RinseCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: accepted, onChanged: (_) => onToggle()),
            if (front != null) ...[
              ScanThumb(image: front.image, size: 60),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(draft.displayName, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${draft.type.value.label}'
                    '${draft.composition.value.isEmpty ? '' : ' · ${draft.composition.value.label}'}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Per garment, because in a list of forty this is the only
                  // place the difference is visible.
                  if (read.label != null)
                    NoteRow(
                      icon: Icons.check_circle_outline,
                      text: 'Care label read',
                      color: theme.colorScheme.primary,
                      iconSize: 14,
                      gap: 6,
                      bottomPadding: 0,
                    )
                  else if (read.labelUnread) ...[
                    NoteRow(
                      icon: Icons.error_outline,
                      text: 'Label photo unreadable — washing is a guess',
                      color: theme.colorScheme.error,
                      iconSize: 14,
                      gap: 6,
                      bottomPadding: 0,
                    ),
                    // The tag, not the garment. This garment is going into the
                    // wardrobe either way; what needs finding again is the
                    // label, and one crumpled tag looks much like another
                    // until you see the one that was photographed.
                    if (outcome.labelShot case final label?) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _Thumb(shot: label, size: 40),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This is the photo that could not be read.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: () async {
                final name = await _askName(context, draft.displayName);
                if (name != null) onRename(name);
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Rename',
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askName(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              Navigator.pop(context, trimmed.isEmpty ? null : trimmed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// The count of what still needs the user, said before anything else.
///
/// A batch is submitted and walked away from. Coming back to "38 read" and a
/// Save button, the natural move is to press it — and the two that failed are
/// forty cards further down, discovered a week later when a garment is missing
/// and the pile is long since put away.
class _NeedsAnotherLook extends StatelessWidget {
  const _NeedsAnotherLook({required this.failed, required this.labelUnread});

  final int failed;
  final int labelUnread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final parts = <String>[
      if (failed > 0)
        failed == 1
            ? '1 garment could not be read'
            : '$failed garments could not be read',
      if (labelUnread > 0)
        labelUnread == 1
            ? "1 care label did not come out"
            : '$labelUnread care labels did not come out',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: context.rinse.tileBorderRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.photo_camera_outlined,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parts.join(', and '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Each one is shown with the photo you took, so you can find '
                  'it in the pile before you put it away.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A garment that came back with nothing, shown as what was photographed.
///
/// Deliberately the same size and shape as a garment that worked. The
/// difference between "in your wardrobe" and "still in the pile" is worth a
/// card either way, and a failure rendered as a line of red text reads as a
/// footnote about the batch rather than a thing to go and do.
class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.outcome});

  final BulkOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identifying = outcome.identifyingShot;
    final others = [
      for (final shot in outcome.shots)
        if (!identical(shot, identifying)) shot,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RinseCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (identifying != null) ...[
                  _Thumb(shot: identifying, size: 72),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Garment ${outcome.index + 1}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        outcome.failure ?? 'Nothing came back for this one.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // The rest of what was taken. The identifying shot is the one that
            // finds the garment; a close-up of a seam or the tag is what says
            // which photograph needs taking again.
            if (others.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: others.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) =>
                      _Thumb(shot: others[index], size: 48, labelled: true),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One photograph, at whatever size the caller has room for.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.shot, required this.size, this.labelled = false});

  final ScanShot shot;
  final double size;

  /// Whether to mark a care-label shot as one. Only worth saying where several
  /// photographs sit side by side and a tag is hard to tell from a sleeve.
  final bool labelled;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ScanThumb(image: shot.image, size: size),
      if (labelled && shot.role == PhotoRole.careTag)
        const Positioned(
          left: 3,
          right: 3,
          bottom: 3,
          child: Center(child: PhotoBadge(text: 'Label')),
        ),
    ],
  );
}
