/// The details Depop's form asks for, in the order it asks for them.
///
/// Each one feeds the description above, which recomposes as it is typed in,
/// and most are also something Depop wants chosen or typed in its own form —
/// the category, the condition, the colours — so they are shown as things to
/// copy across, not as a second form to post.
///
/// **The category is a suggestion.** Depop publishes no list of its categories
/// and the core's paths (`Tops › Sweatshirts`) are a reconstruction of what
/// its pickers offer, so the line says so and offers it to copy. The person
/// picks the real one in Depop, with this beside it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../core/providers.dart';
import '../../../widgets/rinse_kit.dart';
import 'colour_picker.dart';
import 'condition_picker.dart';
import 'edit_session.dart';
import 'fields.dart';
import 'measurement_fields.dart';
import 'word_lists.dart';

/// Space between one field of the form and the next.
const SizedBox _gap = SizedBox(height: 16);

/// Where Depop would file this, as text to copy; null when it depends on a
/// department that has not been chosen.
///
/// Most things are filed the same way for both departments. Blouses, bras and
/// tights are not, and until Men or Women is chosen there is no one answer to
/// give for those, so none is.
String? categoryFor(Listing listing) {
  final department = listing.department;
  if (department != null) {
    return depopCategoryFor(listing.itemType, department);
  }

  final men = depopCategoryFor(listing.itemType, DepopDepartment.men);
  final women = depopCategoryFor(listing.itemType, DepopDepartment.women);
  return men == women ? men : null;
}

class InfoSection extends ConsumerWidget {
  const InfoSection({required this.listing, required this.session, super.key});

  final Listing listing;
  final ListingEditSession session;

  /// Sets an optional text field, or takes it back when it is emptied.
  void _text(String text, Listing Function(Listing, String?) set) => session
      .edit((listing) => set(listing, text.trim().isEmpty ? null : text));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemId = listing.itemId;
    final garment = itemId == null
        ? null
        : ref.watch(itemProvider(itemId)).valueOrNull;

    return EditorSection(
      title: 'Info',
      intro:
          "What Depop's form asks for. Each change shows in the description.",
      children: [
        EditorTextField(
          key: const ValueKey('title'),
          value: listing.title,
          label: 'Title',
          hint:
              'Brand, item, style words — e.g. Nike vintage crewneck '
              'sweatshirt grey',
          helper: listing.title.trim().isEmpty
              ? "Buyers search by these words, and it's the first line of "
                    'the description.'
              : null,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
          onChanged: (text) =>
              session.edit((listing) => listing.copyWith(title: text)),
        ),
        _gap,
        _CategoryBlock(listing: listing, session: session),
        _gap,
        EditorTextField(
          key: const ValueKey('brand'),
          value: listing.brand ?? '',
          label: 'Brand',
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onChanged: (text) => _text(
            text,
            (listing, brand) => brand == null
                ? listing.copyWith(clearBrand: true)
                : listing.copyWith(brand: brand),
          ),
        ),
        _gap,
        EditorTextField(
          key: const ValueKey('size'),
          value: listing.sizeLabel ?? '',
          label: 'Size',
          hint: 'As printed on the tag — M, W32 L30, UK 10',
          textInputAction: TextInputAction.next,
          onChanged: (text) => _text(
            text,
            (listing, size) => size == null
                ? listing.copyWith(clearSizeLabel: true)
                : listing.copyWith(sizeLabel: size),
          ),
        ),
        _gap,
        ConditionPicker(
          key: const ValueKey('condition'),
          listing: listing,
          session: session,
          garment: garment,
        ),
        _gap,
        ColourPicker(
          key: const ValueKey('colours'),
          listing: listing,
          session: session,
        ),
        _gap,
        EditorTextField(
          key: const ValueKey('material'),
          value: listing.material ?? '',
          label: 'Material',
          hint: 'As the label says — 80% cotton, 20% polyester',
          textInputAction: TextInputAction.next,
          onChanged: (text) => _text(
            text,
            (listing, material) => material == null
                ? listing.copyWith(clearMaterial: true)
                : listing.copyWith(material: material),
          ),
        ),
        _gap,
        StyleWordsEditor(
          key: const ValueKey('style-words'),
          listing: listing,
          session: session,
        ),
        _gap,
        EditorTextField(
          key: const ValueKey('era'),
          value: listing.era ?? '',
          label: 'Era',
          hint: '90s, Y2K — only if you know',
          textInputAction: TextInputAction.next,
          onChanged: (text) => _text(
            text,
            (listing, era) => era == null
                ? listing.copyWith(clearEra: true)
                : listing.copyWith(era: era),
          ),
        ),
        _gap,
        MeasurementFields(
          key: const ValueKey('measurements'),
          listing: listing,
          session: session,
        ),
        _gap,
        FlawsEditor(
          key: const ValueKey('flaws'),
          listing: listing,
          session: session,
        ),
        _gap,
        EditorTextField(
          key: const ValueKey('notes'),
          value: listing.notes ?? '',
          label: 'Notes',
          hint: 'Anything else a buyer should read',
          helper: 'Goes at the end of the description.',
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          onChanged: (text) => _text(
            text,
            (listing, notes) => notes == null
                ? listing.copyWith(clearNotes: true)
                : listing.copyWith(notes: notes),
          ),
        ),
      ],
    );
  }
}

/// Department, item type, and the category Depop would file it under.
class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({required this.listing, required this.session});

  final Listing listing;
  final ListingEditSession session;

  Future<void> _copy(BuildContext context, String category) async {
    await Clipboard.setData(ClipboardData(text: category));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied — $category')));
  }

  @override
  Widget build(BuildContext context) {
    final category = categoryFor(listing);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SubHeading('Category'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final department in DepopDepartment.values)
              ChoiceChip(
                label: Text(department.label),
                selected: listing.department == department,
                onSelected: (on) => session.edit(
                  (listing) => on
                      ? listing.copyWith(department: department)
                      : listing.copyWith(clearDepartment: true),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ItemType>(
          initialValue: listing.itemType,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Item type',
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
          items: [
            for (final type in ItemType.values)
              DropdownMenuItem(value: type, child: Text(type.label)),
          ],
          onChanged: (type) {
            if (type == null) return;
            session.edit((listing) => listing.copyWith(itemType: type));
          },
        ),
        const SizedBox(height: 12),
        InsetPanel(
          child: category == null
              ? const QuietText(
                  'Pick Men or Women to see where Depop files this.',
                )
              : SelectableText(
                  category,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        const QuietText(
          "A guide to copy. Depop's own list may word it differently, so "
          'pick the closest one there.',
        ),
        if (category != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _copy(context, category),
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copy category'),
            ),
          ),
      ],
    );
  }
}
