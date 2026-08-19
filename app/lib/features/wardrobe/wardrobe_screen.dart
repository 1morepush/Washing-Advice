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

/// Duplicate groups the user has opened up.
///
/// Collapsing is the default because six identical socks crowd out the garment
/// somebody was looking for. Expanding is per-group and not remembered across
/// visits: opening one is a thing you do to answer a question — which of these
/// have I actually worn — rather than a preference about your wardrobe.
final expandedGroupsProvider = StateProvider<Set<String>>((ref) => {});

/// Whether copies are collapsed at all.
///
/// Off is a real setting rather than a debug switch. The grouping is inferred
/// from facts the app happens to hold, so somebody whose wardrobe it reads
/// wrongly needs a way to simply stop it, and "tap each group open every time"
/// is not that.
final groupDuplicatesProvider = StateProvider<bool>((ref) => true);

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
          // In the overflow rather than as a fourth icon: it is set once and
          // then forgotten, which is not what the top bar is for.
          _MoreMenu(
            grouping: ref.watch(groupDuplicatesProvider),
            onGrouping: (on) {
              ref.read(groupDuplicatesProvider.notifier).state = on;
              ref.read(expandedGroupsProvider.notifier).state = {};
            },
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
          // One button that asks, rather than two unlabelled circles neither
          // of which said what it did without a long press.
          FloatingActionButton.small(
            heroTag: 'add-item',
            onPressed: () => _chooseHowToAdd(context),
            tooltip: 'Add garments',
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

/// Asks whether this is one garment or a pile.
///
/// The two jobs are different — "I bought a shirt" against "I am setting this
/// app up" — but they are the same verb, so they share a button and the sheet
/// names both in words.
Future<void> _chooseHowToAdd(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('One garment'),
            subtitle: const Text(
              'Photograph it and its care label, and check the reading.',
            ),
            onTap: () => Navigator.pop(context, '/scan'),
          ),
          ListTile(
            leading: const Icon(Icons.checklist_outlined),
            title: const Text('Several garments'),
            subtitle: const Text(
              'Photograph a whole pile first, then submit the lot at once. '
              'No waiting between garments.',
            ),
            onTap: () => Navigator.pop(context, '/scan/bulk'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (choice != null && context.mounted) context.go(choice);
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

/// The overflow, which currently holds one thing.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.grouping, required this.onGrouping});

  final bool grouping;
  final ValueChanged<bool> onGrouping;

  @override
  Widget build(BuildContext context) => PopupMenuButton<void>(
    tooltip: 'More',
    itemBuilder: (_) => [
      CheckedPopupMenuItem(
        checked: grouping,
        onTap: () => onGrouping(!grouping),
        child: const Text('Group identical items'),
      ),
    ],
  );
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
              : _List(items: items),
        ),
      ],
    );
  }
}

/// The wardrobe as a wall of garments.
/// The wardrobe as rows.
class _List extends ConsumerWidget {
  const _List({required this.items});

  final List<WardrobeItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = _shown(ref, items);
    final selection = ref.watch(wardrobeSelectionProvider);

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 88),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ItemTile(
          item: entry.item,
          copies: entry.copies,
          selected: selection.contains(entry.item.id),
          // Once you have started picking clothes out, a tap adds to the
          // selection instead of opening the garment. Navigating away
          // mid-selection would throw the selection out, which is not what a
          // tap means any more.
          onTap: selection.isEmpty
              ? () => _open(context, ref, entry)
              : () => _toggleEntry(ref, entry),
          onLongPress: () => _toggleEntry(ref, entry),
        );
      },
    );
  }
}

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
    itemCount: _shown(ref, items).length,
    itemBuilder: (context, index) {
      final entry = _shown(ref, items)[index];
      final selection = ref.watch(wardrobeSelectionProvider);
      return ItemCard(
        item: entry.item,
        selected: selection.contains(entry.item.id),
        copies: entry.copies,
        onTap: selection.isEmpty
            ? () => _open(context, ref, entry)
            : () => _toggleEntry(ref, entry),
        onLongPress: () => _toggleEntry(ref, entry),
      );
    },
  );
}

/// One row of the wardrobe: a garment, and how many copies it stands for.
///
/// A group of one and a lone garment are the same thing here, so the list has
/// one kind of row rather than two — which is what keeps selection, tapping and
/// the empty state from each needing a branch.
class _Entry {
  const _Entry({required this.group, required this.expanded});

  final DuplicateGroup group;

  /// Whether this row is a member of an opened group rather than its head.
  final bool expanded;

  WardrobeItem get item => group.representative;

  /// How many garments this row stands for — 1 once the group is opened, so a
  /// member never claims to be the whole group.
  int get copies => expanded ? 1 : group.count;

  List<ItemId> get ids => expanded ? [item.id] : group.ids;
}

/// The rows to draw, with opened groups flattened back into their members.
List<_Entry> _shown(WidgetRef ref, List<WardrobeItem> items) {
  if (!ref.watch(groupDuplicatesProvider)) {
    return [
      for (final item in items)
        _Entry(
          group: DuplicateGroup(signature: item.id.value, items: [item]),
          expanded: true,
        ),
    ];
  }

  final open = ref.watch(expandedGroupsProvider);
  return [
    for (final group in groupDuplicates(items))
      if (group.isMultiple && open.contains(group.signature))
        for (final item in group.items)
          _Entry(
            group: DuplicateGroup(signature: group.signature, items: [item]),
            expanded: true,
          )
      else
        _Entry(group: group, expanded: false),
  ];
}

/// Opens a garment, or opens up a group.
///
/// A collapsed group has no single garment to show — its members have their own
/// histories and their own wear counts, and picking one to stand for the rest
/// would be inventing an answer. So the first tap opens the group and the
/// second opens a garment.
void _open(BuildContext context, WidgetRef ref, _Entry entry) {
  if (entry.copies > 1) {
    final notifier = ref.read(expandedGroupsProvider.notifier);
    notifier.state = {...notifier.state, entry.group.signature};
    return;
  }
  context.go('/item/${entry.item.id.value}');
}

/// Selects or deselects everything a row stands for.
void _toggleEntry(WidgetRef ref, _Entry entry) {
  final notifier = ref.read(wardrobeSelectionProvider.notifier);
  final next = {...notifier.state};
  // All in or all out, judged by the head: half a group selected is a state
  // nothing on this screen can show, so it is not one worth reaching.
  if (next.contains(entry.item.id)) {
    next.removeAll(entry.ids);
  } else {
    next.addAll(entry.ids);
  }
  notifier.state = next;
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
