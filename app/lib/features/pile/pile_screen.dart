/// Photograph a pile, get the loads to run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/settings.dart';
import 'pile_controller.dart';
import 'widgets/load_card.dart';

class PileScreen extends ConsumerWidget {
  const PileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pileControllerProvider);
    final controller = ref.read(pileControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            controller.reset();
            context.go('/');
          },
        ),
        title: const Text('Sort the laundry'),
      ),
      body: switch (state) {
        PileIdle() => _Capture(controller: controller),
        PileAnalysing() => const _Analysing(),
        PilePlanned() => _Plan(state: state, controller: controller),
        PileFailed(:final message, :final isRetryable) => _Failed(
          message: message,
          isRetryable: isRetryable,
          controller: controller,
        ),
      },
    );
  }
}

class _Capture extends ConsumerWidget {
  const _Capture({required this.controller});

  final PileController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final washer = ref.watch(washerProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_laundry_service_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text('Photograph the pile', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Spread it out so each item is visible. Anything the app already '
              'knows will be recognised, and its care label used instead of a '
              'guess from a crumpled sleeve.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: controller.captureAndPlan,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Take a photo'),
            ),
            if (washer == null) ...[
              const SizedBox(height: 24),
              // Not a blocker. The plan is still useful without a machine — it
              // just states requirements rather than naming a programme — and
              // putting a settings screen between someone and their first
              // answer is how an app gets deleted.
              TextButton(
                onPressed: () => context.go('/settings'),
                child: const Text('Set your machine to get exact programmes'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Analysing extends StatelessWidget {
  const _Analysing();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          'Finding the clothes…',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}

class _Plan extends ConsumerWidget {
  const _Plan({required this.state, required this.controller});

  final PilePlanned state;
  final PileController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = state.plan;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(switch (plan.loadCount) {
          0 => 'Nothing can be sorted yet',
          1 => 'One load',
          _ => '${plan.loadCount} loads',
        }, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          _summary(state),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        if (state.obscuredCount > 0) ...[
          const SizedBox(height: 12),
          _Notice(
            icon: Icons.layers_outlined,
            // Said plainly. Planning for what was visible and staying quiet
            // about the rest sends someone to the machine with a load that is
            // missing items they meant to wash.
            text: state.obscuredCount == 1
                ? 'One more garment was visible but too buried to identify. '
                      'Reshuffle the pile and scan again to include it.'
                : '${state.obscuredCount} more garments were visible but too '
                      'buried to identify. Reshuffle the pile and scan again '
                      'to include them.',
          ),
        ],

        if (ref.watch(washerProvider) == null) ...[
          const SizedBox(height: 12),
          _Notice(
            icon: Icons.settings_outlined,
            text:
                'No machine is set, so these say what each load needs rather '
                'than which programme to select.',
            onTap: () => context.go('/settings'),
          ),
        ],

        if (plan.loads.isEmpty && plan.actionable.isNotEmpty) ...[
          const SizedBox(height: 16),
          _NothingSortable(count: plan.actionable.length),
        ],

        const SizedBox(height: 20),
        for (final load in plan.loads) ...[
          LoadCard(load: load),
          const SizedBox(height: 12),
        ],

        if (plan.unassigned.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Unassigned(items: plan.unassigned),
        ],

        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: controller.reset,
          child: const Text('Scan another pile'),
        ),
      ],
    );
  }

  String _summary(PilePlanned state) {
    final parts = <String>[
      '${state.detections.length} items found',
      if (state.recognisedCount > 0)
        '${state.recognisedCount} recognised from your wardrobe',
      if (state.unrecognisedCount > 0) '${state.unrecognisedCount} new',
    ];
    return parts.join(' · ');
  }
}

/// Items the sorter deliberately left out, each with its reason.
///
/// Shown rather than dropped. An item silently missing from the plan is one
/// the user will find still dirty later, and the reasons are actionable —
/// usually "scan its care label".
class _Unassigned extends StatelessWidget {
  const _Unassigned({required this.items});

  final List<UnassignedItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Left out', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final entry in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${entry.item.displayName} — ${entry.reason}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Why a pile of clothes produced no loads.
///
/// The sorter refuses to place an item whose care it is only guessing at, and
/// a garment seen once in a heap is exactly that. That refusal is the whole
/// point of the system — sorting anyway would put a hot cotton cycle under
/// something that might be wool — but presented as an empty screen it reads as
/// the app being broken.
///
/// So it is stated as what it is: a thing the app does not know yet, with the
/// specific action that fixes it.
class _NothingSortable extends StatelessWidget {
  const _NothingSortable({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == 1
                  ? 'One garment needs identifying first'
                  : 'These $count garments need identifying first',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'A garment seen once in a heap is a guess, and the app will not '
              'put a load together on a guess — that is how a jumper gets '
              'shrunk. Add each one properly, or scan its care label, and it '
              'will be recognised in every pile after that.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => context.go('/scan'),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add a garment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.message,
    required this.isRetryable,
    required this.controller,
  });

  final String message;
  final bool isRetryable;
  final PileController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: controller.reset,
              child: Text(isRetryable ? 'Try again' : 'Take another photo'),
            ),
          ],
        ),
      ),
    );
  }
}
