/// Retaking a garment's photograph.
///
/// The review step here answers a narrower question than the first scan's. The
/// user already has an item; what they need to decide is whether the new
/// photograph's answer is better than the one they have. So this shows the
/// **difference** and nothing else — and says so plainly when there is none,
/// because "the new picture agreed with the old one" is a real outcome and
/// showing a full attribute list would bury it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../widgets/status_message.dart';
import 'retake_controller.dart';
import '../../widgets/back_navigation.dart';
import '../../widgets/state_view.dart';

class RetakeScreen extends ConsumerWidget {
  const RetakeScreen({required this.id, super.key});

  final ItemId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(retakeControllerProvider(id));
    final controller = ref.read(retakeControllerProvider(id).notifier);

    void back() {
      controller.reset();
      context.backOr('/item/${id.value}');
    }

    return LeaveScope(
      onLeave: controller.reset,
      child: Scaffold(
        appBar: AppBar(
          leading: backLeading(
            context,
            '/item/${id.value}',
            onLeave: controller.reset,
          ),
          title: const Text('Take a new photo'),
        ),
        body: switch (state) {
          RetakeIdle() => _Capture(controller: controller),
          RetakeIdentifying() => const LoadingView(
            title: 'Looking at the new photo…',
          ),
          RetakeReviewing() => _Review(state: state, controller: controller),
          RetakeSaved() => SuccessView(
            title: 'Updated',
            headingTitle: false,
            actions: [
              FilledButton(
                onPressed: back,
                child: const Text('Back to the item'),
              ),
            ],
          ),
          RetakeFailed(:final message, :final isRetryable) => _Failed(
            message: message,
            isRetryable: isRetryable,
            controller: controller,
          ),
        },
      ),
    );
  }
}

class _Capture extends StatelessWidget {
  const _Capture({required this.controller});

  final RetakeController controller;

  @override
  Widget build(BuildContext context) => IntroView(
    icon: Icons.add_a_photo_outlined,
    title: 'Photograph the garment',
    message:
        'Lay it flat on a plain surface that is not its own color. The '
        'background is what the app removes, so a busy or matching one '
        'is what makes a cutout go wrong.',
    note: 'Your old photo is kept.',
    actionsGap: 24,
    actions: [
      FilledButton.icon(
        onPressed: controller.captureAndIdentify,
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Take a photo'),
      ),
    ],
  );
}

class _Review extends StatelessWidget {
  const _Review({required this.state, required this.controller});

  final RetakeReviewing state;
  final RetakeController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changes = state.changes;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                changes.isEmpty
                    ? 'The new photo agrees with what was already recorded.'
                    : 'The new photo changes this much:',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                changes.isEmpty
                    ? 'Saving still replaces the picture and its cutout, which '
                          'is usually the point.'
                    : 'Anything you set by hand is kept as it is.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              for (final (label, was, now) in changes)
                _Change(label: label, was: was, now: now),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: controller.reset,
                  child: const Text('Try again'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: controller.save,
                  child: const Text('Use this photo'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Change extends StatelessWidget {
  const _Change({required this.label, required this.was, required this.now});

  final String label;
  final String was;
  final String now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          // Wrapped rather than a Row: "was" and "now" are both free text and
          // at a large text scale two of them side by side will not fit a
          // phone.
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                was,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              Icon(
                Icons.arrow_forward,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              Text(now, style: theme.textTheme.bodyMedium),
            ],
          ),
        ],
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
  final RetakeController controller;

  @override
  Widget build(BuildContext context) => StatusMessage(
    icon: Icons.error_outline,
    title: 'Could not read the new photo',
    detail: message,
    action: isRetryable
        ? TextButton(
            onPressed: controller.reset,
            child: const Text('Try again'),
          )
        : null,
  );
}
