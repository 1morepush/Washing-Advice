/// The three stages of a wash: basket, washing, drying.
///
/// The point of the screen is the first tab. Everywhere else in the app a
/// garment is a thing you own; here it is a thing waiting to go in a machine,
/// and the question is not "what is this?" but "what can go in with it, and on
/// what setting?". That question already had an answer — `LaundrySorter` has
/// been able to produce it since the pile scan — and no answer of its own is
/// invented here.
///
/// There used to be a fourth tab, Clean, which was the wardrobe again. With the
/// wardrobe one tap away on the bottom bar it only pushed Drying off the edge
/// of a phone, so it went; a garment reaches the basket from its own page, or
/// by selecting several in the wardrobe.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/theme.dart';
import '../../widgets/garment_glyph.dart';
import '../../widgets/item_thumbnail.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/rinse_kit.dart';
import '../../widgets/status_message.dart';
import '../pile/widgets/load_card.dart';
import 'laundry_controller.dart';

/// One tab, and the stage it shows.
enum _Pile {
  basket('Basket', LifecycleState.inLaundry),
  washing('Washing', LifecycleState.beingWashed),
  drying('Drying', LifecycleState.beingDried);

  const _Pile(this.label, this.stage);

  final String label;
  final LifecycleState stage;
}

class LaundryScreen extends ConsumerStatefulWidget {
  const LaundryScreen({this.initialTab = 0, super.key});

  /// Defaults to the basket: someone opening Laundry is almost always about to
  /// do some.
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

  /// One key per stage pill, so the row can bring the open one into view.
  final _pillKeys = [for (final _ in _Pile.values) GlobalKey()];
  final _pillScroll = ScrollController();
  int? _revealed;

  @override
  void initState() {
    super.initState();
    // Both: the controller says when the index lands after a swipe, the
    // animation when a tap's slide finishes.
    _tabs.addListener(_revealOpenPill);
    _tabs.animation!.addListener(_revealOpenPill);
    // The stage the screen opens on counts too.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealOpenPill());
  }

  @override
  void dispose() {
    _tabs.removeListener(_revealOpenPill);
    _tabs.animation!.removeListener(_revealOpenPill);
    _pillScroll.dispose();
    _tabs.dispose();
    super.dispose();
  }

  /// When the open stage changes, by a tap or a swipe, scrolls its pill fully
  /// into view. Only matters at large text, where the row scrolls; with the
  /// pills sharing the width there is nothing to scroll and nothing happens.
  void _revealOpenPill() {
    // Only once the page has come to rest: revealing each pill the page
    // passes on its way (Basket to Drying goes through Washing) starts a
    // scroll that the last one then cannot correct.
    if (_tabs.indexIsChanging ||
        _tabs.animation!.value != _tabs.index.toDouble()) {
      return;
    }
    final open = _tabs.index;
    if (open == _revealed) return;
    _revealed = open;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pillScroll.hasClients) return;
      final target = _pillKeys[open].currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Laundry'),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        // Three pills, each in its stage's colour, the open one filled. They
        // drive the same [TabController] the swipeable pages listen to, so a
        // swipe and a tap stay in step.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: AnimatedBuilder(
            animation: _tabs.animation!,
            builder: (context, _) {
              final stages = context.stageColors;
              final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
              Widget pill(int index, _Pile pile, {required bool intrinsic}) =>
                  StagePill(
                    key: _pillKeys[index],
                    label: pile.label,
                    count: _count(pile),
                    color: stages.colorOf(pile.stage)!,
                    onColor: stages.onColorOf(pile.stage)!,
                    selected: _tabs.animation!.value.round() == index,
                    compact: !large && MediaQuery.sizeOf(context).width < 400,
                    intrinsic: intrinsic,
                    onTap: () => _tabs.animateTo(index),
                  );
              // At large text three names and counts cannot share a phone's
              // width without losing letters, and a lost letter on "Washing"
              // is the one thing the pill is for. They scroll instead, each at
              // its full size.
              if (large) {
                return _FadedEdges(
                  controller: _pillScroll,
                  child: SingleChildScrollView(
                    controller: _pillScroll,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (index, pile) in _Pile.values.indexed) ...[
                          if (index > 0) const SizedBox(width: 8),
                          pill(index, pile, intrinsic: true),
                        ],
                      ],
                    ),
                  ),
                );
              }
              return Row(
                children: [
                  for (final (index, pile) in _Pile.values.indexed) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(child: pill(index, pile, intrinsic: false)),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    ),
    body: TabBarView(
      controller: _tabs,
      children: [for (final pile in _Pile.values) _PileView(pile: pile)],
    ),
  );

  /// The number in a pile, or nothing while it is still loading or empty.
  ///
  /// On the tab itself because the counts are the whole status report: "3 to
  /// wash, 8 washing" is what someone opens this screen to find out, and making
  /// them visit each tab to learn it would be a worse screen than no screen.
  int? _count(_Pile pile) {
    final items = ref.watch(pileProvider(pile.stage)).valueOrNull;
    return items == null || items.isEmpty ? null : items.length;
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
      data: (data) => data.isEmpty && pile != _Pile.basket
          ? _Empty(pile: pile)
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                // Above the plan, and above the empty state. This is the one
                // thing somebody opens the app to do on the way past the
                // basket, and it is worth nothing if it is below a list.
                if (pile == _Pile.basket) ...const [
                  SizedBox(height: 4),
                  _WoreSomething(),
                  SizedBox(height: 12),
                  _PhotographPile(),
                ],
                if (data.isEmpty)
                  _Empty(pile: pile)
                else ...[
                  if (pile == _Pile.basket) const _Plan(),
                  _Items(items: data, pile: pile),
                ],
              ],
            ),
    );
  }
}

