/// Adding clothes from photos of you wearing them.
///
/// Capture → reading, photo by photo → review → done, the order the other scan
/// screens use. The review is the lay-flat scan's: a tile per garment with a
/// tick, and the only thing asked of the person is whether to keep each one.
/// What this screen adds is honesty about the pictures. A garment cut out
/// along its outline is a different thing from a rectangle of the photo with
/// the room still in it, and the tile says which one it is showing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/theme.dart';
import '../../widgets/back_navigation.dart';
import '../../widgets/rinse_kit.dart';
import '../../widgets/state_view.dart';
import '../../widgets/status_message.dart';
import 'scan_parts.dart';
import 'worn_photo_controller.dart';

class WornPhotoScreen extends ConsumerWidget {
  const WornPhotoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wornPhotoControllerProvider);
    final controller = ref.read(wornPhotoControllerProvider.notifier);

    return LeaveScope(
      onLeave: controller.reset,
      child: Scaffold(
        appBar: AppBar(
          leading: backLeading(context, '/', onLeave: controller.reset),
          title: const AppBarTitle('From a photo of me'),
        ),
        body: switch (state) {
          WornIdle() => _Start(controller: controller),
          final WornScanning scanning => _Scanning(state: scanning),
          final WornReviewing reviewing => _Reviewing(
            state: reviewing,
            controller: controller,
          ),
          final WornSaved saved => _Done(state: saved, controller: controller),
          final WornFailed failed => StatusMessage(
            icon: Icons.error_outline,
            title: 'That did not work',
            detail: failed.message,
            action: failed.isRetryable
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: () => controller.start(fromGallery: true),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose photos'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: controller.start,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Take a photo'),
                      ),
                    ],
                  )
                : FilledButton.tonal(
                    onPressed: controller.reset,
                    child: const Text('Start again'),
                  ),
          ),
        },
      ),
    );
  }
}

class _Start extends StatelessWidget {
  const _Start({required this.controller});

  final WornPhotoController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const IconBadge(Icons.checkroom_outlined, size: 112),
                  const SizedBox(height: 24),
                  Text(
                    'Add clothes from a photo of you',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick photos of you wearing your clothes, or take one. '
                    'Each garment is cut out of the photo and added with its '
                    'own picture.',
                    textAlign: TextAlign.center,
                    style: quiet,
                  ),
                  const SizedBox(height: 16),
                  // Said before the photo is chosen, so nobody is surprised by
                  // what a photo of a person can and cannot give.
                  Text(
                    'The pictures show your clothes as worn, and anything '
                    'under a jacket may be partly hidden. A photo cannot show '
                    'a care label, so you will be asked to scan those later. '
                    'The photo goes to the scan server with you in it.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ScanActionBar(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => controller.start(fromGallery: true),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose photos'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: controller.start,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take a photo'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Scanning extends StatelessWidget {
  const _Scanning({required this.state});

  final WornScanning state;

  @override
  Widget build(BuildContext context) {
    final String detail;
    if (state.waitingFor case final Duration wait) {
      detail =
          'The scan server is busy. Waiting ${_seconds(wait)} before trying '
          'this photo again.';
    } else if (state.waking) {
      detail =
          'The server is waking up. This can take up to a minute the first '
          'time.';
    } else {
      detail = 'Each photo is read once, so a few photos take a little while.';
    }

    return LoadingView(
      title: state.total == 1
          ? 'Finding the garments…'
          : 'Photo ${state.current} of ${state.total}',
      detail: detail,
      heading: true,
      gap: 24,
    );
  }

  static String _seconds(Duration wait) {
    final seconds = wait.inSeconds < 1 ? 1 : wait.inSeconds;
    return seconds == 1 ? '1 second' : '$seconds seconds';
  }
}

class _Reviewing extends StatelessWidget {
  const _Reviewing({required this.state, required this.controller});

  final WornReviewing state;
  final WornPhotoController controller;

