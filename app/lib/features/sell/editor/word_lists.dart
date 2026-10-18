/// The two lists a listing carries in words: the style words buyers search by,
/// and the flaws they should be told about.
///
/// Both are things to add and to take away, so both are a box with an Add
/// button over what has been added. They differ in what an entry is: a style
/// word is one word or two ("vintage", "button up") and becomes a hashtag, so
/// a comma is a separator; a flaw is a sentence ("small mark on the left
/// cuff") that may have a comma in it, so it is not split.
///
/// **Nothing here says a garment has no flaws.** An empty list means none were
/// listed, which is a different thing, and the line shown for it says only
/// that. The description the core composes follows the same rule, and a screen
/// that offered "no flaws" as an entry would be undoing it.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../core/theme.dart';
import 'edit_session.dart';
import 'fields.dart';

/// [text] cut at commas and line breaks into trimmed, non-empty entries.
List<String> splitEntries(String text) => [
  for (final part in text.split(RegExp(r'[,\n]')))
    if (part.trim().isNotEmpty) part.trim(),
];

/// [existing] with [added] on the end, leaving out any entry already there,
/// whatever its case, and any that repeats within [added].
List<String> withEntries(List<String> existing, List<String> added) {
  final seen = {for (final entry in existing) entry.toLowerCase()};
  return [
    ...existing,
    for (final entry in added)
      if (seen.add(entry.toLowerCase())) entry,
  ];
}

/// A box to type an entry into and the button that adds it.
///
/// Owns its text, which is not part of the listing until it is added, and
/// clears it when it is.
class _AddEntry extends StatefulWidget {
  const _AddEntry({
    required this.label,
    required this.hint,
    required this.buttonLabel,
    required this.onAdd,
    this.splitsOnCommas = false,
  });

  final String label;
  final String hint;

  /// What the Add button is called to a screen reader. On screen it says "Add"
  /// twice in one form, and a screen reader hears only the buttons.
  final String buttonLabel;
  final bool splitsOnCommas;
  final void Function(List<String> entries) onAdd;

  @override
  State<_AddEntry> createState() => _AddEntryState();
}

class _AddEntryState extends State<_AddEntry> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text;
    final entries = widget.splitsOnCommas
        ? splitEntries(text)
        : [if (text.trim().isNotEmpty) text.trim()];
    if (entries.isEmpty) return;

    widget.onAdd(entries);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            hintMaxLines: 2,
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
          onSubmitted: (_) => _add(),
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: FilledButton.tonal(
          onPressed: _add,
          child: Semantics(
            label: widget.buttonLabel,
            excludeSemantics: true,
            child: const Text('Add'),
          ),
        ),
      ),
    ],
  );
}

/// Style words, as chips that can be taken off.
class StyleWordsEditor extends StatelessWidget {
  const StyleWordsEditor({
    required this.listing,
    required this.session,
    super.key,
  });

  final Listing listing;
  final ListingEditSession session;

  @override
  Widget build(BuildContext context) {
    final words = listing.styleWords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SubHeading('Style words'),
        const SizedBox(height: 4),
        const QuietText(
          'Words a buyer would search for: the cut, the style, the print. '
          'They become hashtags, and Depop counts five.',
        ),
        if (words.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final word in words)
                InputChip(
                  label: Text(word),
                  onDeleted: () => session.edit(
                    (listing) => listing.copyWith(
                      styleWords: [
                        for (final held in listing.styleWords)
                          if (held != word) held,
                      ],
                    ),
                  ),
                  deleteButtonTooltipMessage: 'Remove $word',
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        _AddEntry(
          label: 'Add a style word',
          hint: 'vintage, crewneck',
          buttonLabel: 'Add style word',
          splitsOnCommas: true,
          onAdd: (entries) => session.edit(
            (listing) => listing.copyWith(
              styleWords: withEntries(listing.styleWords, entries),
            ),
          ),
        ),
      ],
    );
  }
}

/// Flaws, one to a row, each with a button to take it off.
class FlawsEditor extends StatelessWidget {
  const FlawsEditor({required this.listing, required this.session, super.key});

  final Listing listing;
  final ListingEditSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flaws = listing.flaws;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SubHeading('Flaws'),
        const SizedBox(height: 4),
        const QuietText(
          'Anything a buyer would want to know: a mark, pilling, a loose '
          'thread. Photograph each one.',
        ),
        const SizedBox(height: 8),
        if (flaws.isEmpty)
          const QuietText(
            'None listed. The description lists only what you add.',
          )
        else
          for (final (index, flaw) in flaws.indexed)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.rinse.well,
                  borderRadius: context.rinse.tileBorderRadius,
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(flaw, style: theme.textTheme.bodyMedium),
                        ),
                      ),
                      TextButton(
                        onPressed: () => session.edit(
                          (listing) => listing.copyWith(
                            flaws: [
                              for (final (i, held) in listing.flaws.indexed)
                                if (i != index) held,
                            ],
                          ),
                        ),
                        // Said in full to a screen reader, which would
                        // otherwise hear "Remove" once for every flaw.
                        child: Semantics(
                          label: 'Remove: $flaw',
                          excludeSemantics: true,
                          child: const Text('Remove'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        const SizedBox(height: 8),
        _AddEntry(
          label: 'Add a flaw',
          hint: 'faint stain near the hem',
          buttonLabel: 'Add flaw',
          onAdd: (entries) => session.edit(
            (listing) =>
                listing.copyWith(flaws: withEntries(listing.flaws, entries)),
          ),
        ),
      ],
    );
  }
}