/// The way into logging what you had on today.
///
/// Put at the top of the basket because of *when* it is used. The answer to
/// "what did you wear today" exists for about a minute, at the front door, at
/// the end of a working day — and anything that takes more than a few seconds
/// at that moment does not get done, which is how clothes end up in the pile
/// unrecorded and the wardrobe slowly stops matching the wardrobe.
class _WoreSomething extends StatelessWidget {
  const _WoreSomething();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rinse = context.rinse;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: RinseCard(
        onTap: () => context.push('/laundry/worn'),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Three garments overlapping, as in the mock-up: a picture of
            // "what you had on" rather than a generic icon.
            SizedBox(
              width: 76,
              height: 40,
              child: Stack(
                children: [
                  for (final (index, kind) in const [
                    GlyphKind.hoodie,
                    GlyphKind.jeans,
                    GlyphKind.tee,
                  ].indexed)
                    Positioned(
                      left: index * 18.0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: rinse.well,
                          border: Border.all(
                            color: theme.cardTheme.color ?? theme.cardColor,
                            width: 2,
                          ),
                        ),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: GarmentGlyph(
                              kind: kind,
                              fill: wornTodayStackFill(theme.colorScheme, kind),
                              edge: rinse.garmentEdge,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What did you wear today?',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap them once. No photo needed — they are already in '
                    'your wardrobe.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
    );
  }
}

/// The way into sorting a heap of washing from one photograph.
///
/// Here rather than on the Wardrobe, where it was a floating button: it is a
/// laundry job, done with the washing in front of you, and the wardrobe's
/// corner is for adding garments. Beside "what did you wear today?" because
/// those are the two ways a basket gets filled, and under it because that one
/// is the daily one.
class _PhotographPile extends StatelessWidget {
  const _PhotographPile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: RinseCard(
        onTap: () => context.push('/pile'),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.photo_camera_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Photograph a pile',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Lay the washing out, take one photo, and get the loads '
                    'to run.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
    );
  }
}

/// Starts a load, and asks the one thing the app cannot see.
///
/// The record of a wash keeps whether the recommended programme was the one
/// actually run. The app knows what it recommended; only the person at the
/// machine knows what they selected, and most of the time it is the same
/// thing — so the box starts ticked and costs nothing to leave alone. It is
/// there for the other times, because a record that can only ever say "yes"
/// is no evidence that the advice is any good.
class _StartLoad extends ConsumerStatefulWidget {
  const _StartLoad({required this.load});

  final LaundryLoad load;

  @override
  ConsumerState<_StartLoad> createState() => _StartLoadState();
}

class _StartLoadState extends ConsumerState<_StartLoad> {
  bool _followed = true;

  @override
  Widget build(BuildContext context) {
    final programme = widget.load.washerSetting?.programName;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Only when there is a programme to have followed. Without a machine
        // set the card states requirements, and there is nothing to ask.
        if (programme != null)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _followed,
            onChanged: (value) => setState(() => _followed = value ?? true),
            title: Text('Ran it on $programme'),
          ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: context.stageColors.wash,
            foregroundColor: context.stageColors.onWash,
          ),
          // Records the wash as well as moving the clothes: this is the last
          // moment the settings are known, because once the load is running
          // it is just a set of items in the machine.
          onPressed: () => ref
              .read(laundryControllerProvider)
              .start(widget.load, followedRecommendation: _followed),
          icon: const Icon(Icons.local_laundry_service_outlined),
          label: const Text('Start this load'),
        ),
      ],
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
            // Keyed by what is in the load, so its card — and the "Ran it on
            // …" box inside — travels with it when an earlier load starts and
            // leaves the list. Not by position, and not by id: load ids are
            // positional too (`load.1`, `load.2`), so either way the second
            // load inherited the first one's box.
            key: ValueKey(
              [for (final item in load.items) item.id.value].join('|'),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: LoadCard(
              load: load,
              action: _StartLoad(load: load),
            ),
          ),