  @override
  Widget build(BuildContext context) {
    final accepted = state.accepted.length;
    final known = state.alreadyOwnedCount + state.repeatCount;
    final theme = Theme.of(context);

    if (state.finds.isEmpty) {
      return StatusMessage(
        icon: Icons.search_off_outlined,
        title: 'No garments found',
        detail: state.notes.length == 1
            ? state.notes.single.message
            : state.notes
                  .map((n) => 'Photo ${n.photoNumber}: ${n.message}')
                  .join('\n'),
        action: FilledButton(
          onPressed: controller.reset,
          child: const Text('Try other photos'),
        ),
      );
    }

    final multiple = state.photos.length > 1;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ScanHeading(
                state.finds.length == 1
                    ? '1 garment found'
                    : '${state.finds.length} garments found',
                body: known == 0
                    ? 'Untick anything that is not a garment, fix a name if '
                          'it is wrong, then add them.'
                    : known == 1
                    ? 'One of these is already in your wardrobe or came up '
                          'earlier, so it is not ticked. The rest are new.'
                    : '$known of these are already in your wardrobe or came '
                          'up earlier, so they are not ticked. The rest are '
                          'new.',
              ),
              const SizedBox(height: 16),
              for (final note in state.notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RinseCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Photo ${note.photoNumber}: ${note.message}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final (index, find) in state.finds.indexed)
                _FindCard(
                  find: find,
                  accepted: !state.rejected.contains(index),
                  showPhotoNumber: multiple,
                  onToggle: () => controller.toggle(index),
                  onRename: (name) => controller.rename(index, name),
                ),
            ],
          ),
        ),
        ScanActionBar(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: accepted == 0 ? null : controller.saveAccepted,
                icon: const Icon(Icons.check),
                label: Text(
                  accepted == 1 ? 'Add 1 garment' : 'Add $accepted garments',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// What the garment's page offers a picture that still has background in it:
/// "Mark out by hand" and "New photo". "Clean up" is deliberately not promised:
/// it is the lay-flat remover, which looks for a plain border to subtract, and
/// the border of a crop from a photo of a person is arms, a face and a room.
const _backgroundNote =
    'Includes some background. On the garment\'s page you can mark it out by '
    'hand or take a new photo; "Clean up" is made for clothes laid flat and '
    'may not work on this.';

class _FindCard extends StatelessWidget {
  const _FindCard({
    required this.find,
    required this.accepted,
    required this.showPhotoNumber,
    required this.onToggle,
    required this.onRename,
  });

  final WornFind find;
  final bool accepted;
  final bool showPhotoNumber;
  final VoidCallback onToggle;
  final ValueChanged<String> onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = find.draft;
    final accent = context.rinse.textAccent;

    Widget note(IconData icon, String text, {bool strong = false}) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: strong ? accent : null),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: strong ? FontWeight.w700 : null,
                color: strong ? accent : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RinseCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: 'Add ${draft.displayName}',
              child: Checkbox(value: accepted, onChanged: (_) => onToggle()),
            ),
            // Whole, not cropped to a square: a long coat and a pair of shoes
            // are the shapes cover-fitting would cut.
            ScanThumb(
              image: find.preview,
              size: 64,
              fit: BoxFit.contain,
              garmentRgb: draft.colors.value.colors.firstOrNull?.rgb,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    draft.displayName,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    showPhotoNumber
                        ? '${draft.type.value.label}, photo '
                              '${find.photoIndex + 1}'
                        : draft.type.value.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (find.ownedAs case final WardrobeItem owned)
                    note(
                      Icons.inventory_2_outlined,
                      'Looks like "${owned.displayName}", already in your '
                      'wardrobe',
                      strong: true,
                    ),
                  if (find.repeatOf case final WornRepeat repeat)
                    note(
                      Icons.copy_all_outlined,
                      'Looks like "${repeat.name}" from photo '
                      '${repeat.photoNumber}',
                      strong: true,
                    ),
                  // Plain words about the picture, so a tile with a bedroom in
                  // it is never mistaken for a bad cutout of something else.
                  if (find.pictureKind == WornPicture.box)
                    note(Icons.crop_outlined, _backgroundNote),
                  if (find.pictureKind == WornPicture.cropped)
                    note(
                      Icons.crop_outlined,
                      'Cropped from your photo. $_backgroundNote',
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        final name = await _askName(context, draft.displayName);
                        if (name != null && name.isNotEmpty) onRename(name);
                      },
                      child: const Text('Rename'),
                    ),
                  ),
                ],
              ),
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

  final WornSaved state;
  final WornPhotoController controller;

  @override
  Widget build(BuildContext context) => StatusMessage(
    icon: Icons.check_circle_outline,
    title: state.saved == 1
        ? '1 garment added'
        : '${state.saved} garments added',
    detail: state.skipped == 0
        ? 'Their care is a guess from what was seen. Open a garment and scan '
              'its care label to get the exact washing advice.'
        : '${state.skipped} could not be saved.',
    action: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: controller.reset,
          child: const Text('Add from more photos'),
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
