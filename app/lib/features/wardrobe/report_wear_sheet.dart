/// Reporting that a garment has worn.
///
/// Small, and the last link in a chain that has been complete except for its
/// first step since M1: the core knows that a pilling jumper needs a gentler
/// cycle than its label says, and knows to drop it a fabric class, and had no
/// way to be told that a jumper was pilling.
///
/// Deliberately shows what the report will *do*, because the point is not
/// record-keeping. Marking something as pilling changes how it is washed from
/// the next load onward, and a form that quietly altered laundry advice without
/// saying so would be the same kind of surprise this app exists to avoid.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../history/wear_recorder.dart';

Future<void> showReportWearSheet(BuildContext context, WardrobeItem item) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReportWearSheet(item: item),
    );

class _ReportWearSheet extends ConsumerStatefulWidget {
  const _ReportWearSheet({required this.item});

  final WardrobeItem item;

  @override
  ConsumerState<_ReportWearSheet> createState() => _ReportWearSheetState();
}

class _ReportWearSheetState extends ConsumerState<_ReportWearSheet> {
  WearType _type = WearType.pilling;
  WearSeverity _severity = WearSeverity.moderate;

  /// Whether this report will change how the garment is washed.
  ///
  /// Mirrors `ConditionAssessment.warrantsGentlerCare` rather than restating
  /// the rule: the core decides, and this asks it. A second copy of the
  /// condition here would eventually disagree with the one doing the work.
  bool get _willChangeCare => widget.item.condition
      .record(
        WearObservation(
          type: _type,
          severity: _severity,
          observedAt: DateTime.now(),
        ),
      )
      .warrantsGentlerCare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Report wear', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            widget.item.displayName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in WearType.values)
                ChoiceChip(
                  label: Text(type.label),
                  selected: type == _type,
                  onSelected: (_) => setState(() => _type = type),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<WearSeverity>(
            segments: [
              for (final severity in WearSeverity.values)
                ButtonSegment(value: severity, label: Text(severity.label)),
            ],
            selected: {_severity},
            onSelectionChanged: (chosen) =>
                setState(() => _severity = chosen.first),
          ),
          const SizedBox(height: 16),
          _Consequence(willChangeCare: _willChangeCare),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  await ref
                      .read(wearRecorderProvider)
                      .recordCondition(
                        widget.item.id,
                        type: _type,
                        severity: _severity,
                      );
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Record'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What this report will actually do, stated before it is made.
class _Consequence extends StatelessWidget {
  const _Consequence({required this.willChangeCare});

  final bool willChangeCare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: willChangeCare
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            willChangeCare
                ? Icons.local_laundry_service_outlined
                : Icons.info_outline,
            size: 18,
            color: willChangeCare
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              willChangeCare
                  ? 'This will wash cooler and gentler from now on, and stop '
                        'being tumble dried. A care label describes a new '
                        'garment, and a normal cycle finishes off one that has '
                        'started to go.'
                  : 'Recorded for the history. This one does not change how the '
                        'garment is washed — either it will not get worse in '
                        'the machine, or it is not far enough along yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: willChangeCare
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
