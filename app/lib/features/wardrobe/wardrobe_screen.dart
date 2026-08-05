/// The wardrobe list — the app's home.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import 'widgets/item_tile.dart';

class WardrobeScreen extends ConsumerWidget {
  const WardrobeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(wardrobeItemsProvider);
    final query = ref.watch(wardrobeQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wardrobe'),
        actions: [
          IconButton(
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _SearchField(
            query: query,
            onChanged: (text) => ref
                .read(wardrobeQueryProvider.notifier)
                .update((q) => q.copyWith(text: text)),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/scan'),
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Scan'),
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
        data: (list) => list.isEmpty
            ? _EmptyState(isFiltered: !query.isUnfiltered, ref: ref)
            : _ItemList(items: list),
      ),
    );
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
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
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
  const _EmptyState({required this.isFiltered, required this.ref});

  final bool isFiltered;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) => isFiltered
      ? _Message(
          icon: Icons.filter_alt_off_outlined,
          title: 'Nothing matches',
          detail: 'No items match the filters you have set.',
          action: TextButton(
            onPressed: () => ref
                .read(wardrobeQueryProvider.notifier)
                .update((q) => q.cleared()),
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
