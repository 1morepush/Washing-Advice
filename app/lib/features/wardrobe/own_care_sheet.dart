/// Telling the app how a garment should be washed.
///
/// The app could infer care from fabric and read it off a tag. The one thing
/// it could not do was be *told* — which leaves nothing to do about the
/// commonest gap of all: a label worn illegible, cut out because it itched, or
/// never sewn in.
///
/// Partial on purpose. Somebody in that position knows "it is wool, wash it
/// cold, do not tumble it" and has no opinion about a bleach symbol. A form
/// demanding a complete care profile would be inviting them to invent the
/// fields they are unsure of, and an invented instruction is worse than a
/// rule-table default — the default at least knows it is a default.
///
/// So every control here has an "leave it to the app" position, and only what
/// is actually set is stated. The rest stays with the rule table, which is
/// what the confidence chip on the item goes on saying.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

/// Collects what the user knows about washing [item], or null if they backed
/// out.
///
/// An empty result is meaningful rather than a cancellation: it is how
/// somebody takes back everything they said and hands the garment back to the
/// rule table.
Future<CareConstraint?> showOwnCareSheet(
  BuildContext context, {
  required WardrobeItem item,
}) => showModalBottomSheet<CareConstraint>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _OwnCareSheet(item: item),
);

class _OwnCareSheet extends StatefulWidget {
  const _OwnCareSheet({required this.item});

  final WardrobeItem item;

  @override
  State<_OwnCareSheet> createState() => _OwnCareSheetState();
}

class _OwnCareSheetState extends State<_OwnCareSheet> {
  late WashMethod? _method = widget.item.ownCare?.method;
  late int? _maxTempC = widget.item.ownCare?.maxTempC;
  late bool? _tumbleDry = widget.item.ownCare?.tumbleDryAllowed;
  late bool? _dryClean = widget.item.ownCare?.doNotDryClean;

  /// The temperatures a dial actually offers, plus the cold most machines
  /// label rather than number.
  static const _temperatures = [20, 30, 40, 60, 90];

  CareConstraint get _stated => CareConstraint(
    method: _method,
    maxTempC: _maxTempC,
    tumbleDryAllowed: _tumbleDry,
    doNotDryClean: _dryClean,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How to wash it', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'For a label that has worn away, been cut out, or was never '
                'there. Set only what you know — the app keeps working the '
                'rest out from the fabric.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),

              _Field(
                label: 'Washing',
                child: _Choices<WashMethod>(
                  values: WashMethod.values,
                  selected: _method,
                  label: (m) => m.label,
                  onChanged: (m) => setState(() => _method = m),
                ),
              ),
              _Field(
                label: 'No hotter than',
                child: _Choices<int>(
                  values: _temperatures,
                  selected: _maxTempC,
                  label: (t) => '$t°C',
                  onChanged: (t) => setState(() => _maxTempC = t),
                ),
              ),
              _Field(
                label: 'Tumble drying',
                child: _Choices<bool>(
                  values: const [true, false],
                  selected: _tumbleDry,
                  label: (allowed) => allowed ? 'Allowed' : 'Do not',
                  onChanged: (v) => setState(() => _tumbleDry = v),
                ),
              ),
              _Field(
                label: 'Dry cleaning',
                child: _Choices<bool>(
                  values: const [false, true],
                  selected: _dryClean,
                  label: (banned) => banned ? 'Do not' : 'Allowed',
                  onChanged: (v) => setState(() => _dryClean = v),
                ),
              ),

              const SizedBox(height: 12),
              // Said before the button, not after it. What this does to the
              // garment is the whole question, and the wash plan reads the
              // answer.
              Text(
                _stated.statesNothing
                    ? 'Nothing set, so this garment goes back to being worked '
                          'out from its fabric.'
                    : 'This will be used instead of the label, and the wash '
                          'plan will follow it.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _method = null;
                      _maxTempC = null;
                      _tumbleDry = null;
                      _dryClean = null;
                    }),
                    child: const Text('Clear'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _stated),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        child,
      ],
    ),
  );
}

/// One row of choices, any of which can be turned back off.
///
/// Tapping the selected chip clears it, which is how a field returns to "the
/// app works it out". Without that the sheet would be a one-way door: every
/// field somebody touched by accident would stay asserted forever.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) label;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in values)
        ChoiceChip(
          label: Text(label(value)),
          selected: selected == value,
          onSelected: (chosen) => onChanged(chosen ? value : null),
        ),
    ],
  );
}
