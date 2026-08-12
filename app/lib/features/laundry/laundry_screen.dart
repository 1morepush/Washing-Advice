/// The four piles: clean, to wash, washing, drying.
///
/// The point of the screen is the second tab. Everywhere else in the app a
/// garment is a thing you own; here it is a thing waiting to go in a machine,
/// and the question is not "what is this?" but "what can go in with it, and on
/// what setting?". That question already had an answer — `LaundrySorter` has
/// been able to produce it since the pile scan — and no answer of its own is
/// invented here.
///
/// The Clean tab overlaps the wardrobe, which is a real duplication and a
/// deliberate one: four piles is the mental model, and a laundry screen missing
/// the pile that clothes end up in reads as unfinished.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../widgets/app_drawer.dart';
import '../../widgets/item_thumbnail.dart';
import '../../widgets/status_message.dart';
import '../pile/widgets/load_card.dart';
import 'laundry_controller.dart';

/// One tab, and the stage it shows.
enum _Pile {
  clean('Clean', LifecycleState.active),
  toWash('To wash', LifecycleState.inLaundry),
  washing('Washing', LifecycleState.beingWashed),
  drying('Drying', LifecycleState.beingDried);

  const _Pile(this.label, this.stage);

  final String label;
  final LifecycleState stage;
}

class LaundryScreen extends ConsumerStatefulWidget {
  const LaundryScreen({this.initialTab = 1, super.key});

  /// Defaults to "To wash" rather than "Clean": someone opening Laundry is
  /// almost always about to do some, and the clean pile is the wardrobe they
  /// just came from.
  final int initialTab;

  @override
  ConsumerState<LaundryScreen> createState() => _LaundryScreenState();
}

class _LaundryScreenState extends ConsumerState<LaundryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: _Pile.values.length,
    vsync: this,
    initialIndex: widget.initialTab,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    drawer: const AppDrawer(current: AppDestination.laundry),
    appBar: AppBar(
      title: const Text('Laundry'),
      bottom: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabs: [
          for (final pile in _Pile.values)
            Tab(text: '${pile.label} ${_count(pile)}'),
        ],
      ),
    ),
    body: TabBarView(
      controller: _tabs,
      children: [for (final pile in _Pile.values) _PileView(pile: pile)],
    ),
  );

  /// The number in a pile, in brackets, or nothing while it is still loading.
  ///
  /// On the tab itself because the counts are the whole status report: "3 to
  /// wash, 8 washing" is what someone opens this screen to find out, and making
  /// them visit each tab to learn it would be a worse screen than no screen.
  String _count(_Pile pile) {
    final items = ref.watch(pileProvider(pile.stage)).valueOrNull;
    return items == null || items.isEmpty ? '' : '(${items.length})';
  }
}

class _PileView extends ConsumerWidget {
  const _PileView({required this.pile});

  final _Pile pile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(pileProvider(pile.stage));

    return items.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => StatusMessage.failure(
        title: 'Could not read your wardrobe',
        error: error,
      ),
      data: (data) => data.isEmpty
          ? _Empty(pile: pile)
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (pile == _Pile.toWash) const _Plan(),
                _Items(items: data, pile: pile),
              ],
            ),
    );
  }
}

/// The loads to run, for what is in the basket.
class _Plan extends ConsumerWidget {
  const _Plan();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = ref.watch(laundryPlanProvider).valueOrNull;
    if (plan == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final load in plan.loads)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: LoadCard(
              load: load,
              action: FilledButton.icon(
                // Records the wash as well as moving the clothes: this is the
                // last moment the settings are known, because once the load is
                // running it is just a set of items in the machine.
                onPressed: () =>
                    ref.read(laundryControllerProvider).start(load),
                icon: const Icon(Icons.local_laundry_service_outlined),
                label: const Text('Start this load'),
              ),
            ),
          ),

        // Never silently dropped. A garment the sorter could not place is one
        // the user is about to wash anyway, and "I put everything in and the
        // app only planned six of them" is how trust in the plan goes.
        if (plan.unassigned.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Not in a load', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final left in plan.unassigned)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${left.item.displayName} — ${left.reason}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: left.needsUserAction
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The garments in this pile, and where they can go next.
class _Items extends ConsumerWidget {
  const _Items({required this.items, required this.pile});

  final List<WardrobeItem> items;
  final _Pile pile;

  /// Where this pile's button sends a garment, and what it says.
  (String, IconData, LifecycleState)? get _next => switch (pile) {
    _Pile.clean => (
      'Put in the wash',
      Icons.local_laundry_service_outlined,
      LifecycleState.inLaundry,
    ),
    _Pile.toWash => null,
    _Pile.washing => (
      'Move to drying',
      Icons.dry_outlined,
      LifecycleState.beingDried,
    ),
    _Pile.drying => (
      'Put away',
      Icons.checkroom_outlined,
      LifecycleState.active,
    ),
  };

  /// Whether moving the whole pile at once is offered.
  ///
  /// Emphatically not on the clean pile, where "all 143" would send an entire
  /// wardrobe to the basket in one tap with nothing to undo it. Everywhere else
  /// the pile *is* a load — you take the washing out all at once — so moving it
  /// wholesale is the normal action rather than the dangerous one.
  bool get _movesWholesale => pile != _Pile.clean;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final next = _next;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (next != null && _movesWholesale)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => ref.read(laundryControllerProvider).move([
                  for (final item in items) item.id,
                ], next.$3),
                icon: Icon(next.$2),
                label: Text('${next.$1} — all ${items.length}'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            '${items.length} ${items.length == 1 ? 'item' : 'items'}',
            style: theme.textTheme.titleSmall,
          ),
        ),
        for (final item in items)
          ListTile(
            leading: ItemThumbnail(item: item, size: 44),
            title: Text(item.displayName),
            subtitle: Text(item.colorClass.label),
            trailing: next == null
                ? null
                : IconButton(
                    onPressed: () => ref.read(laundryControllerProvider).move([
                      item.id,
                    ], next.$3),
                    icon: Icon(next.$2),
                    tooltip: next.$1,
                  ),
            onTap: () => context.go('/item/${item.id.value}'),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.pile});

  final _Pile pile;

  @override
  Widget build(BuildContext context) => StatusMessage(
    icon: Icons.local_laundry_service_outlined,
    title: switch (pile) {
      _Pile.clean => 'Nothing clean',
      _Pile.toWash => 'Nothing to wash',
      _Pile.washing => 'Nothing in the washer',
      _Pile.drying => 'Nothing drying',
    },
    detail: switch (pile) {
      _Pile.clean =>
        'Everything you own is either in the wash or put away somewhere else.',
      _Pile.toWash =>
        'Put something in the wash from its own page, or from the Clean tab, '
            'and the loads to run will appear here.',
      _Pile.washing => 'Start a load from the To wash tab.',
      _Pile.drying => 'Move a load out of the washer and it will show up here.',
    },
  );
}
