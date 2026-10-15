/// The review step of a care-label scan: what the label changed.
///
/// Split from the screen, which is only the state switch and the capture
/// steps either side of this.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../widgets/confidence_chip.dart';
import '../../widgets/notice.dart';
import '../wardrobe/care_text.dart';
import 'care_tag_controller.dart';

class CareTagReview extends StatelessWidget {
  const CareTagReview({
    required this.state,
    required this.controller,
    super.key,
  });

  final CareTagReviewing state;
  final CareTagController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final care = state.updated.effectiveCare;
    final overridden = state.resolution.fieldsOverriddenByLabel;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'What the label says',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  ConfidenceChip(
                    confidence: state.reading.confidence,
                    source: Provenance.tagScan,
                  ),
                ],
              ),
              // Said only when it is news. A label in the language the app is
              // already in needs no announcement, and "read in English" on an
              // English label reads as though the app were unsure.
              if (foreignLanguageName(state.reading.language)
                  case final String language) ...[
                Notice(
                  icon: Icons.translate,
                  text:
                      'This label is in $language. The symbols are the same in '
                      'every country, so the instructions below come from '
                      'those; the wording is shown as printed.',
                ),
                const SizedBox(height: 8),
              ],

              if (state.images.length > 1) ...[
                Notice(
                  icon: Icons.photo_library_outlined,
                  text:
                      'Read from ${state.images.length} photos together, as '
                      'one label.',
                ),
                const SizedBox(height: 8),
              ],

              // What this photograph did not read, kept from the last time
              // the label was scanned. Said plainly and with a way out: a
              // merge keeps a field the earlier scan got *wrong* whenever the
              // new one is silent about it, and presenting that as freshly
              // read would be the app being quietly more certain than it is.
              if (state.keptFromEarlier.isNotEmpty) ...[
                _KeptNotice(
                  fields: state.keptFromEarlier,
                  onReplace: controller.replaceEarlierLabel,
                ),
                const SizedBox(height: 8),
              ],

              const SizedBox(height: 12),

              // The changes first. Everything else on this screen is
              // confirmation; this is the part that is news.
              if (overridden.isNotEmpty)
                _Changes(
                  fields: overridden,
                  before: state.previous,
                  after: care,
                )
              else
                _NoChanges(hasLabel: true),

              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How it will be washed',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      _Line(label: 'Wash', value: washSummary(care.wash)),
                      _Line(label: 'Dry', value: drySummary(care.dry)),
                      _Line(label: 'Iron', value: ironSummary(care.iron)),
                      _Line(label: 'Bleach', value: care.bleach.label),
                      // The diff above would announce "Dry cleaning: allowed →
                      // not allowed" and then this summary never mentioned it
                      // again, which is how a label whose only news was "do
                      // not dry clean" appeared to change nothing.
                      if (dryCleanSummary(care) case final String line)
                        _Line(
                          label: careFieldLabel('professional.doNotDryClean'),
                          value: line,
                        ),
                      // Warnings are the label's printed words rather than its
                      // symbols — "wash inside out", "with like colours". The
                      // server only started reporting them reliably once the
                      // prompt asked for them, so before that this row would
                      // always have been empty.
                      if (care.warnings.isNotEmpty)
                        _Line(
                          label: 'Take care',
                          value: care.warnings.map((w) => w.label).join(', '),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              _Composition(
                fromLabel: state.reading.composition,
                recorded: state.updated.composition,
              ),

              if (state.reading.countryOfOrigin?.value case final String made)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _Line(label: 'Made in', value: made),
                ),

              if (!state.reading.isComplete) ...[
                const SizedBox(height: 16),
                _PartialWarning(count: state.reading.unreadableSymbolCount),
              ],

              if (state.reading.symbolsFound.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Read ${state.reading.symbolsFound.length} symbols: '
                  '${state.reading.symbolsFound.join(', ')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
                    onPressed: controller.reset,
                    child: const Text('Rescan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: controller.save,
                    child: const Text('Use these instructions'),
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

/// Where the label contradicted what the app was recommending.
///
/// The single most useful thing this screen can show. "The label says this
/// wool jumper is machine washable, which is unusual" is information the user
/// could not have got any other way, and it is exactly what
/// [CareResolution.fieldsOverriddenByLabel] was built to report.
class _Changes extends StatelessWidget {
  const _Changes({
    required this.fields,
    required this.before,
    required this.after,
  });

  final Set<String> fields;
  final CareInstructions before;
  final CareInstructions after;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fields.length == 1
                ? 'The label changed one thing'
                : 'The label changed ${fields.length} things',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The manufacturer knows this garment better than a rule based on '
            'its fabric does, so their instruction wins.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${careFieldLabel(field)}: ',
                      style: TextStyle(color: scheme.onTertiaryContainer),
                    ),
                    TextSpan(
                      text: careFieldValue(before, field),
                      style: TextStyle(
                        color: scheme.onTertiaryContainer,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    TextSpan(
                      text: '  →  ${careFieldValue(after, field)}',
                      style: TextStyle(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _NoChanges extends StatelessWidget {
  const _NoChanges({required this.hasLabel});

  final bool hasLabel;

  @override
  Widget build(BuildContext context) => NoticePanel(
    padding: 16,
    // Still worth saving. The instructions are unchanged but the *evidence*
    // is much stronger, which is what stops the app asking to scan this label
    // again and what lets it act without checking.
    child: Text(
      'The label agrees with what the app had worked out. Saving it means '
      'these instructions are now the manufacturer\'s, not a guess.',
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

class _PartialWarning extends StatelessWidget {
  const _PartialWarning({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => NoteRow(
    icon: Icons.info_outline,
    iconSize: 18,
    bottomPadding: 0,
    color: Theme.of(context).colorScheme.tertiary,
    // Said plainly rather than hidden. An incomplete reading presented as
    // a complete one is how a garment gets washed on an instruction
    // nobody actually read.
    text: count == 1
        ? 'One symbol could not be read. The fabric rules still cover '
              'whatever it said.'
        : '$count symbols could not be read. The fabric rules still '
              'cover whatever they said.',
  );
}

/// What the garment is made of, after the label was read.
///
/// Shown because the fibre content is on most labels, is taken when it is
/// there, and outranks whatever was guessed from a photograph — and none of
/// that was visible on this screen. Somebody scanning a tag had no way to tell
/// whether the composition had been captured or never read at all.
///
/// The silent case earns its place as much as the other. Saying nothing would
/// look identical whether the label was silent about fabric or the reading
/// missed it, and those want different responses: one is the label's fault and
/// one is worth another photograph.
class _Composition extends StatelessWidget {
  const _Composition({required this.fromLabel, required this.recorded});

  /// What this label stated, if it stated anything.
  final Confident<FabricComposition>? fromLabel;

  /// What the garment will be recorded as. Usually the label's, but not
  /// always: [Confident.resolve] keeps an existing value that is already at
  /// least as well evidenced.
  final Confident<FabricComposition> recorded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The label's own words when it had any, because that is the question
    // being answered — did the fabric come through — rather than what the
    // garment happened to be recorded as beforehand.
    final shown = fromLabel ?? recorded;
    final known = !shown.value.isEmpty;

    // Rare, and worth saying out loud rather than showing a figure that
    // quietly is not the one about to be saved.
    final kept = fromLabel != null && recorded.value != fromLabel!.value;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'What it is made of',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (known)
                  ConfidenceChip(
                    confidence: shown.confidence,
                    source: shown.source,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              known ? shown.value.label : 'Not known yet',
              style: theme.textTheme.bodyMedium,
            ),
            // Named where the comparison actually happens. Somebody holding a
            // tag that reads ELASTANE and an app that says Spandex has no way
            // to tell whether it read the tag right — and reasonably assumes
            // it did not.
            if (_otherNames(shown.value) case final String others)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Your label may call it $others.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              switch ((fromLabel, known, kept)) {
                (null, true, _) =>
                  'This label did not state a fabric, so this is still what '
                      'was worked out earlier.',
                (null, false, _) =>
                  'This label did not state a fabric, and none has been '
                      'recorded. You can set it by editing the item.',
                (_, _, true) =>
                  'Read from this label. What is already recorded is at least '
                      'as well evidenced, so it has been kept: '
                      '\${recorded.value.label}.',
                _ =>
                  'Read from this label, which is why it outranks anything '
                      'worked out from the photo.',
              },
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The other names for whichever fibres this garment is made of.
///
/// Null when every fibre in it goes by one name, which is most garments — the
/// line is worth drawing only when there is a mismatch to explain.
String? _otherNames(FabricComposition composition) {
  final names = <String>[
    for (final fiber in composition.fibers)
      if (composition.isDescribedBy(fiber))
        for (final alias in fiber.alsoKnownAs) alias,
  ];
  if (names.isEmpty) return null;
  if (names.length == 1) return names.single;
  return '${names.sublist(0, names.length - 1).join(', ')} or ${names.last}';
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // Wide enough for "Dry cleaning" and "Take care". At 72 this fit
            // the four short labels it was written for and wrapped the two
            // added later onto a second line.
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Which fields came from the previous scan rather than this one.
///
/// Its own widget rather than another `_ReadNotice` because it needs an action
/// beside it. Keeping a field the earlier reading got wrong is the one way
/// merging can be worse than replacing, and re-scanning cannot fix it while
/// the symbol stays illegible — so the way out has to be here, next to the
/// thing that prompts the doubt, rather than buried in a menu.
class _KeptNotice extends StatelessWidget {
  const _KeptNotice({required this.fields, required this.onReplace});

  final Set<String> fields;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final named = [for (final field in fields) careFieldLabel(field)]..sort();

    return NoticePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.history,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  named.length == 1
                      ? 'This photo did not show ${named.first.toLowerCase()}, '
                            'so it is kept from the last scan of this label.'
                      : 'This photo did not show ${named.join(', ')}, so they '
                            'are kept from the last scan of this label.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onReplace,
              child: const Text('Use only what I just scanned'),
            ),
          ),
        ],
      ),
    );
  }
}