        // Never silently dropped. A garment the sorter could not place is one
        // the user is about to wash anyway, and "I put everything in and the
        // app only planned six of them" is how trust in the plan goes.
        if (plan.unassigned.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Not in a load'),
                for (final left in plan.unassigned)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
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
    _Pile.basket => null,
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

  /// Where else a garment in this pile can go, in words.
  ///
  /// The gap this fills: a garment put in the basket by mistake had no way
  /// back out at all, and one in the machine could only go forwards. Every
  /// laundry pile can now return a garment to the wardrobe.
  ///
  /// `beingWashed` is deliberately not offered from the basket. Starting a
  /// wash is `LaundryController.start`, which *records* the wash — moving a
  /// garment into the drum by hand would put it there with no record, and
  /// "times washed" and every later fading judgement rest on that record.
  List<(String, LifecycleState)> get _alsoGoesTo => switch (pile) {
    _Pile.basket => const [('Take out of the laundry', LifecycleState.active)],
    _Pile.washing => const [
      ('Take out of the laundry', LifecycleState.active),
      ('Back to the basket', LifecycleState.inLaundry),
    ],
    // Putting it away is the forward action, so the useful extra here is the
    // jumper that came out still damp.
    _Pile.drying => const [('Back to the basket', LifecycleState.inLaundry)],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stages = context.stageColors;
    final next = _next;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (next != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: stages.colorOf(next.$3),
                  foregroundColor: stages.onColorOf(next.$3),
                ),
                onPressed: () => ref.read(laundryControllerProvider).move([
                  for (final item in items) item.id,
                ], next.$3),
                icon: Icon(next.$2),
                label: Text('${next.$1} — all ${items.length}'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: GroupCard(
            title: '${items.length} ${items.length == 1 ? 'item' : 'items'}',
            children: [
              for (final item in items)
                ListTile(
                  // The picture enlarges; the rest of the row opens the garment.
                  leading: EnlargeOnTap(
                    item: item,
                    child: ClipRRect(
                      borderRadius: context.rinse.tileBorderRadius,
                      child: ItemThumbnail(item: item, size: 44),
                    ),
                  ),
                  title: Text(
                    item.displayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(item.colorClass.label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (next != null)
                        IconButton(
                          onPressed: () => ref
                              .read(laundryControllerProvider)
                              .move([item.id], next.$3),
                          icon: Icon(next.$2),
                          tooltip: next.$1,
                        ),
                      // Spelled out rather than given a second glyph. The
                      // one-tap icon beside it is the common move and earns
                      // its shorthand; everything else here is occasional,
                      // and an unlabelled symbol for "take this back out of
                      // the wash" is a symbol nobody finds.
                      if (_alsoGoesTo.isNotEmpty)
                        PopupMenuButton<LifecycleState>(
                          onSelected: (stage) => ref
                              .read(laundryControllerProvider)
                              .move([item.id], stage),
                          tooltip: 'Move this somewhere else',
                          itemBuilder: (_) => [
                            for (final (label, stage) in _alsoGoesTo)
                              PopupMenuItem(value: stage, child: Text(label)),
                          ],
                        ),
                    ],
                  ),
                  onTap: () => context.push('/item/${item.id.value}'),
                ),
            ],
          ),
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
      _Pile.basket => 'Nothing to wash',
      _Pile.washing => 'Nothing in the washer',
      _Pile.drying => 'Nothing drying',
    },
    detail: switch (pile) {
      _Pile.basket =>
        'Put something in the wash from its own page, or select several in '
            'the Wardrobe, and the loads to run will appear here.',
      _Pile.washing => 'Start a load from the Basket tab.',
      _Pile.drying => 'Move a load out of the washer and it will show up here.',
    },
  );
}

/// The colour of one garment in the "What did you wear today?" stack.
///
/// Taken from the theme rather than fixed: a navy hoodie and navy jeans drawn
/// in their own colours all but vanish on the Dark and AMOLED wells. These are
/// the accent, the muted ink and the ink, each well clear of the card and the
/// well in all three modes.
@visibleForTesting
Color wornTodayStackFill(ColorScheme scheme, GlyphKind kind) => switch (kind) {
  GlyphKind.hoodie => scheme.primary,
  GlyphKind.jeans => scheme.onSurfaceVariant,
  _ => scheme.onSurface,
};

/// Fades the edge of a horizontally scrolling row that has more beyond it, so
/// it is plain that it scrolls. Nothing is faded on a side that is at its end.
class _FadedEdges extends StatelessWidget {
  const _FadedEdges({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  static const _fade = 20.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        // Before the first layout there is no position: assume more to the
        // right, which is the case that needs the hint.
        final position =
            controller.hasClients && controller.position.hasContentDimensions
            ? controller.position
            : null;
        final more =
            position == null || position.pixels < position.maxScrollExtent - 1;
        final before = position != null && position.pixels > 1;
        final f = (_fade / constraints.maxWidth).clamp(0.0, 0.2);
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [
              if (before) const Color(0x00FFFFFF) else const Color(0xFFFFFFFF),
              const Color(0xFFFFFFFF),
              const Color(0xFFFFFFFF),
              if (more) const Color(0x00FFFFFF) else const Color(0xFFFFFFFF),
            ],
            stops: [0, f, 1 - f, 1],
          ).createShader(rect),
          child: child,
        );
      },
      child: child,
    ),
  );
}
