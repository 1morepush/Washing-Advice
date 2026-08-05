/// Choosing what the wardrobe shows.
///
/// The sheet edits a [WardrobeQuery] and nothing else. That is the point of
/// having made the query a value type in M1: filtering is a matter of building
/// one, and the repository — Drift or in-memory — already knows what every
/// field means. A screen that assembled SQL, or that kept eight separate
/// booleans and reassembled them on each read, would be re-deciding semantics
/// the core has already settled.
///
/// It is also why a natural-language search can be added later without
/// touching this file or the database: "show me my blue hoodies" becomes a
/// translation problem that ends in the same `WardrobeQuery`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import 'wardrobe_screen.dart';

/// Opens the filter sheet, applying changes as they are made.
Future<void> showFilterSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) =>
      const FractionallySizedBox(heightFactor: 0.85, child: FilterSheet()),
);

class FilterSheet extends ConsumerWidget {
  const FilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(wardrobeQueryProvider);
    final theme = Theme.of(context);

    void update(WardrobeQuery Function(WardrobeQuery q) change) =>
        ref.read(wardrobeQueryProvider.notifier).update(change);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Filter', style: theme.textTheme.titleLarge),
              ),
              // Clearing returns to the wardrobe's baseline rather than to an
              // empty query, which would surface everything the user has given
              // away. `activeFilterCount` is the core's own count, so the badge
              // cannot disagree with what is actually applied.
              if (query != WardrobeScreen.baseline)
                TextButton(
                  onPressed: () => update((_) => WardrobeScreen.baseline),
                  child: const Text('Clear all'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              _Section(
                title: 'Category',
                child: _ChipGroup<ItemCategory>(
                  values: ItemCategory.values,
                  selected: query.categories,
                  label: (c) => c.label,
                  onChanged: (set) =>
                      update((q) => q.copyWith(categories: set)),
                ),
              ),
              _Section(
                title: 'Colour',
                child: _ChipGroup<ColorClass>(
                  values: ColorClass.values,
                  selected: query.colorClasses,
                  label: (c) => c.label,
                  onChanged: (set) =>
                      update((q) => q.copyWith(colorClasses: set)),
                ),
              ),
              _Section(
                title: 'Fabric',
                // Only the fibres a wardrobe actually contains in quantity.
                // Offering all twenty would bury the four that matter.
                child: _ChipGroup<Fiber>(
                  values: const [
                    Fiber.cotton,
                    Fiber.wool,
                    Fiber.silk,
                    Fiber.linen,
                    Fiber.polyester,
                    Fiber.viscose,
                    Fiber.cashmere,
                    Fiber.leather,
                  ],
                  selected: query.fibers,
                  label: (f) => f.label,
                  onChanged: (set) => update((q) => q.copyWith(fibers: set)),
                ),
              ),
              _Section(
                title: 'Season',
                child: _ChipGroup<Season>(
                  values: Season.values,
                  selected: query.seasons,
                  label: (s) => s.label,
                  onChanged: (set) => update((q) => q.copyWith(seasons: set)),
                ),
              ),
              _BrandSection(query: query, update: update),
              _Section(
                title: 'Show only',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Favourites'),
                      selected: query.favouritesOnly,
                      onSelected: (on) =>
                          update((q) => q.copyWith(favouritesOnly: on)),
                    ),
                    FilterChip(
                      // The "why do I own this?" view.
                      label: const Text('Never worn'),
                      selected: query.neverWorn,
                      onSelected: (on) =>
                          update((q) => q.copyWith(neverWorn: on)),
                    ),
                    FilterChip(
                      label: const Text('Needs a label scan'),
                      selected: query.needsCareTagScan,
                      onSelected: (on) =>
                          update((q) => q.copyWith(needsCareTagScan: on)),
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'Sort by',
                child: _ChipGroup<WardrobeSort>.single(
                  values: WardrobeSort.values,
                  selectedValue: query.sort,
                  label: _sortLabel,
                  onSelected: (sort) => update((q) => q.copyWith(sort: sort)),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const _ResultCount(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// How many items the current filters match.
///
/// On the dismiss button, because the useful moment to know is before closing
/// the sheet — a filter combination matching nothing is worth discovering
/// while the controls are still on screen.
class _ResultCount extends ConsumerWidget {
  const _ResultCount();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(wardrobeItemsProvider).valueOrNull;
    if (items == null) return const Text('Show results');
    return Text(
      items.isEmpty
          ? 'Nothing matches'
          : 'Show ${items.length} ${items.length == 1 ? 'item' : 'items'}',
    );
  }
}

class _BrandSection extends ConsumerWidget {
  const _BrandSection({required this.query, required this.update});

  final WardrobeQuery query;
  final void Function(WardrobeQuery Function(WardrobeQuery q)) update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brands = ref.watch(knownBrandsProvider).valueOrNull ?? const [];
    // Drawn from the wardrobe rather than from a fixed list: a filter offering
    // brands the user does not own is a filter that returns nothing.
    if (brands.isEmpty) return const SizedBox.shrink();

    return _Section(
      title: 'Brand',
      child: _ChipGroup<String>(
        values: brands,
        selected: query.brands,
        label: (b) => b,
        onChanged: (set) => update((q) => q.copyWith(brands: set)),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

/// A row of chips, either multi-select or single-select.
class _ChipGroup<T extends Object> extends StatelessWidget {
  const _ChipGroup({
    required this.values,
    required Set<T> this.selected,
    required this.label,
    required ValueChanged<Set<T>> this.onChanged,
  }) : selectedValue = null,
       onSelected = null;

  const _ChipGroup.single({
    required this.values,
    required T this.selectedValue,
    required this.label,
    required ValueChanged<T> this.onSelected,
  }) : selected = null,
       onChanged = null;

  final List<T> values;
  final Set<T>? selected;
  final T? selectedValue;
  final String Function(T value) label;
  final ValueChanged<Set<T>>? onChanged;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in values)
        if (onChanged case final ValueChanged<Set<T>> onChanged)
          FilterChip(
            label: Text(label(value)),
            selected: selected!.contains(value),
            onSelected: (on) => onChanged(
              {...selected!, if (on) value}
                ..removeWhere((v) => !on && v == value),
            ),
          )
        else
          ChoiceChip(
            label: Text(label(value)),
            selected: selectedValue == value,
            onSelected: (_) => onSelected!(value),
          ),
    ],
  );
}

String _sortLabel(WardrobeSort sort) => switch (sort) {
  WardrobeSort.recentlyAdded => 'Recently added',
  WardrobeSort.nameAscending => 'Name',
  WardrobeSort.mostWorn => 'Most worn',
  WardrobeSort.recentlyWorn => 'Recently worn',
  WardrobeSort.leastRecentlyWorn => 'Least worn lately',
  WardrobeSort.costPerWear => 'Cost per wear',
};
