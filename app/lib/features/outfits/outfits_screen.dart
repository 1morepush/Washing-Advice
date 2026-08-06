/// Something to wear.
///
/// The screen's job is to make the reasoning visible. A suggestion with no
/// explanation is either obeyed blindly or ignored, and both are worse than
/// one the user can disagree with — so every card carries the reasons the core
/// gave for it, in the core's own words.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/item_thumbnail.dart';
import '../history/wear_recorder.dart';

class OutfitsScreen extends ConsumerWidget {
  const OutfitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(outfitSuggestionsProvider);
    final request = ref.watch(outfitRequestProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Outfits'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _OccasionBar(
            selected: request.occasion,
            onChanged: (occasion) => ref
                .read(outfitRequestProvider.notifier)
                .update((r) => _copy(r, occasion: occasion)),
          ),
        ),
      ),
      drawer: const AppDrawer(current: AppDestination.outfits),
      body: suggestions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (list) => list.isEmpty
            ? _Empty(occasion: request.occasion)
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: list.length,
                itemBuilder: (_, index) => _SuggestionCard(
                  suggestion: list[index],
                  occasion: request.occasion,
                ),
              ),
      ),
      bottomNavigationBar: _Options(
        request: request,
        onChanged: (updated) =>
            ref.read(outfitRequestProvider.notifier).state = updated,
      ),
    );
  }
}

/// `OutfitRequest` has no `copyWith`, deliberately — it is a request, not an
/// entity, and the core has no use for one. The screen does, so it lives here.
OutfitRequest _copy(
  OutfitRequest request, {
  Occasion? occasion,
  Season? season,
  bool? includeOuterwear,
}) => OutfitRequest(
  occasion: occasion ?? request.occasion,
  season: season ?? request.season,
  count: request.count,
  includeOuterwear: includeOuterwear ?? request.includeOuterwear,
  includeFootwear: request.includeFootwear,
  mustInclude: request.mustInclude,
  exclude: request.exclude,
);

class _OccasionBar extends StatelessWidget {
  const _OccasionBar({required this.selected, required this.onChanged});

  final Occasion selected;
  final ValueChanged<Occasion> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final occasion in Occasion.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: ChoiceChip(
                label: Text(occasion.label),
                selected: occasion == selected,
                onSelected: (_) => onChanged(occasion),
              ),
            ),
          ),
      ],
    ),
  );
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({required this.suggestion, required this.occasion});

  final OutfitSuggestion suggestion;
  final Occasion occasion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final item in suggestion.items)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Piece(item: item),
                    ),
                  ),
              ],
            ),
            if (suggestion.reasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              for (final reason in suggestion.reasons.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          reason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              // What closes the loop. Recording an outfit as worn is the only
              // way the app finds out its suggestion was any good, and every
              // such record teaches the builder a pairing it did not know.
              child: TextButton.icon(
                onPressed: () async {
                  await ref
                      .read(wearRecorderProvider)
                      .recordOutfit(
                        suggestion.itemIds,
                        occasion: occasion.name,
                      );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Recorded. These now count as worn '
                        'together.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.checkroom_outlined, size: 18),
                label: const Text('Wearing this'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Piece extends StatelessWidget {
  const _Piece({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => context.go('/item/${item.id.value}'),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ItemThumbnail(item: item, size: double.infinity),
          ),
          const SizedBox(height: 8),
          Text(
            item.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            item.type.value.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Options extends StatelessWidget {
  const _Options({required this.request, required this.onChanged});

  final OutfitRequest request;
  final ValueChanged<OutfitRequest> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<Season>(
                initialValue: request.season,
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
                onChanged: (season) =>
                    onChanged(_copy(request, season: season)),
              ),
            ),
            const SizedBox(width: 16),
            FilterChip(
              label: const Text('With a layer'),
              selected: request.includeOuterwear,
              onSelected: (on) =>
                  onChanged(_copy(request, includeOuterwear: on)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.occasion});

  final Occasion occasion;

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
              Icons.style_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing for ${occasion.label.toLowerCase()} yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              // Naming the actual requirement, rather than "no results". An
              // outfit needs both halves, and someone with only tops catalogued
              // should be told that instead of left guessing.
              'An outfit needs a top and a bottom, or a one-piece. Add more '
              'to your wardrobe, or tag things for this occasion if the '
              'defaults do not match how you dress.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
