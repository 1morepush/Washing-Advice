/// The body of the item page: facts, care, and what can be done next.
///
/// Split from the screen, which keeps the app bar, the menu and deleting.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../widgets/care_symbol.dart';
import '../../widgets/confidence_chip.dart';
import '../../widgets/item_thumbnail.dart';
import '../history/wear_recorder.dart';
import '../laundry/laundry_controller.dart';
import 'care_text.dart';
import 'cutout_controller.dart';
import 'own_care_sheet.dart';

class ItemDetails extends StatelessWidget {
  const ItemDetails({required this.item, super.key});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final care = item.effectiveCare;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // The garment on its well, photographed or drawn. It used to be left
        // out when there was no picture, because a 160-pixel colour disc told
        // nobody anything the list had not; the silhouette in the garment's
        // own colour does — it is what the garment is — so it always has a
        // place here.
        _Hero(item: item),
        _NameHeading(item: item),
        _Actions(item: item),
        if (CutoutController.isAvailableFor(item))
          _CutoutPrompt(
            id: item.id,
            hasCutout: item.photos.displayPhoto?.hasCutout ?? false,
          ),
        if (item.needsCareTagScan) _ScanPrompt(item: item),
        _Section(
          title: 'What it is',
          children: [
            _Fact(
              label: 'Type',
              value: item.type.value.label,
              belief: item.type,
            ),
            if (item.brand case final Confident<String> brand)
              _Fact(label: 'Brand', value: brand.value, belief: brand),
            if (item.countryOfOrigin case final Confident<String> made)
              _Fact(label: 'Made in', value: made.value, belief: made),
            _Fact(
              label: 'Fabric',
              value: item.composition.value.label,
              belief: item.composition,
            ),
            _Fact(
              label: 'Color',
              value: item.colors.value.colors
                  .map((c) => c.name ?? c.hex)
                  .join(', '),
              belief: item.colors,
              // Colour is the one missing fact that changes what the app
              // *does* rather than only what it displays: with no palette the
              // garment sorts by a default, and the load it lands in is a
              // guess. Worth one tap to fix, from the screen where the gap is
              // visible.
              action: item.colors.value.colors.isEmpty
                  ? TextButton(
                      onPressed: () =>
                          context.push('/item/${item.id.value}/edit'),
                      child: const Text('Set it'),
                    )
                  : null,
            ),
            if (item.sizeLabel case final String size)
              _Fact(label: 'Size', value: size),
          ],
        ),
        _Section(
          // Named for the decision it drives, not for the data it shows.
          title: 'How to wash it',
          trailing: ConfidenceChip(
            confidence: item.care.confidence,
            source: item.care.source,
          ),
          children: [
            // The symbols as the label prints them, beside the words below
            // and never instead of them: a symbol the art does not cover (a
            // 60° wash, three iron dots) is simply absent here and still
            // spelled out in the rows.
            if (careSymbolsFor(care) case final kinds when kinds.isNotEmpty)
              _CareSymbols(kinds: kinds),
            _Fact(label: 'Wash', value: washSummary(care.wash)),
            _Fact(label: 'Dry', value: drySummary(care.dry)),
            _Fact(label: 'Iron', value: ironSummary(care.iron)),
            _Fact(label: 'Bleach', value: care.bleach.label),
            // Shown only when the label actually said something. A garment
            // whose label is silent about dry cleaning would otherwise grow a
            // row asserting a permission nobody gave. The label comes from
            // `careFieldLabel` so this row and the review screen's diff cannot
            // drift into two words for one thing.
            if (dryCleanSummary(care) case final String line)
              _Fact(
                label: careFieldLabel('professional.doNotDryClean'),
                value: line,
              ),
            if (care.warnings.isNotEmpty)
              _Fact(
                label: 'Take care',
                value: care.warnings.map((w) => w.label).join(', '),
              ),
          ],
        ),
        _Section(
          title: 'Laundry',
          children: [
            // An empty palette still produces a colour class, because
            // `ColorClass` has a default and the sorter must put the garment
            // somewhere. Said plainly rather than shown as a decision: it
            // lands in darks because that is the harmless mistake, not because
            // anything looked at the garment.
            _Fact(
              label: 'Sorts into',
              value: item.colors.value.colors.isEmpty
                  ? '${item.colorClass.label} — assumed, no color recorded'
                  : item.colorClass.label,
            ),
            _Fact(label: 'Fabric weight', value: item.fabricClass.label),
            if (item.isLikelyToBleed)
              const _Fact(
                label: 'Dye',
                // The condition is `isLikelyToBleed`, which is already
                // restricted to items washed fewer than three times, so the
                // explanation can state the reason rather than the rule.
                value: 'Still new enough to run — wash separately',
              ),
            if (item.producesLint)
              const _Fact(label: 'Lint', value: 'Sheds onto other fabrics'),
            if (item.attractsLint)
              const _Fact(label: 'Lint', value: 'Shows other fabrics\' lint'),
          ],
        ),
        _Section(
          title: 'Use',
          trailing: _WoreItButton(id: item.id),
          children: [
            _Fact(label: 'Worn', value: '${item.usage.timesWorn} times'),
            _Fact(label: 'Washed', value: '${item.usage.timesWashed} times'),
            if (item.costPerWear case final double cost)
              // With the currency it was recorded in. A bare "4.99" is not a
              // number anyone can act on, and assuming the user's local
              // currency would silently misstate what they paid.
              _Fact(
                label: 'Cost per wear',
                value:
                    '${cost.toStringAsFixed(2)} '
                            '${item.purchase?.currencyCode ?? ''}'
                        .trim(),
              ),
            _Fact(label: 'Status', value: item.lifecycle.label),
          ],
        ),
        if (item.notes case final String notes)
          _Section(
            title: 'Notes',
            children: [_Fact(label: '', value: notes)],
          ),
      ],
    );
  }
}

