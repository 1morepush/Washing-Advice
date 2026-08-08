/// What the wardrobe adds up to.
///
/// Every figure here comes from `WardrobeSummary` in the core. The screen
/// arranges and phrases them; it computes nothing, because a statistic
/// calculated in a widget is a statistic that will disagree with the same one
/// on another screen.
///
/// Ordered by what someone can act on. Readiness comes first because it says
/// whether the app's main feature will work for them today, and the leaderboards
/// come last because they are interesting rather than useful.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/app_drawer.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(wardrobeSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      drawer: const AppDrawer(current: AppDestination.insights),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (data) => data.isEmpty
            ? const _Empty()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _Readiness(summary: data),
                  const SizedBox(height: 16),
                  _Totals(summary: data),
                  const SizedBox(height: 16),
                  _Breakdown(
                    title: 'What it is made of',
                    subtitle:
                        'Counted per garment. A cotton–polyester blend is in '
                        'both rows.',
                    tallies: [
                      for (final tally in data.byFiber.take(6))
                        (label: tally.key.label, tally: tally),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Breakdown(
                    title: 'The piles it sorts into',
                    subtitle: 'Which loads your wardrobe naturally makes.',
                    tallies: [
                      for (final tally in data.byColorClass)
                        (label: tally.key.label, tally: tally),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Breakdown(
                    title: 'By category',
                    subtitle: null,
                    tallies: [
                      for (final tally in data.byCategory.take(8))
                        (label: tally.key.label, tally: tally),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Neglected(summary: data),
                  const SizedBox(height: 16),
                  _Value(summary: data),
                ],
              ),
      ),
    );
  }
}

/// The headline: can the app actually do its job for this wardrobe?
class _Readiness extends StatelessWidget {
  const _Readiness({required this.summary});

  final WardrobeSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (summary.readiness * 100).round();
    final outstanding = summary.needingCareTagScan.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ready to sort', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$percent%',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      outstanding == 0
                          ? 'Every washable item has a care label the app '
                                'trusts.'
                          : '$outstanding ${outstanding == 1 ? 'item is' : 'items are'} '
                                'still a guess. Scanning their labels is what '
                                'turns a pile photo into a load.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: summary.readiness,
                minHeight: 8,
              ),
            ),
            if (outstanding > 0) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.go(
                    '/item/${summary.needingCareTagScan.first.id.value}/care-label',
                  ),
                  child: const Text('Scan the next label'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.summary});

  final WardrobeSummary summary;

  @override
  Widget build(BuildContext context) {
    final spend = summary.totalSpend;

    return Column(
      children: [
        // `IntrinsicHeight` so the three cards are one band rather than three
        // cards of different heights sitting on a shared centre line. Only one
        // of these labels wraps — "wears recorded" — and left alone that card
        // grew taller than the two beside it and the row read as misaligned.
        //
        // It is what makes `stretch` legal here: this row is inside a
        // `ListView`, so its height is unbounded, and stretching against an
        // unbounded cross axis is an error rather than a layout.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Stat(value: '${summary.itemCount}', label: 'items'),
              const SizedBox(width: 12),
              _Stat(value: '${summary.totalWears}', label: 'wears recorded'),
              const SizedBox(width: 12),
              _Stat(value: '${summary.totalWashes}', label: 'washes'),
            ],
          ),
        ),
        // Spend gets its own row rather than a fourth column. Per currency and
        // never converted — a total built on an invented exchange rate is
        // worse than none because it looks like an answer — which means the
        // number of figures is not fixed, and squeezing them into a quarter of
        // a phone's width truncated the one wardrobe with two currencies in it.
        if (spend.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              // The gap goes *between* the cards, not after each one. Trailing
              // it left the row a gap short of the right edge, so a single
              // currency — which is the usual case — sat visibly narrower than
              // every other card on the screen.
              for (final (index, entry) in spend.entries.indexed) ...[
                if (index > 0) const SizedBox(width: 12),
                _Stat(
                  value: '${(entry.value / 100).round()} ${entry.key}',
                  label: 'spent',
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _Row = ({String label, Tally<Object?> tally});

class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.title,
    required this.subtitle,
    required this.tallies,
  });

  final String title;
  final String? subtitle;
  final List<_Row> tallies;

  @override
  Widget build(BuildContext context) {
    if (tallies.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle case final String text) ...[
              const SizedBox(height: 4),
              Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            for (final row in tallies) ...[
              _Bar(label: row.label, tally: row.tally),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.tally});

  final String label;
  final Tally<Object?> tally;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              '${tally.count}  ·  ${(tally.share * 100).round()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            // Shares are of the wardrobe, so a fibre in every garment fills the
            // bar and one in a third fills a third — comparable across rows
            // even when the counts add to more than the item count.
            value: tally.share.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _Neglected extends StatelessWidget {
  const _Neglected({required this.summary});

  final WardrobeSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final never = summary.neverWorn;
    final idle = summary.idleFor(90);

    if (never.isEmpty && idle.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Not being worn', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              // Two different problems, kept apart: one is a purchase to learn
              // from, the other a garment doing its job seasonally.
              'Never worn is a different question from not worn lately.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (never.isNotEmpty) ...[
              _SubHeading('Never worn (${never.length})'),
              for (final item in never.take(5))
                _ItemRow(item: item, trailing: 'not once'),
            ],
            if (idle.isNotEmpty) ...[
              const SizedBox(height: 8),
              const _SubHeading('Not worn in three months'),
              for (final ranked in idle.take(5))
                _ItemRow(
                  item: ranked.item,
                  trailing: '${ranked.value.round()} days',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.summary});

  final WardrobeSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = summary.bestValue;
    if (best.isEmpty) return const SizedBox.shrink();

    String perWear(RankedItem ranked) {
      final currency = ranked.item.purchase?.currencyCode ?? '';
      return '${ranked.value.toStringAsFixed(2)} $currency';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cost per wear', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              // Stated plainly because the omission is otherwise mistaken for
              // a bug: an unworn item has no cost per wear, not an infinite one.
              'Only items with both a price and a wear appear here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            const _SubHeading('Earning their keep'),
            for (final ranked in best.take(3))
              _ItemRow(item: ranked.item, trailing: perWear(ranked)),
            if (summary.worstValue.length > 3) ...[
              const SizedBox(height: 8),
              const _SubHeading('Yet to'),
              for (final ranked in summary.worstValue.take(3))
                _ItemRow(item: ranked.item, trailing: perWear(ranked)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubHeading extends StatelessWidget {
  const _SubHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.trailing});

  final WardrobeItem item;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => context.go('/item/${item.id.value}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              trailing,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insights_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Nothing to measure yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Add a few garments and this fills in on its own.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/scan'),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add a garment'),
            ),
          ],
        ),
      ),
    );
  }
}
