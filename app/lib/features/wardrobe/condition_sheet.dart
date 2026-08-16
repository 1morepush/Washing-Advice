/// Photographing a garment to see whether it has worn.
///
/// The screen's whole job is to be easy to say no to. Everything on it is a
/// claim a model made about a garment the user is holding, and each one, if
/// accepted, changes how that garment is washed from the next load onward. So
/// every finding is confirmed on its own, the reason to accept it is stated
/// before the button that does, and where to look is printed beside it — a
/// report of pilling with nowhere to look is one nobody can check.
///
/// "Nothing to report" is drawn as a real answer rather than as an empty list.
/// Most garments are fine, and a panel that went blank on the commonest
/// outcome would read as a feature that had failed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import 'condition_controller.dart';

Future<void> showConditionSheet(BuildContext context, WardrobeItem item) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConditionSheet(item: item),
    );

class _ConditionSheet extends ConsumerWidget {
  const _ConditionSheet({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = conditionControllerProvider(item.id);

    Future<void> look() async {
      final images = await ref.read(imageCaptureProvider).pickMultiple();
      if (images.isEmpty) return;
      await ref.read(controller.notifier).look(images);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Check for wear', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            item.displayName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: switch (ref.watch(controller)) {
                ConditionIdle() => _Intro(onLook: look),
                ConditionLooking() => const _Looking(),
                ConditionFailed(:final message, :final isRetryable) => _Failed(
                  message: message,
                  onRetry: isRetryable ? look : null,
                ),
                final ConditionRead read => _Found(
                  read: read,
                  onAccept: ref.read(controller.notifier).accept,
                  onDismiss: ref.read(controller.notifier).dismiss,
                  onLookAgain: look,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onLook});

  final Future<void> Function() onLook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          // Saying where to point the camera, because it is the one thing the
          // user controls that decides whether the answer is any good. Wear
          // collects where a garment rubs, and none of those places are in the
          // photograph somebody takes by default.
          'Photograph the places a garment wears: cuffs, elbows, underarms, '
          'the seat, the hem. More angles read better than one good one.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onLook,
          icon: const Icon(Icons.photo_camera_outlined, size: 18),
          label: const Text('Take photos'),
        ),
        const SizedBox(height: 8),
        Text(
          'Nothing is recorded until you say so.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Looking extends StatelessWidget {
  const _Looking();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text('Looking it over…', style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, this.onRetry});

  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        if (onRetry case final Future<void> Function() retry) ...[
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: retry, child: const Text('Try again')),
        ],
      ],
    );
  }
}

class _Found extends StatelessWidget {
  const _Found({
    required this.read,
    required this.onAccept,
    required this.onDismiss,
    required this.onLookAgain,
  });

  final ConditionRead read;
  final Future<void> Function(NoticedWear) onAccept;
  final void Function(NoticedWear) onDismiss;
  final Future<void> Function() onLookAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (read.found.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Nothing to report',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            read.setAside == 0
                ? 'It looked this garment over and found nothing worth '
                      'recording. That is the usual answer.'
                // Said rather than hidden. Somebody who can see a hole and is
                // told nothing was found deserves to know the app saw
                // something and was not sure enough to say — otherwise it
                // looks blind rather than careful.
                : 'Nothing it was sure enough about. It set aside '
                      '${read.setAside} thing${read.setAside == 1 ? '' : 's'} '
                      'it could not make out clearly — a closer photograph of '
                      'the same place may settle it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onLookAgain,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('Take more photos'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Check each of these against the garment.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final wear in read.found)
          _Finding(
            wear: wear,
            onAccept: () => onAccept(wear),
            onDismiss: () => onDismiss(wear),
          ),
      ],
    );
  }
}

/// One claim, with what accepting it would do.
class _Finding extends StatelessWidget {
  const _Finding({
    required this.wear,
    required this.onAccept,
    required this.onDismiss,
  });

  final NoticedWear wear;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${wear.severity.label} ${wear.type.label.toLowerCase()}',
              style: theme.textTheme.titleSmall,
            ),
            if (wear.observed.note case final String note) ...[
              const SizedBox(height: 2),
              // Where to look. The whole difference between a claim somebody
              // can check in two seconds and one they can only take on trust.
              Text(
                note,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (wear.changesCare) ...[
              const SizedBox(height: 8),
              // Stated before the button that does it. "Your jumper is
              // pilling" is a remark; "and it will be washed more gently from
              // now on" is a decision, and asking for one without saying so is
              // exactly the surprise this app exists to avoid.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.local_laundry_service_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recording this will wash it cooler and gentler from '
                      'now on, and stop it being tumble dried.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  child: const Text('Not there'),
                ),
                FilledButton.tonal(
                  onPressed: onAccept,
                  child: const Text('Record it'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
