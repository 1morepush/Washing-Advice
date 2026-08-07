/// The sync controls, on the settings screen.
///
/// Deliberately blunt about what the credential is. A token that cannot be
/// recovered and cannot be revoked is unusual enough that leaving someone to
/// discover it is a way of losing their wardrobe — so the screen says it in
/// plain words at the point where they would otherwise assume an account.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/settings.dart';
import 'sync_controller.dart';

class SyncSection extends ConsumerStatefulWidget {
  const SyncSection({super.key});

  @override
  ConsumerState<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<SyncSection> {
  late final TextEditingController _token = TextEditingController(
    text: ref.read(syncTokenProvider) ?? '',
  );
  bool _revealed = false;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sync between devices', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          'Optional. Everything works without it — sync copies your wardrobe '
          'between your own devices through the same server that does the '
          'scanning.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _token,
          obscureText: !_revealed,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Sync token',
            hintText: 'Paste an existing token, or generate one',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _revealed = !_revealed),
              icon: Icon(_revealed ? Icons.visibility_off : Icons.visibility),
              tooltip: _revealed ? 'Hide' : 'Show',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: () async {
                await controller.setToken(_token.text);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sync token saved.')),
                );
              },
              child: const Text('Save'),
            ),
            OutlinedButton(
              onPressed: () {
                // Generated here rather than issued by the server: there is no
                // registration step to fail, and no list of users to leak.
                final generated = SyncController.generateToken();
                setState(() {
                  _token.text = generated;
                  _revealed = true;
                });
              },
              child: const Text('Generate'),
            ),
            if (state is! SyncOff)
              TextButton(
                onPressed: state is SyncRunning ? null : controller.run,
                child: const Text('Sync now'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _Status(state: state),
        const SizedBox(height: 12),
        _Warning(),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.state});

  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, text, color) = switch (state) {
      SyncOff() => (
        Icons.cloud_off_outlined,
        'Not set up. Your wardrobe stays on this device.',
        theme.colorScheme.onSurfaceVariant,
      ),
      SyncIdle(:final lastSyncedAt) => (
        Icons.cloud_queue,
        lastSyncedAt == null
            ? 'Ready. Nothing has been synced yet.'
            : 'Last synced ${_ago(lastSyncedAt)}.',
        theme.colorScheme.onSurfaceVariant,
      ),
      SyncRunning() => (
        Icons.sync,
        'Syncing…',
        theme.colorScheme.onSurfaceVariant,
      ),
      SyncDone(:final report) => (
        Icons.cloud_done_outlined,
        _summarise(report),
        theme.colorScheme.primary,
      ),
      SyncFailed(:final message, :final isRetryable) => (
        Icons.cloud_off_outlined,
        isRetryable ? '$message It will be retried.' : message,
        theme.colorScheme.error,
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// What a run actually did, rather than a bare tick.
///
/// Conflicts are named because they are the interesting case: two devices
/// disagreed and the app chose, and someone who has just watched a field
/// change deserves to know why rather than suspecting a bug.
String _summarise(SyncReport report) {
  final parts = <String>[];
  if (report.pulled > 0) parts.add('${report.pulled} received');
  if (report.pushed > 0) parts.add('${report.pushed} sent');
  if (report.hadConflicts) {
    final count = report.merged.length;
    parts.add('$count reconciled by which source was more reliable');
  }
  return parts.isEmpty ? 'Already up to date.' : 'Synced: ${parts.join(', ')}.';
}

String _ago(DateTime at) {
  final elapsed = DateTime.now().difference(at);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} minutes ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours} hours ago';
  return '${elapsed.inDays} days ago';
}

class _Warning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.key_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              // Said before it matters, not after. This is the whole security
              // model, and it is unusual enough that assuming an account is
              // the natural mistake.
              'This token is the only key to your synced wardrobe. There is no '
              'password and no recovery: anyone who has it can read your '
              'wardrobe, and losing it means losing the copy on the server. '
              'Keep it somewhere you keep passwords, and use the same token on '
              'each of your devices.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
