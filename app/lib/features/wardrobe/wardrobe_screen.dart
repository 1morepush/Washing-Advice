/// The wardrobe list — the app's home.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/app_drawer.dart';
import '../laundry/laundry_controller.dart';
import 'filter_sheet.dart';
import 'widgets/item_card.dart';
import 'widgets/item_tile.dart';

/// The garments currently picked out, if any.
///
/// A full basket is the ordinary case, and taking it to the laundry screen one
/// garment at a time is the kind of tedium that gets a feature abandoned. Kept
/// on the screen rather than in the controller because it is a thing the *list*
/// is doing, and it ends the moment the last garment is unpicked.
final wardrobeSelectionProvider = StateProvider<Set<ItemId>>((ref) => {});

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
    final selection = ref.watch(wardrobeSelectionProvider);

    // A contextual scaffold rather than extra buttons on the usual one. While
    // you are picking clothes out, search and filters and the two floating
    // buttons are all in the way, and the one thing that matters is how to
    // finish or how to get out.
    if (selection.isNotEmpty) {
      return _SelectionScaffold(
        selection: selection,
        items: items.valueOrNull ?? const [],
      );
    }

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
                    final selection = ref.watch(wardrobeSelectionProvider);
                    return ItemTile(
                      item: item,
                      selected: selection.contains(item.id),
                      // Once you have started picking clothes out, a tap adds
                      // to the selection instead of opening the garment.
                      // Navigating away mid-selection would throw the selection
                      // out, which is not what a tap means any more.
                      onTap: selection.isEmpty
                          ? () => context.go('/item/${item.id.value}')
                          : () => toggleWardrobeSelection(ref, item.id),
                      onLongPress: () => toggleWardrobeSelection(ref, item.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// The wardrobe as a wall of garments.
class _Grid extends ConsumerWidget {
  const _Grid({required this.items});

  final List<WardrobeItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GridView.builder(
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
      final selection = ref.watch(wardrobeSelectionProvider);
      return ItemCard(
        item: item,
        selected: selection.contains(item.id),
        onTap: selection.isEmpty
            ? () => context.go('/item/${item.id.value}')
            : () => toggleWardrobeSelection(ref, item.id),
        onLongPress: () => toggleWardrobeSelection(ref, item.id),
      );
    },
  );
}

/// Adds [id] to the selection, or takes it back out.
void toggleWardrobeSelection(WidgetRef ref, ItemId id) {
  final notifier = ref.read(wardrobeSelectionProvider.notifier);
  final next = {...notifier.state};
  if (!next.remove(id)) next.add(id);
  notifier.state = next;
}

/// The wardrobe while garments are being picked out.
///
/// Everything a selection cannot use is gone: the drawer, the search box, the
/// filter button and both floating buttons. What is left says how many are
/// picked, how to take them all, how to stop, and the one action worth doing in
/// bulk.
class _SelectionScaffold extends ConsumerWidget {
  const _SelectionScaffold({required this.selection, required this.items});

  final Set<ItemId> selection;
  final List<WardrobeItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only what can actually go. `transitionTo` would refuse the rest, so a
    // button counting them would promise a move that silently does nothing.
    final washable = [
      for (final item in items)
        if (selection.contains(item.id) &&
            item.lifecycle == LifecycleState.active)
          item.id,
    ];

    void clear() => ref.read(wardrobeSelectionProvider.notifier).state = {};

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: clear,
          tooltip: 'Stop selecting',
        ),
        title: Text('${selection.length} selected'),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(wardrobeSelectionProvider.notifier).state = {
                  for (final item in items) item.id,
                },
            child: const Text('All'),
          ),
        ],
      ),
      body: _ItemList(items: items),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: washable.isEmpty
                ? null
                : () async {
                    await ref
                        .read(laundryControllerProvider)
                        .move(washable, LifecycleState.inLaundry);
                    clear();
                  },
            icon: const Icon(Icons.local_laundry_service_outlined),
            label: Text(
              washable.isEmpty
                  ? 'Nothing here can go in the wash'
                  : 'Put ${washable.length} in the wash',
            ),
          ),
        ),
      ),
    );
  }
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

  /// Follows the query when something other than this field changes it.
  ///
  /// The field owns its controller but not the query, and two other controls
  /// reset that query wholesale: "Clear all" in the filter sheet and "Clear
  /// filters" on the empty state. Without this the wardrobe went back to
  /// showing everything while the box still displayed the search that was no
  /// longer being applied — a list that visibly disagrees with the filter
  /// above it.
  ///
  /// Guarded on inequality so it never fights typing: a keystroke updates the
  /// query, which rebuilds this widget with the text it already holds.
  @override
  void didUpdateWidget(_SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = widget.query.text ?? '';
    if (text != _controller.text) _controller.text = text;
  }

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
