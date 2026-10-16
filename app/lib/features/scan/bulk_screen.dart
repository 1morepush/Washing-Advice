/// Photograph everything, then hand it over.
///
/// Four steps, and the order is the point: collect → process → review → done.
/// The single scan screen interleaves those per garment, which is right for one
/// and unbearable for forty.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/back_navigation.dart';
import '../../widgets/notice.dart';
import '../../widgets/rinse_kit.dart';
import '../../widgets/status_message.dart';
import 'bulk_controller.dart';
import 'bulk_review.dart';
import 'crop_screen.dart';
import 'scan_parts.dart';
import 'shot_tile.dart';

class BulkScanScreen extends ConsumerWidget {
  const BulkScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bulkControllerProvider);
    final controller = ref.read(bulkControllerProvider.notifier);

    return LeaveScope(
      onLeave: controller.reset,
      child: Scaffold(
        appBar: AppBar(
          leading: backLeading(context, '/', onLeave: controller.reset),
          title: const AppBarTitle('Add several garments'),
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
          final BulkReviewing reviewing => BulkReviewList(
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
      ),
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
              ScanHeading(
                state.isEmpty
                    ? 'Nothing photographed yet'
                    : '${state.garmentCount} '
                          '${state.garmentCount == 1 ? 'garment' : 'garments'}, '
                          '${state.photoCount} photos',
                body:
                    'Photograph each garment and its care label, then tap Next '
                    'garment and start the following one. Nothing is sent '
                    'until you submit the lot, so you can work through a '
                    'whole pile without waiting.',
              ),
              const SizedBox(height: 8),
              if (state.done.isNotEmpty) ...[
                const SectionLabel(
                  'Finished',
                  padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
                ),
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
              // Offered here rather than in Settings. It is a property of the
              // session somebody is in the middle of — documenting a wardrobe
              // against adding a garment — not a preference they hold, and a
              // switch two screens away would be found by nobody standing over
              // a pile.
              Card(
                child: SwitchListTile(
                  value: state.onePerGarment,
                  onChanged: controller.setOnePerGarment,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  title: Text(
                    'One photo per garment',
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: const Text(
                    'For getting a whole wardrobe recorded. Each photo '
                    'becomes its own garment, so it is shoot, shoot, shoot — '
                    'no back, no label, no tap in between.',
                  ),
                ),
              ),
              const SizedBox(height: 8),

              SectionLabel(
                state.onePerGarment
                    ? 'Next garment'
                    : current.isEmpty
                    ? 'This garment'
                    : 'This garment · ${current.shots.length} '
                          '${current.shots.length == 1 ? 'photo' : 'photos'}',
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              ),
              if (state.onePerGarment)
                Text(
                  'Every photo is a garment. Add the backs and the care '
                  'labels later, whenever you get to them.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else if (current.isEmpty)
                Text(
                  'Take the front, the back if it differs, and the care label.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final (index, shot) in current.shots.indexed)
                      ShotTile(
                        compact: true,
                        shot: shot,
                        onRole: (role) => controller.setRole(index, role),
                        onCrop: () async {
                          final cropped = await showCropper(
                            context,
                            shot.image,
                          );
                          if (cropped != null) {
                            controller.replaceShot(index, cropped);
                          }
                        },
                      ),
                  ],
                ),
              if (current.hasCareTag) ...[
                const SizedBox(height: 12),
                NoteRow(
                  icon: Icons.check_circle_outline,
                  color: theme.colorScheme.primary,
                  bottomPadding: 0,
                  text:
                      'The care label is in here, so it will be read with '
                      'this garment.',
                ),
              ],
            ],
          ),
        ),
        ScanActionBar(
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
                  onPressed: controller.importAsGarments,
                  icon: const Icon(Icons.photo_library_outlined),
                  tooltip: 'Import photos — one garment each',
                ),
                const SizedBox(width: 4),
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
                  child: FilledButton.tonalIcon(
                    // Disabled with nothing in hand: an empty garment is
                    // one more thing to explain in the review list. Gone
                    // entirely in one-tap mode, where a photograph has
                    // already finished its garment and this would only
                    // ever say what just happened.
                    onPressed: current.isEmpty || state.onePerGarment
                        ? null
                        : controller.nextGarment,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Next garment'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: state.isEmpty ? null : controller.submit,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text('Submit ${state.garmentCount}'),
                  ),
                ),
              ],
            ),
          ],
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
            const IconBadge(Icons.auto_awesome_outlined),
            const SizedBox(height: 24),
            SizedBox(
              width: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: total == 0 ? null : finished / total,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('$finished of $total', style: theme.textTheme.titleLarge),
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
