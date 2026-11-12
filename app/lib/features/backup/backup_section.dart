/// The Backup group on the settings screen.
///
/// Two buttons, a line saying when the last backup was made, and a quiet
/// nudge when there is a reason. The wardrobe lives only on this device (sync
/// is optional and off by default), and on an iPhone's home-screen web app
/// clearing site data takes it all, so this is the one safety net most people
/// have — which is why it says so plainly, once, rather than burying it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../widgets/rinse_kit.dart' show InsetPanel;
import 'backup_controller.dart';
import 'restore_dialogs.dart';

/// The explanation behind the Backup group's info button.
const backupInfo =
    'A backup is one file with everything you would miss: garments, photos, '
    'history, outfits, listings and your machine and sorting choices. It does '
    'not contain your sync token or server address, so sharing it never '
    'shares the key to a synced wardrobe.\n\n'
    'Restoring can merge it into what is here, which never deletes anything, '
    'or replace everything with it.';

/// How long ago, in the words the sync line uses.
String backupAgo(DateTime now, DateTime at) {
  final elapsed = now.difference(at);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} minutes ago';
  if (elapsed.inDays < 1) {
    final h = elapsed.inHours;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }
  final d = elapsed.inDays;
  return d == 1 ? 'yesterday' : '$d days ago';
}

class BackupSection extends ConsumerWidget {
  const BackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(backupControllerProvider);
    final last = ref.watch(lastBackupAtProvider);
    final garments = ref.watch(ownedCountProvider).valueOrNull ?? 0;

    final nudge = backupNudge(
      lastBackupAt: last,
      garmentsAtLastBackup: ref.watch(garmentsAtLastBackupProvider),
      garmentsNow: garments,
      now: DateTime.now(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              last == null ? Icons.shield_outlined : Icons.verified_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                last == null
                    ? 'No backup yet.'
                    : 'Last backup ${backupAgo(DateTime.now(), last)}.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        if (nudge != BackupNudge.none) ...[
          const SizedBox(height: 8),
          Text(
            switch (nudge) {
              BackupNudge.neverBackedUp =>
                'Your wardrobe lives only on this device. If its storage or '
                    "the browser's site data is cleared, it is gone. One tap "
                    'below keeps a copy.',
              _ =>
                'Your wardrobe has grown since the last backup, which is over '
                    'a month old.',
            },
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.rinse.textAccent,
            ),
          ),
        ],
        const SizedBox(height: 12),
        // Stacked rather than side by side: at 320 px and large text two
        // labelled buttons do not share a row.
        FilledButton.icon(
          onPressed: state.busy
              ? null
              : () => ref.read(backupControllerProvider.notifier).save(),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Save a backup'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: state.busy ? null : () => _restore(context, ref),
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Restore from a backup'),
        ),
        if (state.busy) ...[
          const SizedBox(height: 12),
          _Progress(state: state),
        ],
        if (state.notice case final notice?) ...[
          const SizedBox(height: 12),
          _Notice(notice: notice),
        ],
      ],
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(backupControllerProvider.notifier);

    final chosen = await controller.choose();
    if (chosen == null || !context.mounted) return;

    final previews = await controller.previews(chosen.backup);
    final current = await controller.currentCounts();
    if (!context.mounted) return;

    final mode = await showDialog<RestoreMode>(
      context: context,
      builder: (_) => RestoreChoiceDialog(
        backup: chosen.backup,
        fileName: chosen.fileName,
        previews: previews,
      ),
    );
    if (mode == null || !context.mounted) return;

    if (mode == RestoreMode.replace) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (_) => ReplaceConfirmDialog(
          backup: chosen.backup,
          current: current,
          plan: previews[RestoreMode.replace]!,
        ),
      );
      if (sure != true || !context.mounted) return;
    }

    await controller.restore(chosen.backup, mode);
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state});

  final BackupState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = state.total > 0 ? ' ${state.done} of ${state.total}' : '';

    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: state.fraction),
          const SizedBox(height: 6),
          Text(
            '${state.stage ?? 'Working…'}$count',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends ConsumerWidget {
  const _Notice({required this.notice});

  final BackupNotice notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = notice.isError ? scheme.error : context.rinse.textAccent;

    return InsetPanel(
      tint: notice.isError
          ? scheme.errorContainer.withValues(alpha: 0.4)
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            notice.isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (notice.detail case final detail?) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
