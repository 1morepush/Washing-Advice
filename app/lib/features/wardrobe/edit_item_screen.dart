/// Correcting what the app believes about an item.
///
/// The provenance ladder tops out here. Everything the camera produces is an
/// inference; everything the rule table derives rests on one. A person looking
/// at the actual garment knows things neither can — that it already shrank
/// once, that the "wool" is acrylic, that the label is wrong. So an edit is
/// recorded at [Provenance.userEdited] and outranks every other source.
///
/// The consequence that matters: changing the fabric **re-resolves the care**.
/// A screen that let someone correct 100% wool to 100% acrylic while still
/// recommending a wool cycle would be worse than one that never let them edit
/// at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/confidence_chip.dart';
import '../../widgets/status_message.dart';
import 'care_text.dart';

class EditItemScreen extends ConsumerWidget {
  const EditItemScreen({required this.id, super.key});

  final ItemId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemProvider(id));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/item/${id.value}')),
        title: const Text('Edit item'),
      ),
      body: item.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StatusMessage.failure(
          title: 'Could not open this item',
          error: error,
        ),
        data: (value) => value == null
            ? const Center(child: Text('This item no longer exists.'))
            : _Form(original: value),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.original});

  final WardrobeItem original;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final TextEditingController _name = TextEditingController(
    text: widget.original.name,
  );
  late final TextEditingController _brand = TextEditingController(
    text: widget.original.brand?.value ?? '',
  );
  late final TextEditingController _size = TextEditingController(
    text: widget.original.sizeLabel ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.original.notes ?? '',
  );

  late ItemType _type = widget.original.type.value;
  late List<ItemColor> _colors = [...widget.original.colors.value.colors];
  late Map<Fiber, int> _composition = {
    ...widget.original.composition.value.percentages,
  };
  late bool _isFavorite = widget.original.isFavorite;
  late LifecycleState _lifecycle = widget.original.lifecycle;

  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _size.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The item as it would be saved, with care re-derived.
  ///
  /// Built on every rebuild rather than only on save, so the care preview at
  /// the bottom of the form reflects the edit *before* the user commits to it.
  WardrobeItem get _edited {
    final original = widget.original;
    final brand = _brand.text.trim();

    final changed = original.copyWith(
      name: _name.text.trim().isEmpty ? original.name : _name.text.trim(),
      // Every corrected field is re-stamped as the user's, which is what makes
      // it outrank the camera on any future resolution.
      type: _type == original.type.value
          ? original.type
          : Confident.fromUser(_type),
      composition: _sameComposition
          ? original.composition
          : Confident.fromUser(FabricComposition(_composition)),
      // `ordered`, not the plain constructor: a hand-picked list carries no
      // measured coverage, and the order the user put them in is the only
      // statement of which one the garment mostly is.
      colors: _sameColors
          ? original.colors
          : Confident.fromUser(ColorPalette.ordered(_colors)),
      brand: brand.isEmpty ? null : Confident.fromUser(brand),
      sizeLabel: _size.text.trim().isEmpty ? null : _size.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      isFavorite: _isFavorite,
      lifecycle: _lifecycle,
      updatedAt: DateTime.now(),
    );

    // `forItem` carries the stored care label through, so correcting the fabric
    // does not throw away what the manufacturer said.
    return changed.copyWith(
      care: ref.read(careResolverProvider).forItem(changed).profile,
    );
  }

  /// Compared by name and by the colour itself, because either can change
  /// alone: swapping Navy for Black keeps the count, and reordering keeps both.
  bool get _sameColors {
    final before = widget.original.colors.value.colors;
    if (before.length != _colors.length) return false;
    return List.generate(
      _colors.length,
      (i) =>
          before[i].name == _colors[i].name && before[i].hex == _colors[i].hex,
    ).every((same) => same);
  }

  bool get _sameComposition {
    final before = widget.original.composition.value.percentages;
    if (before.length != _composition.length) return false;
    return before.entries.every((e) => _composition[e.key] == e.value);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = _edited;
    await ref.read(wardrobeRepositoryProvider).save(saved);

    // A garment that has left the wardrobe for good cannot stay in an outfit.
    // The repository already knows how — drop the item, and delete any outfit
    // left with fewer than two — and nothing was calling it, so retiring
    // something left saved outfits quietly pointing at it.
    //
    // `isOwned`, emphatically not `isWearable`: an item in the laundry basket
    // is not wearable this minute and is coming back on Tuesday. Tearing it
    // out of every saved outfit because it is in the wash would be a far worse
    // bug than the one being fixed, and the two predicates are one word apart.
    if (widget.original.lifecycle.isOwned && !saved.lifecycle.isOwned) {
      await ref.read(outfitRepositoryProvider).removeItem(saved.id);
      ref.invalidate(savedOutfitsProvider);
    }

    // The detail screen reads through a FutureProvider, which caches. Without
    // this the user returns to the values they just changed.
    ref.invalidate(itemProvider(saved.id));
    ref.invalidate(knownBrandsProvider);
    if (mounted) context.go('/item/${saved.id.value}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _edited;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _brand,
                decoration: const InputDecoration(labelText: 'Brand'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _size,
                decoration: const InputDecoration(labelText: 'Size'),
              ),

              const SizedBox(height: 24),
              _FieldHeading(
                title: 'Type',
                belief: widget.original.type,
                isEdited: _type != widget.original.type.value,
              ),
              DropdownButtonFormField<ItemType>(
                initialValue: _type,
                isExpanded: true,
                items: [
                  for (final type in ItemType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: (value) => setState(() => _type = value ?? _type),
              ),

              const SizedBox(height: 24),
              _FieldHeading(
                title: 'Fabric',
                belief: widget.original.composition,
                isEdited: !_sameComposition,
              ),
              _CompositionEditor(
                composition: _composition,
                onChanged: (value) => setState(() => _composition = value),
              ),

              const SizedBox(height: 24),
              _FieldHeading(
                title: 'Color',
                belief: widget.original.colors,
                isEdited: !_sameColors,
              ),
              _ColorEditor(
                colors: _colors,
                onChanged: (value) => setState(() => _colors = value),
              ),

              const SizedBox(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isFavorite,
                onChanged: (value) => setState(() => _isFavorite = value),
                title: const Text('Favorite'),
              ),
              DropdownButtonFormField<LifecycleState>(
                initialValue: _lifecycle,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final state in LifecycleState.values)
                    DropdownMenuItem(value: state, child: Text(state.label)),
                ],
                onChanged: (value) =>
                    setState(() => _lifecycle = value ?? _lifecycle),
              ),

              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),

              const SizedBox(height: 24),
              _CarePreview(item: preview, theme: theme),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        context.go('/item/${widget.original.id.value}'),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A field's heading, showing where the current value came from.
///
/// So the user can see *what they are overruling*. Correcting something the
/// app read off a care label deserves more hesitation than correcting a guess
/// from a photograph, and the chip is the only thing that says which is which.
class _FieldHeading extends StatelessWidget {
  const _FieldHeading({
    required this.title,
    required this.belief,
    required this.isEdited,
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
                color: theme.colorScheme.primary,
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
class _CompositionEditor extends StatelessWidget {
  const _CompositionEditor({
    required this.composition,
    required this.onChanged,
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
class _CarePreview extends StatelessWidget {
  const _CarePreview({required this.item, required this.theme});

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
class _ColorEditor extends StatefulWidget {
  const _ColorEditor({required this.colors, required this.onChanged});

  final List<ItemColor> colors;
  final ValueChanged<List<ItemColor>> onChanged;

  @override
  State<_ColorEditor> createState() => _ColorEditorState();
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

class _ColorEditorState extends State<_ColorEditor> {
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
