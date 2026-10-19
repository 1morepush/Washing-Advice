/// The editors inside the edit form that are worth a file of their own.
///
/// Fibre composition, colours and the care preview each have their own state
/// or their own rules; the form around them is only layout and saving.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/theme.dart';
import '../../widgets/confidence_chip.dart';
import 'care_text.dart';

/// A field's heading, showing where the current value came from.
///
/// So the user can see *what they are overruling*. Correcting something the
/// app read off a care label deserves more hesitation than correcting a guess
/// from a photograph, and the chip is the only thing that says which is which.
class FieldHeading extends StatelessWidget {
  const FieldHeading({
    required this.title,
    required this.belief,
    required this.isEdited,
    super.key,
  });

  final String title;
  final Confident<Object> belief;
  final bool isEdited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
          if (isEdited)
            Text(
              'Your correction',
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.rinse.textAccent,
              ),
            )
          else
            ConfidenceChip.of(belief),
        ],
      ),
    );
  }
}

/// Percentages by fibre.
///
/// Deliberately not free text. "80% cotton, 20% poly" parsed from a string
/// would be a small parser with its own failure modes, and the failures land
/// on the field that drives every washing decision.
class CompositionEditor extends StatelessWidget {
  const CompositionEditor({
    required this.composition,
    required this.onChanged,
    super.key,
  });

  final Map<Fiber, int> composition;
  final ValueChanged<Map<Fiber, int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = composition.values.fold(0, (sum, value) => sum + value);
    final entries = composition.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text(entry.key.label)),
                Expanded(
                  flex: 4,
                  child: Slider(
                    value: entry.value.toDouble(),
                    max: 100,
                    divisions: 20,
                    label: '${entry.value}%',
                    onChanged: (value) {
                      final next = {...composition};
                      if (value.round() == 0) {
                        next.remove(entry.key);
                      } else {
                        next[entry.key] = value.round();
                      }
                      onChanged(next);
                    },
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${entry.value}%',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                // Shown, not enforced. Real labels round, and blocking a save
                // at 99% would be pedantry about someone else's trousers.
                total == 100 ? 'Totals 100%' : 'Totals $total%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: total == 100
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.tertiary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _addFibre(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add fiber'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addFibre(BuildContext context) async {
    final remaining = [
      for (final fiber in Fiber.values)
        if (!composition.containsKey(fiber)) fiber,
    ];

    final chosen = await showModalBottomSheet<Fiber>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          for (final fiber in remaining)
            ListTile(
              title: Text(fiber.label),
              onTap: () => Navigator.of(context).pop(fiber),
            ),
        ],
      ),
    );

    if (chosen != null) onChanged({...composition, chosen: 10});
  }
}

/// What the edit does to the washing instructions, before it is committed.
class CarePreview extends StatelessWidget {
  const CarePreview({required this.item, required this.theme, super.key});

