/// Laying several garments out and photographing them together.
///
/// Four steps, the same order the other scan screens use: capture → analysing
/// → review → done. What differs is the arithmetic. One photograph here
/// produces several garments, so the review list is the whole point rather
/// than a formality, and the only thing asked of the user per garment is
/// whether to keep it.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../widgets/status_message.dart';
import 'spread_controller.dart';

class SpreadScanScreen extends ConsumerWidget {
  const SpreadScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spreadControllerProvider);
    final controller = ref.read(spreadControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            controller.reset();
            context.go('/');
          },
        ),
        title: const Text('Lay several out'),
      ),
      body: switch (state) {
        SpreadIdle() => _Start(controller: controller),
        SpreadAnalysing() => const _Analysing(),
        final SpreadReviewing reviewing => _Reviewing(
          state: reviewing,
          controller: controller,
        ),
        final SpreadSaved saved => _Done(state: saved, controller: controller),
        final SpreadFailed failed => StatusMessage(
          icon: Icons.error_outline,
          title: 'That did not work',
          detail: failed.message,
          action: failed.isRetryable
              ? FilledButton.icon(
                  onPressed: controller.capture,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Take another photo'),
                )
              : FilledButton.tonal(
                  onPressed: controller.reset,
                  child: const Text('Start again'),
                ),
        ),
      },
    );
  }
}

class _Start extends StatelessWidget {
  const _Start({required this.controller});

  final SpreadController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.grid_view_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Lay them out and take one photo',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Spread a few garments on a bed or the floor so none of '
                    'them overlaps, and photograph the lot. Each one becomes '
                    'its own garment, with its own picture cut out of the '
                    'photo.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Said here rather than discovered later. Somebody deciding
                  // between this and photographing each garment properly needs
                  // to know what they are giving up.
                  Text(
                    'Quick rather than thorough: no backs and no care labels. '
                    'Add those later for the garments that need them.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
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
                  onPressed: () => controller.capture(fromGallery: true),
                  icon: const Icon(Icons.photo_library_outlined),
                  tooltip: 'Choose a photo',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Analysing extends StatelessWidget {
  const _Analysing();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('Finding the garments…', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'One read of the photo finds them all, so this takes about as '
              'long as a single garment would.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
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

  final SpreadReviewing state;
  final SpreadController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accepted = state.accepted.length;
    final owned = state.alreadyOwnedCount;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                state.finds.length == 1
                    ? '1 garment found'
                    : '${state.finds.length} garments found',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                owned == 0
                    ? 'Untick anything that is not a garment, fix a name if it '
                          'is wrong, then save.'
                    : owned == 1
                    ? 'One of these is already in your wardrobe and is not '
                          'ticked. The rest are new.'
                    : '$owned of these are already in your wardrobe and are '
                          'not ticked. The rest are new.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              for (final (index, find) in state.finds.indexed)
                _FindCard(
                  find: find,
                  accepted: !state.rejected.contains(index),
                  onToggle: () => controller.toggle(index),
                  onRename: (name) => controller.rename(index, name),
                ),
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
                  accepted == 1 ? 'Add 1 garment' : 'Add $accepted garments',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FindCard extends StatelessWidget {
  const _FindCard({
    required this.find,
    required this.accepted,
    required this.onToggle,
    required this.onRename,
  });

  final SpreadFind find;
  final bool accepted;
  final VoidCallback onToggle;
  final ValueChanged<String> onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = find.draft;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: accepted, onChanged: (_) => onToggle()),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                Uint8List.fromList(find.image.bytes),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    draft.displayName,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    draft.type.value.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (find.ownedAs case final WardrobeItem owned) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Looks like "${owned.displayName}", already in '
                            'your wardrobe',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
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
        title: const Text('Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.state, required this.controller});

  final SpreadSaved state;
  final SpreadController controller;

  @override
  Widget build(BuildContext context) => StatusMessage(
    icon: Icons.check_circle_outline,
    title: state.saved == 1
        ? '1 garment added'
        : '${state.saved} garments added',
    detail: state.skipped == 0
        ? 'Photograph another armful, or go back to the wardrobe.'
        : '${state.skipped} could not be saved.',
    action: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          // The common case by a distance: somebody doing this is doing it to
          // a whole wardrobe, an armful at a time.
          onPressed: controller.capture,
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Do another armful'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            controller.reset();
            GoRouter.of(context).go('/');
          },
          child: const Text('Back to the wardrobe'),
        ),
      ],
    ),
  );
}
