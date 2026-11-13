/// Worn today, from a mirror photo.
///
/// Take or pick one photo, and the app says what it thinks you are wearing for
/// you to confirm. Three groups, in words: what it is sure of (ticked), what it
/// is not sure of (shown, not ticked) and what it does not recognise (offered
/// as something to add).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../widgets/item_thumbnail.dart';
import '../../widgets/rinse_kit.dart';
import '../../widgets/state_view.dart';
import '../../widgets/status_message.dart';
import '../scan/scan_parts.dart';
import 'worn_today_photo_controller.dart';

class WornTodayPhotoScreen extends ConsumerWidget {
  const WornTodayPhotoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wornTodayPhotoControllerProvider);
    final controller = ref.read(wornTodayPhotoControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('From a photo')),
      body: switch (state.phase) {
        WornPhase.idle => _Start(controller: controller),
        WornPhase.scanning => LoadingView(
          title: 'Looking at what you have on…',
          detail: state.waking
              ? 'The server is waking up. This can take up to a minute the '
                    'first time.'
              : 'The photo goes to the scan server, with you in it.',
          heading: true,
          gap: 24,
        ),
        WornPhase.result => _Result(state: state, controller: controller),
        WornPhase.failed => StatusMessage(
          icon: Icons.error_outline,
          title: 'That did not work',
          detail: state.message ?? 'The photo could not be read.',
          action: state.isRetryable
              ? FilledButton(
                  onPressed: controller.reset,
                  child: const Text('Try another photo'),
                )
              : FilledButton.tonal(
                  onPressed: controller.reset,
                  child: const Text('Start again'),
                ),
        ),
        WornPhase.done => StatusMessage(
          icon: Icons.check_circle_outline,
          title: state.saved == 1
              ? '1 garment in the basket'
              : '${state.saved} garments in the basket',
          detail: 'Logged as worn today, and ready for the next wash.',
          action: FilledButton(
            onPressed: () => context.go('/laundry'),
            child: const Text('Done'),
          ),
        ),
      },
    );
  }
}

class _Start extends StatelessWidget {
  const _Start({required this.controller});

  final WornTodayPhotoController controller;

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
                  const IconBadge(Icons.checkroom_outlined, size: 112),
                  const SizedBox(height: 24),
                  Text(
                    'Show the app what you are wearing',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Take or pick one photo of you in your clothes. The app '
                    'finds each garment and matches it to your wardrobe, and '
                    'you confirm the list before anything is logged. The '
                    'photo goes to the scan server with you in it.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
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
                onPressed: controller.start,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take a photo'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => controller.start(fromGallery: true),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose a photo'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.state, required this.controller});

  final WornTodayPhotoState state;
  final WornTodayPhotoController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = state.selected.length;
    final sure = [
      for (final (i, s) in state.sightings.indexed)
        if (s.certainty == Certainty.sure) (i, s),
    ];
    final unsure = [
      for (final (i, s) in state.sightings.indexed)
        if (s.certainty == Certainty.unsure) (i, s),
    ];
    final none = state.unmatched;

    final names = [
      for (final i in state.selected.toList()..sort())
        if (state.sightings[i].item?.displayName case final String name) name,
    ];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ScanHeading(
                names.isEmpty
                    ? 'Nothing matched yet'
                    : "You're wearing: ${names.join(', ')}",
                body: 'Check the list. Only what is ticked is logged.',
              ),
              if (state.message case final String message) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              for (final (i, s) in sure)
                _MatchRow(
                  sighting: s,
                  ticked: state.selected.contains(i),
                  onToggle: () => controller.toggle(i),
                ),
              if (unsure.isNotEmpty) ...[
                const _GroupLabel('Not sure — is it one of these?'),
                for (final (i, s) in unsure)
                  _MatchRow(
                    sighting: s,
                    ticked: state.selected.contains(i),
                    onToggle: () => controller.toggle(i),
                  ),
              ],
              if (none.isNotEmpty) ...[
                const _GroupLabel('Not in your wardrobe — add it?'),
                for (final s in none)
                  _NewRow(
                    sighting: s,
                    onAdd: () async {
                      await controller.addToWardrobe(s);
                      if (!context.mounted) return;
                      await context.push('/scan/worn');
                      // Whatever was added is in the wardrobe now.
                      await controller.rematch();
                    },
                  ),
              ],
              if (state.sightings.isEmpty)
                Text('Nothing was found.', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        ScanActionBar(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: chosen == 0 || state.saving
                    ? null
                    : controller.confirm,
                icon: const Icon(Icons.local_laundry_service_outlined),
                label: Text(
                  chosen == 0
                      ? 'Tick what you wore'
                      : chosen == 1
                      ? 'Log 1 and put it in the basket'
                      : 'Log $chosen and put them in the basket',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.sighting,
    required this.ticked,
    required this.onToggle,
  });

  final Sighting sighting;
  final bool ticked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = sighting.item;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RinseCard(
        padding: const EdgeInsets.all(12),
        onTap: onToggle,
        child: Row(
          children: [
            Semantics(
              label: 'Wearing ${item?.displayName ?? 'this garment'}',
              child: Checkbox(value: ticked, onChanged: (_) => onToggle()),
            ),
            if (item != null)
              ClipRRect(
                borderRadius: context.rinse.tileBorderRadius,
                child: ItemThumbnail(item: item, size: 56),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item?.displayName ?? 'Unknown garment',
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    sighting.certainty == Certainty.sure
                        ? 'Matched to your wardrobe'
                        : 'Could be, but not sure',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
}

class _NewRow extends StatelessWidget {
  const _NewRow({required this.sighting, required this.onAdd});

  final Sighting sighting;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scan = sighting.detection.scan;
    final name = scan.suggestedName ?? scan.type.value.label;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RinseCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sighting.picture case final picture?) ...[
              ScanThumb(
                image: picture,
                size: 56,
                fit: BoxFit.contain,
                garmentRgb: scan.colors.value.colors.firstOrNull?.rgb,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    scan.type.value.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton(
                    onPressed: onAdd,
                    child: const Text('Add it to my wardrobe'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
