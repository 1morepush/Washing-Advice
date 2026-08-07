/// The wardrobe list — the app's home.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/app_drawer.dart';
import 'filter_sheet.dart';
import 'widgets/item_card.dart';
import 'widgets/item_tile.dart';

class WardrobeScreen extends ConsumerWidget {
  const WardrobeScreen({super.key});

  /// The view this screen returns to when filters are cleared.
  ///
  /// Not an empty query: the wardrobe shows what the user still owns, so the
  /// lifecycle filter is the baseline rather than something they applied.
  /// Clearing to a truly empty query would surface everything they have given
  /// away, which is not what "clear filters" means to anyone.
  static const baseline = WardrobeQuery.owned();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(wardrobeItemsProvider);
    final owned = ref.watch(ownedCountProvider).valueOrNull;

    return Scaffold(
      drawer: const AppDrawer(current: AppDestination.wardrobe),
      appBar: AppBar(
        title: const Text('Wardrobe'),
        actions: [
          _ViewToggle(
            view: ref.watch(wardrobeViewProvider),
            onChanged: (view) =>
                ref.read(wardrobeViewProvider.notifier).state = view,
          ),
          _FilterAction(
            // Counted against the baseline, not against an empty query: the
            // lifecycle filter in `.owned()` is the default view, and badging
            // it as an active filter would show "1" to someone who has set
            // nothing.
            count: ref
                .watch(wardrobeQueryProvider)
                .copyWith(
                  lifecycleStates: WardrobeScreen.baseline.lifecycleStates,
                )
                .activeFilterCount,
            onPressed: () => showFilterSheet(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _SearchField(
            query: ref.watch(wardrobeQueryProvider),
            onChanged: (text) => ref
                .read(wardrobeQueryProvider.notifier)
                .update((q) => q.copyWith(text: text)),
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Adding one garment is the smaller action and gets the smaller
          // button. Sorting a pile is what the app is for.
          FloatingActionButton.small(
            heroTag: 'add-item',
            onPressed: () => context.go('/scan'),
            tooltip: 'Add a garment',
            child: const Icon(Icons.add_a_photo_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'sort-pile',
            onPressed: () => context.go('/pile'),
            icon: const Icon(Icons.local_laundry_service_outlined),
            label: const Text('Sort laundry'),
          ),
        ],
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Failures are shown, not swallowed. A wardrobe that silently renders
        // as empty when the database cannot be opened is worse than one that
        // says so, because the user's next move is to add everything again.
        error: (error, _) => _Message(
          icon: Icons.error_outline,
          title: 'Could not load your wardrobe',
          detail: '$error',
        ),
        // Whether filters are hiding things is answered by the wardrobe, not
        // by inspecting the query: the default view is `.owned()`, which is a
        // filter in shape but not in meaning, and reading it as one told a
        // first-time user with nothing saved that "no items match the filters
        // you have set".
        data: (list) => list.isEmpty
            ? _EmptyState(hasItems: (owned ?? 0) > 0, ref: ref)
            : _ItemList(items: list),
      ),
    );
  }
}

/// Switches between the grid and the list.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final WardrobeView view;
  final ValueChanged<WardrobeView> onChanged;

  @override
  Widget build(BuildContext context) {
    final isGrid = view == WardrobeView.grid;
    return IconButton(
      // The icon shows what tapping *gives you*, not what you are looking at.
      // The other convention leaves people tapping to find out.
      onPressed: () =>
          onChanged(isGrid ? WardrobeView.list : WardrobeView.grid),
      icon: Icon(isGrid ? Icons.view_list_outlined : Icons.grid_view_outlined),
      tooltip: isGrid ? 'Show as a list' : 'Show as a grid',
    );
  }
}

/// The filter button, badged with how many filters are on.
class _FilterAction extends StatelessWidget {
  const _FilterAction({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.tune),
      tooltip: 'Filter',
    );
    if (count == 0) return button;

    return Badge.count(count: count, child: button);
  }
}

class _ItemList extends ConsumerWidget {
  const _ItemList({required this.items});

  final List<WardrobeItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = ref.watch(ownedCountProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          // "12 of 40" rather than "12 items": an unexpectedly short list is
          // otherwise indistinguishable from a small wardrobe, and the user
          // has no way to tell they left a filter on.
          child: Text(
            owned == null || owned == items.length
                ? '${items.length} ${items.length == 1 ? 'item' : 'items'}'
                : '${items.length} of $owned items',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ref.watch(wardrobeViewProvider) == WardrobeView.grid
              ? _Grid(items: items)
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 88),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ItemTile(
                      item: item,
                      onTap: () => context.go('/item/${item.id.value}'),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// The wardrobe as a wall of garments.
class _Grid extends StatelessWidget {
  const _Grid({required this.items});

  final List<WardrobeItem> items;

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
    // Sized by extent rather than a fixed column count, so a phone gets three
    // columns, a tablet gets six, and neither has to be special-cased.
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 180,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      // Taller than wide: garments are, and the two text lines need room.
      childAspectRatio: 0.78,
    ),
    itemCount: items.length,
    itemBuilder: (context, index) {
      final item = items[index];
      return ItemCard(
        item: item,
        onTap: () => context.go('/item/${item.id.value}'),
      );
    },
  );
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.query, required this.onChanged});

  final WardrobeQuery query;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final _controller = TextEditingController(text: widget.query.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search your wardrobe',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasItems, required this.ref});

  /// Whether the user owns anything at all. If they do and the list is still
  /// empty, filters are the reason.
  final bool hasItems;

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) => hasItems
      ? _Message(
          icon: Icons.filter_alt_off_outlined,
          title: 'Nothing matches',
          detail: 'No items match the filters you have set.',
          action: TextButton(
            onPressed: () => ref.read(wardrobeQueryProvider.notifier).state =
                WardrobeScreen.baseline,
            child: const Text('Clear filters'),
          ),
        )
      : const _Message(
          icon: Icons.checkroom_outlined,
          title: 'Your wardrobe is empty',
          detail: 'Scan a garment to add the first item.',
        );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action case final Widget action) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
