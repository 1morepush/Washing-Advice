/// Scanning a care label.
///
/// The review step here answers a different question from the garment scan's.
/// There the question was "is this reading right?"; here it is "**what did the
/// label change?**" — because the user already has care instructions, and the
/// only thing worth their attention is where the manufacturer disagreed with
/// what the app had been telling them.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../widgets/confidence_chip.dart';
import '../wardrobe/care_text.dart';
import 'care_tag_controller.dart';

class CareTagScreen extends ConsumerWidget {
  const CareTagScreen({required this.id, super.key});

  final ItemId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(careTagControllerProvider(id));
    final controller = ref.read(careTagControllerProvider(id).notifier);

    void back() {
      controller.reset();
      context.go('/item/${id.value}');
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: back),
        title: const Text('Scan the care label'),
      ),
      body: switch (state) {
        CareTagIdle() => _Capture(controller: controller),
        CareTagCollecting(:final images) => _Collected(
          images: images,
          controller: controller,
        ),
        CareTagReading() => const _Reading(),
        CareTagReviewing() => _Review(state: state, controller: controller),
        CareTagSaved() => _Saved(onDone: back),
        CareTagFailed(:final message, :final isRetryable) => _Failed(
          message: message,
          isRetryable: isRetryable,
          controller: controller,
        ),
      },
    );
  }
}

class _Capture extends StatelessWidget {
  const _Capture({required this.controller});

  final CareTagController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Photograph the care label',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Flatten it out and fill the frame with the symbols. This is the '
              "manufacturer's own instruction, so it will override anything "
              'the app worked out from the fabric.\n\n'
              'Printed on both sides? You can add the other side before it is '
              'read. Any language is fine — the symbols are the same '
              'everywhere.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: controller.capture,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Take a photo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          'Reading the label…',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}

class _Review extends StatelessWidget {
  const _Review({required this.state, required this.controller});

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
                _ReadNotice(
                  icon: Icons.translate,
                  text:
                      'This label is in $language. The symbols are the same in '
                      'every country, so the instructions below come from '
                      'those; the wording is shown as printed.',
                ),
                const SizedBox(height: 8),
              ],

              if (state.images.length > 1) ...[
                _ReadNotice(
                  icon: Icons.photo_library_outlined,
                  text:
                      'Read from ${state.images.length} photos together, as '
                      'one label.',
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      // Still worth saving. The instructions are unchanged but the *evidence*
      // is much stronger, which is what stops the app asking to scan this label
      // again and what lets it act without checking.
      child: Text(
        'The label agrees with what the app had worked out. Saving it means '
        'these instructions are now the manufacturer\'s, not a guess.',
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

class _PartialWarning extends StatelessWidget {
  const _PartialWarning({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: scheme.tertiary),
        const SizedBox(width: 8),
        Expanded(
          // Said plainly rather than hidden. An incomplete reading presented as
          // a complete one is how a garment gets washed on an instruction
          // nobody actually read.
          child: Text(
            count == 1
                ? 'One symbol could not be read. The fabric rules still cover '
                      'whatever it said.'
                : '$count symbols could not be read. The fabric rules still '
                      'cover whatever they said.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.tertiary),
          ),
        ),
      ],
    );
  }
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

class _Saved extends StatelessWidget {
  const _Saved({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Care instructions updated',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    ),
  );
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.message,
    required this.isRetryable,
    required this.controller,
  });

  final String message;
  final bool isRetryable;
  final CareTagController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: controller.reset,
              child: Text(isRetryable ? 'Try again' : 'Back'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The photographs taken so far, with the choice of adding another or reading.
///
/// This screen exists because reading the first shot immediately is wrong for
/// the commonest awkward label: one printed on both sides, or continued onto a
/// second tag sewn behind the first. Reading half of one produces an answer
/// that looks complete, and there is nothing on it to suggest otherwise.
class _Collected extends StatelessWidget {
  const _Collected({required this.images, required this.controller});

  final List<ScanImage> images;
  final CareTagController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                images.length == 1
                    ? 'One photo of the label'
                    : '${images.length} photos of the label',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'They are read together as one label, so put each side or tag '
                'in its own photo. Nothing has been read yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (index, image) in images.indexed)
                    _Shot(index: index + 1, image: image),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: controller.capture,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('Add another side'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // For the shot that came out blurred, which is most of
                    // them. Retaking without this would mean starting over.
                    IconButton(
                      onPressed: controller.discardLast,
                      icon: const Icon(Icons.undo),
                      tooltip: 'Remove the last photo',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: controller.readCollected,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: Text(
                      images.length == 1
                          ? 'Read this label'
                          : 'Read these ${images.length} together',
                    ),
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

/// One collected photograph, numbered in the order it was taken.
class _Shot extends StatelessWidget {
  const _Shot({required this.index, required this.image});

  final int index;
  final ScanImage image;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            Uint8List.fromList(image.bytes),
            width: 108,
            height: 108,
            fit: BoxFit.cover,
            // A thumbnail that will not decode must not take the screen with
            // it — the photograph is still perfectly good to the server.
            errorBuilder: (_, _, _) => Container(
              width: 108,
              height: 108,
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.image_not_supported_outlined),
            ),
          ),
        ),
        Positioned(
          top: 4,
          left: 4,
          child: CircleAvatar(
            radius: 11,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              '$index',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Something worth saying about how the reading was obtained.
class _ReadNotice extends StatelessWidget {
  const _ReadNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
