/// Saying what you wore, in as few taps as the answer allows.
///
/// A grid rather than a list, because the question is one of recognition — you
/// are looking for the shirt you had on, and a picture answers that faster
/// than a name does. Everything is sized for a thumb at the end of a day: big
/// targets, no search to type into, no per-garment screen to open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/item_thumbnail.dart';
import '../../widgets/status_message.dart';
import 'worn_today_controller.dart';

class WornTodayScreen extends ConsumerWidget {
  const WornTodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wornTodayControllerProvider);
    final controller = ref.read(wornTodayControllerProvider.notifier);
    final theme = Theme.of(context);

    if (state.isDone) {
      return Scaffold(
        appBar: AppBar(title: const Text('Worn today')),
        body: StatusMessage(
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
      );
    }

    final chosen = state.selected.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Worn today')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              state.candidates.isEmpty
                  ? 'Nothing in the wardrobe to put in the basket.'
                  : 'Tap what you had on. The list reorders as you go — what '
                        'you usually wear together comes to the top.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              itemCount: state.candidates.length,
              itemBuilder: (context, index) {
                final candidate = state.candidates[index];
                return _Candidate(
                  candidate: candidate,
                  chosen: state.selected.contains(candidate.item.id),
                  onTap: () => controller.toggle(candidate.item.id),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: chosen == 0 || state.saving
                      ? null
                      : controller.commit,
                  icon: const Icon(Icons.local_laundry_service_outlined),
                  // Names both halves of what happens, because one of them is
                  // invisible: the garment moving is obvious, the wear being
                  // recorded is not, and it is the half that feeds cost per
                  // wear and everything downstream of it.
                  label: Text(
                    chosen == 0
                        ? 'Pick what you wore'
                        : chosen == 1
                        ? 'Log 1 and put it in the basket'
                        : 'Log $chosen and put them in the basket',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Candidate extends StatelessWidget {
  const _Candidate({
    required this.candidate,
    required this.chosen,
    required this.onTap,
  });

  final WornCandidate candidate;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = candidate.item;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: chosen
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: chosen ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: ItemThumbnail(item: item, size: 120),
                    ),
                  ),
                  if (chosen)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Icon(
                        Icons.check_circle,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              item.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: chosen
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
              ),
            ),
            // Only on the garments the co-wear graph lifted. A reason shown on
            // every tile would be noise; shown on the ones that just moved, it
            // is the difference between a helpful reorder and a list that
            // shuffles itself for no visible cause.
            if (candidate.wornWithPicked)
              Text(
                'usually worn together',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
