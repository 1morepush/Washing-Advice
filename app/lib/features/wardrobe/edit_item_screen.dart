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
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/status_message.dart';
import '../../widgets/back_navigation.dart';
import 'edit_item_fields.dart';

class EditItemScreen extends ConsumerWidget {
  const EditItemScreen({required this.id, super.key});

  final ItemId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemProvider(id));

    return Scaffold(
      appBar: AppBar(
        leading: backLeading(context, '/item/${id.value}'),
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
    if (mounted) context.backOr('/item/${saved.id.value}');
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
              FieldHeading(
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
              FieldHeading(
                title: 'Fabric',
                belief: widget.original.composition,
                isEdited: !_sameComposition,
              ),
              CompositionEditor(
                composition: _composition,
                onChanged: (value) => setState(() => _composition = value),
              ),

              const SizedBox(height: 24),
              FieldHeading(
                title: 'Color',
                belief: widget.original.colors,
                isEdited: !_sameColors,
              ),
              ColorEditor(
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
                  // Not "Removed". That is what Delete does, and it is a
                  // tombstone rather than a status anyone sets by hand.
                  for (final state in LifecycleState.values)
                    if (state != LifecycleState.removed)
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
              CarePreview(item: preview, theme: theme),
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
                        context.backOr('/item/${widget.original.id.value}'),
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
