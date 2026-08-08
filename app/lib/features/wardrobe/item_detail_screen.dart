/// One item, and everything the app believes about it.
///
/// The organising idea is that a care instruction is worth nothing unless the
/// user can see where it came from. "Wash at 30°" is an order; "wash at 30°,
/// from the care label" is a fact they can check, and "wash at 30°, assumed"
/// is an invitation to scan the label. Every claim on this screen therefore
/// carries its provenance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/confidence_chip.dart';
import '../../widgets/item_thumbnail.dart';
import '../history/wear_recorder.dart';
import 'cutout_controller.dart';
import 'care_text.dart';
import 'report_wear_sheet.dart';

class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({required this.id, super.key});

  final ItemId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemProvider(id));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/')),
        title: Text(item.valueOrNull?.displayName ?? 'Item'),
        actions: [
          if (item.valueOrNull case final WardrobeItem value) ...[
            IconButton(
              onPressed: () => showReportWearSheet(context, value),
              icon: const Icon(Icons.report_problem_outlined),
              tooltip: 'Report wear',
            ),
            IconButton(
              onPressed: () => context.go('/item/${id.value}/edit'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
            ),
            // Behind an overflow menu rather than an icon beside the others:
            // this is the one action here with no undo, and it should never
            // be one accidental tap away from "Edit".
            PopupMenuButton<String>(
              onSelected: (choice) => _confirmAndDelete(context, ref, value),
              itemBuilder: (menuContext) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: Theme.of(menuContext).colorScheme.error,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Delete',
                        style: TextStyle(
                          color: Theme.of(menuContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: item.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (value) => value == null
            ? const Center(child: Text('This item no longer exists.'))
            : _Details(item: value),
      ),
    );
  }
}

/// Asks, then removes an item for good.
///
/// Separate from retiring — the lifecycle states on the edit screen (donated,
/// sold, discarded) that keep an item's history for statistics while taking it
/// out of the active wardrobe. This is for the record that should never have
/// existed at all: a duplicate, a scan of the wrong garment, a test entry.
/// There is no lifecycle to move it to, because nothing is being kept.
Future<void> _confirmAndDelete(
  BuildContext context,
  WidgetRef ref,
  WardrobeItem item,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete this item?'),
      content: Text(
        '"${item.displayName}" and its photos will be gone for good. This '
        "can't be undone.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.errorContainer,
            foregroundColor: Theme.of(
              dialogContext,
            ).colorScheme.onErrorContainer,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;
  if (!context.mounted) return;

  // Every file this item ever produced: the originals and any cutout made
  // from them. Left behind, they are bytes nothing will ever read again —
  // and on a platform that already has a storage-quota problem, an orphaned
  // photo per deleted item is exactly the kind of thing that adds up.
  final images = ref.read(imageStoreProvider);
  for (final photo in item.photos.photos) {
    await images.delete(photo.uri);
    if (photo.cutoutUri case final String cutoutUri) {
      await images.delete(cutoutUri);
    }
  }

  // A garment that no longer exists cannot stay in a saved outfit — the same
  // cleanup retiring an item already relies on, including dropping an outfit
  // left with fewer than two members.
  await ref.read(outfitRepositoryProvider).removeItem(item.id);

  await ref.read(wardrobeRepositoryProvider).delete(item.id);

  ref
    ..invalidate(ownedItemsProvider)
    ..invalidate(ownedCountProvider)
    ..invalidate(coWearGraphProvider)
    ..invalidate(savedOutfitsProvider)
    ..invalidate(knownBrandsProvider);

  if (!context.mounted) return;
  context.go('/');
}

class _Details extends StatelessWidget {
  const _Details({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final care = item.effectiveCare;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // Only when there is a real picture. A 160-pixel colour swatch is a
        // large coloured circle telling the user nothing they cannot already
        // see in the list, so the space goes to the facts instead.
        if (item.photos.displayImageUri != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(child: ItemThumbnail(item: item, size: 160)),
          ),
        if (CutoutController.isAvailableFor(item)) _CutoutPrompt(id: item.id),
        if (item.needsCareTagScan) _ScanPrompt(id: item.id),
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
            _Fact(
              label: 'Fabric',
              value: item.composition.value.label,
              belief: item.composition,
            ),
            _Fact(
              label: 'Colour',
              value: item.colors.value.colors
                  .map((c) => c.name ?? c.hex)
                  .join(', '),
              belief: item.colors,
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
            _Fact(label: 'Wash', value: washSummary(care.wash)),
            _Fact(label: 'Dry', value: drySummary(care.dry)),
            _Fact(label: 'Iron', value: ironSummary(care.iron)),
            _Fact(label: 'Bleach', value: care.bleach.label),
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
            _Fact(label: 'Sorts into', value: item.colorClass.label),
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
class _ScanPrompt extends StatelessWidget {
  const _ScanPrompt({required this.id});

  final ItemId id;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
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
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () => context.go('/item/${id.value}/care-label'),
              child: const Text('Scan the label'),
            ),
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
class _CutoutPrompt extends ConsumerWidget {
  const _CutoutPrompt({required this.id});

  final ItemId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(cutoutControllerProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              switch (status) {
                CutoutStatus.working => 'Removing the background…',
                CutoutStatus.failed =>
                  'The garment could not be told apart from its background.',
                _ => 'Remove the background to make this easier to spot.',
              },
              style: theme.textTheme.bodySmall?.copyWith(
                color: status == CutoutStatus.failed
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (status == CutoutStatus.working)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton(
              onPressed: () =>
                  ref.read(cutoutControllerProvider.notifier).generate(id),
              child: Text(
                status == CutoutStatus.failed ? 'Try again' : 'Clean up',
              ),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            if (trailing case final Widget trailing) trailing,
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}

/// A single labelled claim, with its provenance when it has one.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.belief});

  final String label;
  final String value;

  /// The belief this fact came from, if it is an inference rather than
  /// something derived or entered.
  final Confident<Object>? belief;

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
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
          if (belief case final Confident<Object> belief) ...[
            const SizedBox(width: 8),
            ConfidenceChip.of(belief),
          ],
        ],
      ),
    );
  }
}
