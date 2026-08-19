/// Photograph everything, then hand it over.
///
/// Four steps, and the order is the point: collect → process → review → done.
/// The single scan screen interleaves those per garment, which is right for one
/// and unbearable for forty.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../widgets/status_message.dart';
import 'bulk_controller.dart';
import 'scan_controller.dart' show ScanShot;

class BulkScanScreen extends ConsumerWidget {
  const BulkScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bulkControllerProvider);
    final controller = ref.read(bulkControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            controller.reset();
            context.go('/');
          },
        ),
        title: const Text('Add several garments'),
      ),
      body: switch (state) {
        final BulkCollecting collecting => _Collecting(
          state: collecting,
          controller: controller,
        ),
        BulkProcessing(:final finished, :final total) => _Processing(
          finished: finished,
          total: total,
        ),
        final BulkReviewing reviewing => _Reviewing(
          state: reviewing,
          controller: controller,
        ),
        BulkSaved(:final saved, :final skipped) => _Done(
          saved: saved,
          skipped: skipped,
          controller: controller,
        ),
        BulkFailed(:final message) => StatusMessage(
          icon: Icons.error_outline,
          title: 'Could not take that photo',
          detail: message,
          action: FilledButton.tonal(
            onPressed: controller.reset,
            child: const Text('Start again'),
          ),
        ),
      },
    );
  }
}

class _Collecting extends StatelessWidget {
  const _Collecting({required this.state, required this.controller});

  final BulkCollecting state;
  final BulkController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = state.current;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                state.isEmpty
                    ? 'Nothing photographed yet'
                    : '${state.garmentCount} '
                          '${state.garmentCount == 1 ? 'garment' : 'garments'}, '
                          '${state.photoCount} photos',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Photograph each garment and its care label, then tap Next '
                'garment and start the following one. Nothing is sent until '
                'you submit the lot, so you can work through a whole pile '
                'without waiting.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (state.done.isNotEmpty) ...[
                Text(
                  'Finished',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (index, garment) in state.done.indexed)
                      Chip(
                        avatar: Icon(
                          garment.hasCareTag
                              ? Icons.local_offer_outlined
                              : Icons.checkroom_outlined,
                          size: 16,
                        ),
                        label: Text(
                          '${index + 1} · ${garment.shots.length} '
                          '${garment.shots.length == 1 ? 'photo' : 'photos'}',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              Text(
                current.isEmpty
                    ? 'This garment'
                    : 'This garment · ${current.shots.length} '
                          '${current.shots.length == 1 ? 'photo' : 'photos'}',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              if (current.isEmpty)
                Text(
                  'Take the front, the back if it differs, and the care label.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final (index, shot) in current.shots.indexed)
                      _ShotTile(
                        shot: shot,
                        onRole: (role) => controller.setRole(index, role),
                      ),
                  ],
                ),
              if (current.hasCareTag) ...[
                const SizedBox(height: 8),
                Text(
                  'The care label is in here, so it will be read with this '
                  'garment.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
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
                      child: FilledButton.icon(
                        onPressed: controller.capture,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Take a photo'),
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        // Disabled with nothing in hand: an empty garment is
                        // one more thing to explain in the review list.
                        onPressed: current.isEmpty
                            ? null
                            : controller.nextGarment,
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Next garment'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: state.isEmpty ? null : controller.submit,
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: Text('Submit ${state.garmentCount}'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The unattended wait, counted rather than spun at: this is the one screen
/// somebody is invited to walk away from, and "9 of 40" is what makes coming
/// back at the right time possible.
class _Processing extends StatelessWidget {
  const _Processing({required this.finished, required this.total});

  final int finished;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              child: LinearProgressIndicator(
                value: total == 0 ? null : finished / total,
              ),
            ),
            const SizedBox(height: 20),
            Text('$finished of $total', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Reading each garment and its label. You can put the phone down '
              '— nothing is saved until you have looked at the results.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reviewing extends StatelessWidget {
  const _Reviewing({required this.state, required this.controller});

  final BulkReviewing state;
  final BulkController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accepted = state.accepted.length;

    if (state.readable.isEmpty) {
      return StatusMessage(
        icon: Icons.error_outline,
        title: 'None of them could be read',
        detail: state.failed.firstOrNull?.failure ?? 'Nothing came back.',
        action: FilledButton.tonal(
          onPressed: controller.reset,
          child: const Text('Start again'),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${state.readable.length} read',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Everything is ticked. Untick anything you do not want, fix a '
                'name if it is wrong, then save the lot.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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
              if (state.failed.isNotEmpty) ...[
                const SizedBox(height: 8),
                // Named rather than silently dropped: thirty-seven back out
                // of forty would leave somebody counting hangers.
                Text(
                  '${state.failed.length} could not be read',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                for (final failure in state.failed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Garment ${failure.index + 1}: ${failure.failure}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Their photos are not kept. Add those few the usual way.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: accepted, onChanged: (_) => onToggle()),
            if (front != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  Uint8List.fromList(front.image.bytes),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 56,
                    height: 56,
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(draft.displayName, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${draft.type.value.label}'
                    '${draft.composition.value.isEmpty ? '' : ' · ${draft.composition.value.label}'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Per garment, because in a list of forty this is the only
                  // place the difference is visible.
                  if (read.label != null)
                    _Note(
                      icon: Icons.check_circle_outline,
                      text: 'Care label read',
                      color: theme.colorScheme.primary,
                    )
                  else if (read.labelUnread)
                    _Note(
                      icon: Icons.error_outline,
                      text: 'Label photo unreadable — washing is a guess',
                      color: theme.colorScheme.error,
                    ),
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

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ),
    ],
  );
}

class _Done extends StatelessWidget {
  const _Done({
    required this.saved,
    required this.skipped,
    required this.controller,
  });

  final int saved;
  final int skipped;
  final BulkController controller;

  @override
  Widget build(BuildContext context) => StatusMessage(
    icon: Icons.check_circle_outline,
    title: saved == 1 ? '1 garment added' : '$saved garments added',
    detail: skipped == 0
        ? 'They are in your wardrobe now.'
        : '$skipped were not saved.',
    action: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: () {
            controller.reset();
            GoRouter.of(context).go('/');
          },
          child: const Text('See the wardrobe'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: controller.reset, child: const Text('Add more')),
      ],
    ),
  );
}

/// One photograph, with what it shows. The same roles the single scan screen
/// offers, care label included.
class _ShotTile extends StatelessWidget {
  const _ShotTile({required this.shot, required this.onRole});

  final ScanShot shot;
  final ValueChanged<PhotoRole> onRole;

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
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              Uint8List.fromList(shot.image.bytes),
              width: 96,
              height: 96,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 96,
                height: 96,
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.image_not_supported_outlined),
              ),
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
                Flexible(
                  child: Text(
                    shot.role.label,
                    style: theme.textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 16,
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