  final WardrobeItem item;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final care = item.effectiveCare;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wrapped rather than a row: the chip reads "Confident · from the
            // care label" at its longest, which does not fit beside this
            // heading on a narrow phone once the system text size is raised.
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'How it will be washed',
                  style: theme.textTheme.titleSmall,
                ),
                ConfidenceChip(
                  confidence: item.care.confidence,
                  source: item.care.source,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(washSummary(care.wash), style: theme.textTheme.bodyMedium),
            Text(drySummary(care.dry), style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// The colours the garment actually is.
///
/// Not decoration. This value decides which load the garment goes in and
/// whether the app warns that its dye may run, so a wrong colour is a garment
/// washed with the wrong pile — the failure the whole app exists to prevent.
/// A camera under warm indoor light reads navy as black often enough to matter,
/// and until now there was no way to say so.
///
/// Swatches rather than a colour wheel, plus a hex box for anything the list
/// does not cover. Nobody knows the hex code of their jumper, and a wheel would
/// invite a precision the underlying judgement does not have — but a hex code
/// is exactly what someone copying a colour off a shop listing already has.
class ColorEditor extends StatefulWidget {
  const ColorEditor({required this.colors, required this.onChanged, super.key});

  final List<ItemColor> colors;
  final ValueChanged<List<ItemColor>> onChanged;

  @override
  State<ColorEditor> createState() => _ColorEditorState();
}

/// Beyond this, a stated colour would be recorded and then ignored.
///
/// `ColorPalette.ordered` spreads coverage across the list, and the pile rules
/// only consider a colour covering at least 12% of the garment. A fourth
/// hand-picked colour lands below that line, so offering it would take an
/// answer and quietly discard it.
const _maxColors = 3;

/// Colours garments actually come in, which is not the same as colours.
///
/// Chosen to span the laundry classes — whites, lights, brights, darks — and to
/// include the ones a camera most often mistakes: navy read as black, cream
/// read as white, charcoal read as navy.
const _swatches = <(String, String)>[
  ('White', '#FAFAFA'),
  ('Cream', '#F0EDE5'),
  ('Beige', '#C3B091'),
  ('Gray', '#9A9A9A'),
  ('Charcoal', '#3B3B3B'),
  ('Black', '#1A1A1A'),
  ('Navy', '#1F2A44'),
  ('Blue', '#1E45C8'),
  ('Light blue', '#A8C8E8'),
  ('Denim', '#4A6FA5'),
  ('Teal', '#128C8C'),
  ('Green', '#2E7D32'),
  ('Olive', '#6B7A3A'),
  ('Yellow', '#F2C230'),
  ('Orange', '#E06A1E'),
  ('Red', '#C81E1E'),
  ('Burgundy', '#6E1B2C'),
  ('Pink', '#F2C6D0'),
  ('Purple', '#6B3FA0'),
  ('Brown', '#6B4A2F'),
];

/// The names of the swatches, for the test that holds each to a Depop colour.
///
/// A colour named here ends up on a listing, and `depopColoursFor` in the core
/// is what turns it into one of Depop's. The core cannot read this list — it is
/// the editor's, and private — so the other half of that agreement is a test
/// in the app, which needs the names.
@visibleForTesting
List<String> get swatchNames => [for (final (name, _) in _swatches) name];

class _ColorEditorState extends State<ColorEditor> {
  final _hex = TextEditingController();
  String? _hexError;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  bool get _isFull => widget.colors.length >= _maxColors;

  void _add(ItemColor color) {
    if (_isFull) return;
    widget.onChanged([...widget.colors, color]);
  }

  void _removeAt(int index) => widget.onChanged([
    for (final (i, color) in widget.colors.indexed)
      if (i != index) color,
  ]);

  void _addTyped() {
    final text = _hex.text.trim();
    if (text.isEmpty) return;
    try {
      // Named after itself: a hex code is not a colour name, and inventing one
      // ("Dark blue-ish") would put a guess where the user gave a fact.
      final color = ItemColor.fromHex(text);
      _add(color.copyWith(name: color.hex));
      _hex.clear();
      setState(() => _hexError = null);
    } on FormatException {
      setState(() => _hexError = 'Six hex digits, like #1F2A44.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.colors.isEmpty)
          Text(
            'No color recorded. Pick the one it mostly is.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (index, color) in widget.colors.indexed)
                InputChip(
                  avatar: _Swatch(color: color),
                  label: Text(color.name ?? color.hex),
                  onDeleted: () => _removeAt(index),
                  deleteButtonTooltipMessage: 'Remove this color',
                ),
            ],
          ),
        if (widget.colors.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'The first is the one it mostly is, and decides the load it goes '
              'in.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (_isFull)
          Text(
            'Remove one to add another.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (name, hex) in _swatches)
                ActionChip(
                  avatar: _Swatch(color: ItemColor.fromHex(hex)),
                  label: Text(name),
                  onPressed: () => _add(ItemColor.fromHex(hex, name: name)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _hex,
                  decoration: InputDecoration(
                    labelText: 'Or a hex code',
                    hintText: '#1F2A44',
                    errorText: _hexError,
                  ),
                  onSubmitted: (_) => _addTyped(),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: IconButton.filledTonal(
                  onPressed: _addTyped,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add this color',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A dot of the colour itself.
///
/// Outlined, because the two colours hardest to tell apart from their names —
/// white and cream — are also the two that vanish against a light background
/// without a border.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final ItemColor color;

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      color: Color(0xFF000000 | color.rgb),
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
  );
}
