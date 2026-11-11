/// The two questions a restore asks: how to apply it, and "are you sure".
///
/// Both say what will happen in numbers, taken from the same plan the restore
/// then follows, so what the dialog promised and what was done cannot differ.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `3 Nov 2026, 10:15`, in the viewer's own time.
String whenMade(DateTime at) {
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]} ${local.year}, '
      '${two(local.hour)}:${two(local.minute)}';
}

/// "adds 12 garments, updates 3" for a merge.
String _mergeSummary(RestorePlan plan) {
  String n(int c, String noun) => '$c $noun';
  final bits = <String>[
    if (plan.itemCounts.added > 0)
      'add ${n(plan.itemCounts.added, plan.itemCounts.added == 1 ? 'garment' : 'garments')}',
    if (plan.itemCounts.updated > 0)
      'update ${n(plan.itemCounts.updated, plan.itemCounts.updated == 1 ? 'garment' : 'garments')}',
    if (plan.eventCounts.added > 0)
      'add ${n(plan.eventCounts.added, plan.eventCounts.added == 1 ? 'history entry' : 'history entries')}',
    if (plan.outfitCounts.added + plan.outfitCounts.updated > 0)
      'bring ${n(plan.outfitCounts.added + plan.outfitCounts.updated, 'outfits')}',
    if (plan.listingCounts.added + plan.listingCounts.updated > 0)
      'bring ${n(plan.listingCounts.added + plan.listingCounts.updated, 'listings')}',
  ];
  if (bits.isEmpty) return 'Nothing new: this wardrobe already has all of it.';
  final text = bits.join(', ');
  return 'Would $text.';
}

class RestoreChoiceDialog extends StatefulWidget {
  const RestoreChoiceDialog({
    required this.backup,
    required this.fileName,
    required this.previews,
    super.key,
  });

  final OpenedBackup backup;
  final String fileName;
  final Map<RestoreMode, RestorePlan> previews;

  @override
  State<RestoreChoiceDialog> createState() => _RestoreChoiceDialogState();
}

class _RestoreChoiceDialogState extends State<RestoreChoiceDialog> {
  RestoreMode _mode = RestoreMode.merge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manifest = widget.backup.manifest;
    final merge = widget.previews[RestoreMode.merge]!;

    return AlertDialog(
      title: const Text('Restore this backup?'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.fileName,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Made ${whenMade(manifest.createdAt)}, by version '
            '${manifest.appVersion}.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Holds ${manifest.counts.summary} '
            '(${backupSizeLabel(widget.backup.sizeInBytes)}).',
            style: theme.textTheme.bodyMedium,
          ),
          if (manifest.counts.missingImages > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${manifest.counts.missingImages} photos were already missing '
              'when it was made.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          RadioGroup<RestoreMode>(
            groupValue: _mode,
            onChanged: (value) => setState(() => _mode = value ?? _mode),
            child: Column(
              children: [
                RadioListTile<RestoreMode>(
                  value: RestoreMode.merge,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Merge (recommended)'),
                  subtitle: Text(
                    'Adds what is missing and keeps the newer copy of '
                    'anything in both. Deletes nothing. A garment you '
                    'deleted since then stays deleted.\n'
                    '${_mergeSummary(merge)}',
                  ),
                ),
                const RadioListTile<RestoreMode>(
                  value: RestoreMode.replace,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Replace everything'),
                  subtitle: Text(
                    'Makes this wardrobe exactly the backup. Asks again '
                    'before doing it.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _mode),
          child: Text(_mode == RestoreMode.merge ? 'Merge' : 'Continue'),
        ),
      ],
    );
  }
}

/// The second, explicit confirmation before anything is lost.
class ReplaceConfirmDialog extends StatelessWidget {
  const ReplaceConfirmDialog({
    required this.backup,
    required this.current,
    required this.plan,
    super.key,
  });

  final OpenedBackup backup;

  /// What is on the phone now.
  final BackupCounts current;
  final RestorePlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lost = plan.itemCounts.removed;

    return AlertDialog(
      title: const Text('Replace everything?'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This wardrobe has ${current.summary}. All of it will be deleted '
            'and replaced by the backup: ${backup.manifest.counts.summary}, '
            'made ${whenMade(backup.manifest.createdAt)}.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            [
              if (lost > 0)
                '$lost ${lost == 1 ? 'garment is' : 'garments are'} here and '
                    'not in the backup, and will be lost.',
              'Anything changed since the backup is lost too. This cannot be '
                  'undone.',
            ].join(' '),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'If in doubt, cancel and save a backup of this wardrobe first.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Replace everything'),
        ),
      ],
    );
  }
}