/// Records a wear.
///
/// On the detail screen rather than the list, because it is a deliberate act
/// and a stray tap in a scrolling list would quietly corrupt the counters that
/// cost-per-wear and "never worn" are computed from.
class _WoreItButton extends ConsumerStatefulWidget {
  const _WoreItButton({required this.id});

  final ItemId id;

  @override
  ConsumerState<_WoreItButton> createState() => _WoreItButtonState();
}

class _WoreItButtonState extends ConsumerState<_WoreItButton> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: _saving
        ? null
        : () async {
            setState(() => _saving = true);
            await ref.read(wearRecorderProvider).recordWear(widget.id);
            if (mounted) setState(() => _saving = false);
          },
    icon: const Icon(Icons.add, size: 18),
    label: const Text('Wore it'),
  );
}

/// The banner asking for a care label scan.
///
/// Shown only when [WardrobeItem.needsCareTagScan] — that is, when the belief
/// is weak enough that acting on it risks damage. Prompting on every item would
/// make the prompt meaningless.
class _ScanPrompt extends ConsumerWidget {
  const _ScanPrompt({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: context.rinse.tileBorderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.document_scanner_outlined,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'These instructions are a guess. Scan the care label to be '
                  'sure.',
                  style: TextStyle(color: scheme.onTertiaryContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Scanning is still the better answer where a label exists, so it
          // keeps the emphasis. Telling the app is the way out for the case
          // scanning cannot reach — worn away, cut out, never sewn in — which
          // this prompt used to have no answer for at all.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () async {
                  final stated = await showOwnCareSheet(context, item: item);
                  if (stated == null) return;
                  await ref
                      .read(wardrobeRecorderProvider)
                      .setOwnCare(item: item, care: stated);
                  ref.invalidate(itemProvider(item.id));
                },
                child: const Text('No label? Tell it'),
              ),
              FilledButton.tonal(
                onPressed: () =>
                    context.push('/item/${item.id.value}/care-label'),
                child: const Text('Scan the label'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Offers to remove the background of an item that still has one.
///
/// Shown only where it can do something: an item with a photograph and no
/// cutout. Items scanned since the feature arrived already have one and never
/// see this.
/// The things you actually came here to do, in words.
///
/// In the body rather than the app bar because that bar was carrying five
/// unlabelled icons and had squeezed the garment's name to "Charco…". An icon
/// is fine for an action people already know is there; it is useless for
/// introducing one, and "ask about a spill" is not a thing anyone goes looking
/// for behind a scrubbing brush.
///
/// A `Wrap`, so a large text scale drops them onto their own lines rather than
/// running off a narrow phone.
class _Actions extends ConsumerWidget {
  const _Actions({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Wrap(
      spacing: 8,
      children: [
        // The one-garment way into the basket. A whole load is what the
        // laundry screen is for; the common case is taking one thing off.
        if (item.lifecycle == LifecycleState.active)
          FilledButton.tonalIcon(
            onPressed: () async {
              await ref.read(laundryControllerProvider).move([
                item.id,
              ], LifecycleState.inLaundry);
              if (context.mounted) context.go('/laundry');
            },
            icon: const Icon(Icons.local_laundry_service_outlined),
            label: const Text('Put in the wash'),
          )
        else if (item.lifecycle.isInLaundryCycle)
          FilledButton.tonalIcon(
            onPressed: () => context.go('/laundry'),
            icon: const Icon(Icons.local_laundry_service),
            label: Text(item.lifecycle.label),
          ),
        TextButton.icon(
          onPressed: () => context.push('/item/${item.id.value}/stain'),
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('Spilled something?'),
        ),
      ],
    ),
  );
}

class _CutoutPrompt extends ConsumerWidget {
  const _CutoutPrompt({required this.id, required this.hasCutout});

  final ItemId id;

  /// Whether there is already a mask, which changes this from an offer into a
  /// second chance. Both are worth having: a cutout the remover got wrong
  /// outranks the untouched photograph everywhere, so "it looks wrong" needs
  /// somewhere to go.
  final bool hasCutout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(cutoutControllerProvider(id));
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            switch (status) {
              CutoutStatus.working => 'Removing the background…',
              CutoutStatus.failed =>
                'The garment could not be told apart from its background. '
                    'You can still mark it out by hand.',
              _ when hasCutout =>
                'If the background removal took part of the garment with it, '
                    'tidy it by hand.',
              _ => 'Remove the background to make this easier to spot.',
            },
            style: theme.textTheme.bodySmall?.copyWith(
              color: status == CutoutStatus.failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (status == CutoutStatus.working)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                // Running the remover again is only worth offering when it has
                // not run yet, or when it failed and might do better on a
                // second attempt at a different moment. Once a mask exists,
                // re-running is pointless — the remover is deterministic, so
                // the same photograph gives the same wrong answer — and the
                // only thing that changes the result is a finger.
                if (!hasCutout)
                  TextButton(
                    onPressed: () => ref
                        .read(cutoutControllerProvider(id).notifier)
                        .generate(),
                    child: Text(
                      status == CutoutStatus.failed ? 'Try again' : 'Clean up',
                    ),
                  ),
                TextButton(
                  onPressed: () => context.push('/item/${id.value}/mask'),
                  child: Text(hasCutout ? 'Tidy by hand' : 'Mark out by hand'),
                ),
                // The last resort, and sometimes the only one that works: no
                // mask rescues a garment photographed against a wall its own
                // colour, with a hand and a shadow in shot. A different
                // photograph is the only thing that changes the answer.
                TextButton(
                  onPressed: () => context.push('/item/${id.value}/retake'),
                  child: const Text('New photo'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A `Wrap`, for the same reason `_Fact` uses one: the trailing
          // widget is a confidence chip whose text runs to "Confident · from
          // the care label", and unflexed beside a heading it overflowed once
          // the system text size went up. Here it drops below the heading
          // instead.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (trailing case final Widget trailing) trailing,
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

/// The contrast a garment needs against its hero tile: higher than a list
/// tile's 1.6, because at 176 px a dim silhouette reads as a smudge.
const heroFloor = 2.5;

/// The garment large, on the soft well every garment tile sits on.
class _Hero extends StatelessWidget {
  const _Hero({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) => Container(
    height: 216,
    color: ItemThumbnail.tileFor(context, item, floor: heroFloor),
    alignment: Alignment.center,
    // `backdrop: false` because the hero is itself the tile, tinted only as
    // far as this garment needs to show (see [ItemThumbnail.tileFor]); the tint a
    // cutout gets in a list would make a second, smaller panel inside it.
    child: ItemThumbnail(item: item, size: 176, backdrop: false),
  );
}

/// The care symbols for this garment, three to a row, each captioned.
///
/// Captioned because a symbol is only legible to somebody who already knows
/// the alphabet, and the person holding the phone often does not.
class _CareSymbols extends StatelessWidget {
  const _CareSymbols({required this.kinds});

  final List<CareSymbolKind> kinds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rinse = context.rinse;
    final edge = rinse.cardEdge;
    const gap = 8.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          // Three columns, fewer when the text is large enough that a caption
          // would not fit a third of the width.
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final columns = scale > 1.4 ? 2 : 3;
          final width = (box.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final kind in kinds)
                Container(
                  width: width,
                  constraints: const BoxConstraints(minHeight: 88),
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                  decoration: BoxDecoration(
                    color: rinse.well,
                    borderRadius: rinse.tileBorderRadius,
                    border: edge == BorderSide.none
                        ? null
                        : Border.fromBorderSide(edge),
                  ),
                  child: Column(
                    children: [
                      CareSymbol(
                        kind: kind,
                        color: theme.colorScheme.onSurface,
                        size: 32,
                        // The caption says the same thing.
                        semanticLabel: '',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        careArt[kind]!.label,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A single labelled claim, with its provenance when it has one.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.belief,
    this.action,
  });

  final String label;
  final String value;

  /// The belief this fact came from, if it is an inference rather than
  /// something derived or entered.
  final Confident<Object>? belief;

  /// Something to do about this fact, shown after the value.
  ///
  /// For the rows where "not known" is worth fixing on the spot. Telling
  /// someone a fact is missing and leaving them to find the screen that sets
  /// it is half an answer.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          // A `Wrap` rather than the value and the chip as two more children
          // of the row. A chip reading "Confident · from the care label" is
          // nearly 200dp wide, and unflexed beside a 110dp label column it
          // overflowed a 320dp phone outright — and a 393dp one as soon as
          // the system text size went up a notch, which is the case this
          // screen is most likely to be read in.
          //
          // The cost is that the chip now sits after the value rather than
          // flush right, so the chips down the screen no longer line up. That
          // is worth it: the alternative is content that cannot be seen at
          // all, and no flex arrangement can say "take your natural width if
          // it fits, shrink if it does not" without measuring the text.
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Never an empty string. A fact the app has nothing to say
                // about used to render as a label, a gap and a lone chip —
                // which reads as a broken screen rather than as missing
                // information, and was reported as one. Colour is the row that
                // hits it: a scan whose palette came back empty leaves an
                // "Unsure · assumed" chip floating beside nothing.
                Text(
                  value.trim().isEmpty ? 'Not known' : value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: value.trim().isEmpty ? null : FontWeight.w700,
                    // Greyed and italic when there is nothing, so absence does
                    // not read as a garment whose colour is called "Not known".
                    color: value.trim().isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                    fontStyle: value.trim().isEmpty ? FontStyle.italic : null,
                  ),
                ),
                if (belief case final Confident<Object> belief)
                  ConfidenceChip.of(belief),
                ?action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The garment's name as the page's heading, with what it is underneath:
/// "Uniqlo · Sweater", built only from what is recorded, so a garment with no
/// brand reads just "Sweater".
class _NameHeading extends StatelessWidget {
  const _NameHeading({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (item.brand case final Confident<String> brand) brand.value,
      item.type.value.label,
    ].where((part) => part.trim().isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.displayName,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
