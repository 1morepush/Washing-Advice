/// A way to get past a stale service worker, on the settings screen.
///
/// A saved-to-home-screen PWA is the one place a new deployment can silently
/// fail to reach the person using it, and the fix people reach for — delete
/// the icon, reopen in Safari, save it again — is this button instead.
/// Whether it belongs on screen at all (only where there is a service worker
/// to clear) is for whoever composes the settings screen to decide, not this
/// widget — see the `kIsWeb` check around its one call site.
library;

import 'package:flutter/material.dart';

import '../../core/app_updater.dart';

class UpdateSection extends StatefulWidget {
  const UpdateSection({super.key});

  @override
  State<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<UpdateSection> {
  bool _updating = false;

  Future<void> _check() async {
    setState(() => _updating = true);
    await forceAppUpdate();
    // On the web this line is never reached — forceAppUpdate() ends in a
    // page reload. It only runs at all on a platform where that call was a
    // no-op, so there is nothing left to wait for.
    if (mounted) setState(() => _updating = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('App updates', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          'If the app looks outdated after a change, use this instead of '
          'deleting and re-adding the home screen icon — it clears what the '
          'browser cached and reloads.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _updating ? null : _check,
              icon: const Icon(Icons.refresh),
              label: const Text('Check for updates'),
            ),
            const SizedBox(width: 12),
            if (_updating)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ],
    );
  }
}
