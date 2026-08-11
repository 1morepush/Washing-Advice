/// Packing for a trip.
///
/// The list itself is table stakes. What this screen is actually for is the
/// notes underneath it: what the trip will do to the clothes, which is the
/// thing a wardrobe app knows and a packing app does not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/item_thumbnail.dart';
import '../../widgets/status_message.dart';

class PackingScreen extends ConsumerWidget {
  const PackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripSpecProvider);
    final list = ref.watch(packingListProvider);

    void update(TripSpec updated) =>
        ref.read(tripSpecProvider.notifier).state = updated;

    return Scaffold(
      appBar: AppBar(title: const Text('Packing')),
      drawer: const AppDrawer(current: AppDestination.packing),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StatusMessage.failure(
          title: 'Could not work out what to pack',
          error: error,
        ),
        data: (plan) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _TripForm(trip: trip, onChanged: update),
            const SizedBox(height: 16),
            if (plan.notes.isNotEmpty) ...[
              _Notes(notes: plan.notes),
              const SizedBox(height: 16),
            ],
            if (plan.gaps.isNotEmpty) ...[
              _Gaps(gaps: plan.gaps),
              const SizedBox(height: 16),
            ],
            _Bag(plan: plan),
          ],
        ),
      ),
    );
  }
}

class _TripForm extends StatelessWidget {
  const _TripForm({required this.trip, required this.onChanged});

  final TripSpec trip;
  final ValueChanged<TripSpec> onChanged;

  TripSpec _copy({
    int? days,
    Season? season,
    Set<Occasion>? occasions,
    bool? laundryAvailable,
  }) => TripSpec(
    days: days ?? trip.days,
    season: season ?? trip.season,
    occasions: occasions ?? trip.occasions,
    laundryAvailable: laundryAvailable ?? trip.laundryAvailable,
    washEveryDays: trip.washEveryDays,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${trip.days}', style: theme.textTheme.headlineMedium),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    trip.days == 1 ? 'day' : 'days',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: trip.days.toDouble(),
              min: 1,
              max: 21,
              divisions: 20,
              label: '${trip.days}',
              onChanged: (value) => onChanged(_copy(days: value.round())),
            ),
            const SizedBox(height: 8),
            Text('What kind of days', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final occasion in Occasion.values)
                  FilterChip(
                    label: Text(occasion.label),
                    selected: trip.occasions.contains(occasion),
                    onSelected: (on) {
                      final next = {...trip.occasions};
                      if (on) {
                        next.add(occasion);
                      } else {
                        next.remove(occasion);
                      }
                      // A trip with no kind of day at all packs nothing, which
                      // reads as a bug rather than as an answer.
                      if (next.isEmpty) return;
                      onChanged(_copy(occasions: next));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Season>(
                    initialValue: trip.season,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Season',
                      isDense: true,
                    ),
                    style: theme.textTheme.bodyMedium,
                    items: [
                      for (final season in Season.values)
                        DropdownMenuItem(
                          value: season,
                          child: Text(
                            season == Season.allSeason ? 'Any' : season.label,
                          ),
                        ),
                    ],
                    onChanged: (season) => onChanged(_copy(season: season)),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: trip.laundryAvailable,
              onChanged: (on) => onChanged(_copy(laundryAvailable: on)),
              title: const Text('Laundry where I am staying'),
              // The single biggest lever on how much goes in the bag, so it
              // says what it does. Stated against *this* trip rather than in
              // general: on a short trip the cap changes nothing, and a
              // subtitle promising a saving that will not arrive is worse than
              // no subtitle.
              subtitle: Text(
                trip.days <= trip.washEveryDays + 1
                    ? 'This trip is short enough that a wash would not save '
                          'you anything'
                    : 'Packs ${trip.washEveryDays + 1} of each instead of '
                          '${trip.days}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_laundry_service_outlined,
                  size: 20,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'While you are away',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  note,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Gaps extends StatelessWidget {
  const _Gaps({required this.gaps});

  final List<PackingGap> gaps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Short of a few things',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              // Said out loud, because a list that looks complete and is not
              // is how people arrive somewhere without socks.
              'The list below is what your wardrobe could supply, not what the '
              'trip needs.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            for (final gap in gaps)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  gap.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bag extends StatelessWidget {
  const _Bag({required this.plan});

  final PackingList plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (plan.items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Nothing in your wardrobe suits this trip yet.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final byCategory = <ItemCategory, List<PackedItem>>{};
    for (final packed in plan.items) {
      (byCategory[packed.category] ??= []).add(packed);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${plan.count} items',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  // Approximate by construction, and labelled as such rather
                  // than presented as a figure to weigh a bag against.
                  'about ${(plan.estimatedWeightGrams / 1000).toStringAsFixed(1)} kg',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final entry in byCategory.entries) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${entry.key.label} · ${entry.value.length}',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Flexible, because this one is not a fixed phrase. The
                  // reason for footwear and for anything uncategorised is
                  // "For " plus every occasion the trip covers, joined — so a
                  // trip that is a bit of everything produces a line several
                  // times wider than a phone. Unflexed, that overflowed the
                  // row rather than wrapping.
                  Flexible(
                    child: Text(
                      entry.value.first.reason,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: entry.value.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final item = entry.value[index].item;
                    return InkWell(
                      onTap: () => context.go('/item/${item.id.value}'),
                      borderRadius: BorderRadius.circular(12),
                      child: Tooltip(
                        message: item.displayName,
                        child: ItemThumbnail(item: item, size: 72),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
