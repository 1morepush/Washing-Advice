/// "Use an earlier version": the way back if a release does not work for you.
///
/// Every recent release stays published beside the newest one. This lists
/// them, says which the data on this phone can still be opened by, and moves
/// to the one chosen. It sits under "Check for updates" because it is the same
/// kind of thing — which build of the app is this phone running — and the
/// answer to "the new version broke something" the update button cannot give.
///
/// Written to be read at 320 px and 1.6x text: every row is a stacked column
/// of wrapping lines, with the action under the words and never beside them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data_format.dart';
import '../../core/version_switch.dart';
import 'patch_notes.dart';
import 'setting_info.dart';

/// The browser's way of switching. Overridden in tests with one that records
/// what it was asked to do instead of navigating anywhere.
final versionSwitcherProvider = Provider<VersionSwitcher>(
  (ref) => createVersionSwitcher(),
);

/// What `versions.json` says, read fresh each time the section is shown and
/// when "Try again" is tapped. A failure is a value the section words, not an
/// error that escapes: being offline is ordinary on a phone.
final siteVersionsProvider = FutureProvider.autoDispose<SiteVersions>(
  (ref) => ref.watch(versionSwitcherProvider).fetchVersions(),
);

/// The explanation behind the section's info button.
const earlierVersionsInfo =
    'If a new version does not work for you, you can go back to an earlier '
    'one. Your wardrobe, photos and settings stay where they are: every '
    'version reads the same ones.\n\n'
    'The app stays on the version you choose, including when you open it '
    'from the home screen, until you tap Back to latest at the top of the '
    'screen. Going back does not undo anything you added or changed, and a '
    'version that is older than the format your wardrobe is now saved in is '
    'not offered, because it could not open it.';

class EarlierVersionsSection extends ConsumerWidget {
  const EarlierVersionsSection({this.running, super.key});

  /// The version that is open. The newest release note unless a test says
  /// otherwise: a test asserts that note matches `pubspec.yaml`.
  final String? running;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final switcher = ref.watch(versionSwitcherProvider);
    if (!switcher.available) return const SizedBox.shrink();

    final current = running ?? patchNotes.first.version;
    final versions = ref.watch(siteVersionsProvider);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TitleWithInfo(
          'Use an earlier version',
          style: theme.textTheme.titleMedium,
          info: earlierVersionsInfo,
        ),
        const SizedBox(height: 4),
        Text('You are using $current.', style: muted),
        const SizedBox(height: 12),
        switch (versions) {
          AsyncData(:final value) => _List(
            versions: value.olderThan(current),
            stored: switcher.storedFormat,
            onChoose: (version) => _confirm(context, switcher, version),
          ),
          AsyncError() => _Unavailable(
            onRetry: () => ref.invalidate(siteVersionsProvider),
          ),
          _ => Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text('Looking for earlier versions…', style: muted),
              ),
            ],
          ),
        },
      ],
    );
  }

  Future<void> _confirm(
    BuildContext context,
    VersionSwitcher switcher,
    SiteVersion version,
  ) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Use ${version.version}?'),
        content: SingleChildScrollView(
          child: Text(
            '${version.version}, ${version.name}, from '
            '${formatLongDate(version.date)}.\n\n'
            'The app will reopen as that version and stay on it, even when '
            'you open it from the home screen, until you tap Back to latest '
            'at the top of the screen.\n\n'
            'Your wardrobe, photos and settings are kept. Going back does '
            'not undo anything you have added or changed, and the earlier '
            'version will not know about features that came after it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Use ${version.version}'),
          ),
        ],
      ),
    );
    if (go == true) await switcher.switchTo(version.version);
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.versions,
    required this.stored,
    required this.onChoose,
  });

  final List<SiteVersion> versions;
  final DataFormat? stored;
  final void Function(SiteVersion) onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (versions.isEmpty) {
      return Text(
        'Earlier versions appear here after the next update.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final version in versions) ...[
          _Row(
            version: version,
            reason: whyUnreadable(
              version: version.version,
              build: version.dataFormat,
              stored: stored,
            ),
            onChoose: () => onChoose(version),
          ),
          if (version != versions.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.version,
    required this.reason,
    required this.onChoose,
  });

  final SiteVersion version;

  /// Why this one cannot be opened, or null when it can.
  final String? reason;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${version.version} · ${version.name}',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(formatLongDate(version.date), style: muted),
        const SizedBox(height: 4),
        OutlinedButton(
          // Present but dead when the data has outgrown this version, so the
          // list still shows what exists and the sentence below says why not.
          onPressed: reason == null ? onChoose : null,
          child: Text('Use ${version.version}'),
        ),
        if (reason case final reason?) ...[
          const SizedBox(height: 4),
          Text(reason, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Earlier versions could not be listed just now. They need a '
          'connection.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
