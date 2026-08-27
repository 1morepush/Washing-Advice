/// How much the sorter is allowed to combine.
///
/// Two questions, kept together because the answer people actually hold in
/// their head is the pair: wash together or apart, dry together or apart. Put
/// on opposite ends of a settings screen they would read as two unrelated
/// switches, and the combination — the thing being chosen — would never appear
/// anywhere.
///
/// Both only ever *separate*. Neither can talk the sorter into combining
/// something it held apart, because those were held apart to stop a white
/// shirt coming out pink, and a preference is not evidence about dye.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';

class SortingSection extends ConsumerWidget {
  const SortingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final separateWashing = ref.watch(separateWashingProvider);
    final splitDrying = ref.watch(splitDryingProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Washing and drying', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          'How far the app goes in putting clothes in the same load. Neither '
          'of these can put two things together that should be kept apart — '
          'they only ever separate more.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),

        SwitchListTile(
          value: separateWashing,
          onChanged: (on) async {
            await ref.read(settingsStoreProvider).setSeparateWashing(on);
            ref.read(separateWashingProvider.notifier).state = on;
          },
          contentPadding: EdgeInsets.zero,
          title: const Text('Wash each colour separately'),
          subtitle: const Text(
            'Off, colours that do not conflict share a drum — lights with '
            'brights — which is fewer, fuller loads. On, each colour washes on '
            'its own: more loads and more water, and no argument about it.',
          ),
        ),

        SwitchListTile(
          value: splitDrying,
          onChanged: (on) async {
            await ref.read(settingsStoreProvider).setSplitDrying(on);
            ref.read(splitDryingProvider.notifier).state = on;
          },
          contentPadding: EdgeInsets.zero,
          title: const Text('Split a load for drying'),
          subtitle: const Text(
            'Clothes that wash together do not always dry together. Off, a '
            'load dries as one and a single hang-dry garment sends the whole '
            'lot to the airer. On, the rest goes in the dryer and you sort '
            'them once.',
          ),
        ),

        const SizedBox(height: 12),
        // The combination, spelled out. Built from two halves rather than
        // written out four times, so a reworded switch cannot leave the
        // summary describing the old behaviour.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            sortingSummary(
              separateWashing: separateWashing,
              splitDrying: splitDrying,
            ),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// One sentence naming which of the four combinations is in force.
///
/// Public and pure so a test can pin all four without building a screen.
String sortingSummary({
  required bool separateWashing,
  required bool splitDrying,
}) {
  final washing = separateWashing
      ? 'Each colour washes on its own'
      : 'Colours that do not conflict wash together';
  final drying = splitDrying
      ? 'a load splits so whatever can be tumble dried is'
      : 'each load dries as one';
  return '$washing, and $drying.';
}
