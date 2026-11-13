/// The Cutouts group on the settings screen: re-cut the wardrobe's pictures.
///
/// One button, and while it runs a progress line, a bar and a Cancel. Written
/// to be read at 320 px and 1.6x text: everything is a stacked, wrapping line
/// and no two controls share a row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wardrobe/redo_cutouts_controller.dart';

/// The explanation behind the Cutouts group's info button.
const cutoutsInfo =
    'Each garment\'s picture is its photograph with the background taken away. '
    'When the server gets better at that, this re-cuts them all from the '
    'photographs already on this device — nothing needs re-photographing.\n\n'
    'It goes one garment at a time and you can stop it whenever you like. A '
    'cutout is only replaced when the new one looks right, and any cutout you '
    'tidied by hand in the editor is left exactly as you made it. Garments '
    'photographed while worn are skipped.';

/// What the finished run says, in a sentence a person can act on.
String redoSummary(RedoFinished done) {
  final parts = <String>[
    done.cancelled ? 'Stopped.' : 'Done.',
    if (done.redone == 1) '1 cutout redone.' else '${done.redone} cutouts redone.',
    if (done.kept > 0)
      done.kept == 1
          ? '1 kept as it was — the server could not do better.'
          : '${done.kept} kept as they were — the server could not do better.',
    if (done.skippedHandEdited > 0)
      done.skippedHandEdited == 1
          ? '1 you edited by hand was left alone.'
          : '${done.skippedHandEdited} you edited by hand were left alone.',
    if (done.skippedWorn > 0)
      done.skippedWorn == 1
          ? '1 worn photo was skipped.'
          : '${done.skippedWorn} worn photos were skipped.',
  ];
  return parts.join(' ');
}

class CutoutsSection extends ConsumerWidget {
  const CutoutsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(redoCutoutsProvider);
    final controller = ref.read(redoCutoutsProvider.notifier);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Re-cut every garment\'s picture with the current background '
          'remover. Cutouts you edited by hand are never touched.',
          style: muted,
        ),
        const SizedBox(height: 12),
        switch (state) {
          RedoRunning() => _Running(state: state, onCancel: controller.cancel),
          _ => OutlinedButton.icon(
            onPressed: controller.run,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('Redo cutouts'),
          ),
        },
        if (state case final RedoFinished done) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(redoSummary(done), style: theme.textTheme.bodyMedium),
          ),
        ],
      ],
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.state, required this.onCancel});

  final RedoRunning state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = state.total == 0 ? null : state.finished / state.total;

    final line = state.cancelling
        ? 'Stopping after this garment…'
        : state.waiting != null
        ? 'The server asked for a short break — '
              'continuing in ${state.waiting!.inSeconds.clamp(1, 9999)} s…'
        : 'Redoing cutouts: ${state.finished} of ${state.total}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(line, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: fraction),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: state.cancelling ? null : onCancel,
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
        ),
      ],
    );
  }
}
