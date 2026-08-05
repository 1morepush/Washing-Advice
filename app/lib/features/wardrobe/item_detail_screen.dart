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

class _Details extends StatelessWidget {
  const _Details({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    final care = item.effectiveCare;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (item.needsCareTagScan) const _ScanPrompt(),
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
            _Fact(label: 'Wash', value: _washSummary(care.wash)),
            _Fact(label: 'Dry', value: _drySummary(care.dry)),
            _Fact(label: 'Iron', value: _ironSummary(care.iron)),
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

/// The banner asking for a care label scan.
///
/// Shown only when [WardrobeItem.needsCareTagScan] — that is, when the belief
/// is weak enough that acting on it risks damage. Prompting on every item would
/// make the prompt meaningless.
class _ScanPrompt extends StatelessWidget {
  const _ScanPrompt();

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
      child: Row(
        children: [
          Icon(
            Icons.document_scanner_outlined,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'These instructions are a guess. Scan the care label to be sure.',
              style: TextStyle(color: scheme.onTertiaryContainer),
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

// --- Turning care values into sentences ------------------------------------
//
// These read the core's model and phrase it; they never decide anything. A
// temperature or a permission invented here would be laundry logic in the
// presentation layer, which is exactly what the core exists to prevent.

String _washSummary(WashCare wash) {
  if (wash.method == WashMethod.doNotWash) return 'Do not wash';
  final parts = [
    wash.method.label,
    if (wash.maxTempC case final int temp) 'up to $temp°C',
    if (wash.agitation != Agitation.normal) wash.agitation.label.toLowerCase(),
  ];
  return parts.join(', ');
}

String _drySummary(DryCare dry) {
  final parts = [
    if (dry.tumbleDryAllowed)
      'Tumble dry ${dry.tumbleDryHeat.label.toLowerCase()}'
    else
      'Do not tumble dry',
    if (dry.naturalDry case final NaturalDryMethod method) method.label,
    if (dry.dryInShade) 'in the shade',
    if (dry.doNotWring) 'do not wring',
  ];
  return parts.join(', ');
}

String _ironSummary(IronCare iron) {
  if (!iron.isIronable) return 'Do not iron';
  return iron.steamAllowed
      ? '${iron.temperature.label}, steam allowed'
      : '${iron.temperature.label}, no steam';
}
