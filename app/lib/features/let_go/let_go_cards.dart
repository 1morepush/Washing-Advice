/// The two places the suggestion is quietly mentioned: Insights and Sell.
///
/// Each is nothing at all when there is nothing to say — no empty card, no
/// "0 things" — and neither says what to do. They say what is so, and offer to
/// show it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../widgets/rinse_kit.dart';
import 'let_go_providers.dart';

/// Where the list is.
const letGoRoute = '/sell/unworn';

/// A card in Insights, after the figures it follows from.
class LetGoInsightsCard extends ConsumerWidget {
  const LetGoInsightsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(letGoProvider).valueOrNull?.length ?? 0;
    if (count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    // Brings its own gap below, so that when there is nothing to say there is
    // no stray space where the card would have been.
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Not worn in a year',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${letGoHeadline(count)}. If any of it is ready to go to '
                'someone who will wear it, you can list it for sale from here. '
                'Nothing is decided for you.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => context.push(letGoRoute),
                child: const Text('See them'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line on the Sell tab, above the list or the empty state's buttons.
class LetGoSellLine extends ConsumerWidget {
  const LetGoSellLine({
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 4),
    super.key,
  });

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(letGoProvider).valueOrNull?.length ?? 0;
    if (count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final rinse = context.rinse;
    return Padding(
      padding: margin,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: () => context.push(letGoRoute),
          borderRadius: rinse.tileBorderRadius,
          child: InsetPanel(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        letGoHeadline(count),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'See them',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: rinse.textAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
