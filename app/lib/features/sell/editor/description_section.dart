/// The description, as it will be pasted into Depop.
///
/// Not a box to type in. The text is composed by the core from the fields
/// further down, the same way every time, so what is edited here is facts — a
/// brand, a size, a flaw — and what is pasted is those facts laid out as Depop
/// buyers read them. A description written fresh for each listing leaves things
/// out, and this one cannot forget the size: the size line is simply not there
/// when the field is empty, and the field is one scroll below.
///
/// It is shown exactly as it will be copied, character for character, with
/// Depop's own two counters under it. The core keeps a description inside both
/// limits, so the counters mostly confirm; they go to the error colour and say
/// by how much when something is over, which a hashtag typed into the notes can
/// still make happen.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../widgets/rinse_kit.dart';
import 'editor_text.dart';
import 'fields.dart';

class DescriptionSection extends StatelessWidget {
  const DescriptionSection({required this.listing, super.key});

  final Listing listing;

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text("Copied — paste it into Depop's description"),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = composeDescription(listing);
    final check = checkDescription(text);

    return EditorSection(
      title: 'Description',
      intro:
          'This is what you paste into Depop, exactly as it will read. It '
          'is built from the details below, so change them there.',
      children: [
        InsetPanel(
          child: text.isEmpty
              ? const QuietText(
                  'Nothing to paste yet. Add a title and the description '
                  'builds itself here.',
                )
              : SelectableText(text, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _Counter(
              text:
                  '${groupedCount(check.length)} / '
                  '${groupedCount(depopDescriptionLimit)} characters',
              over: check.overLimit ? check.length - depopDescriptionLimit : 0,
            ),
            _Counter(
              text: '${check.hashtagCount} / $depopHashtagLimit hashtags',
              over: check.tooManyHashtags
                  ? check.hashtagCount - depopHashtagLimit
                  : 0,
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: text.isEmpty ? null : () => _copy(context, text),
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy description'),
        ),
      ],
    );
  }
}

/// One of Depop's counters: "312 / 1,000 characters".
///
/// In the error colour and with how far over it is when [over] is more than
/// zero. Said in words as well as colour, because a colour alone is nothing to
/// somebody who cannot tell it from the rest.
class _Counter extends StatelessWidget {
  const _Counter({required this.text, required this.over});

  final String text;
  final int over;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOver = over > 0;

    return Text(
      isOver ? '$text — ${groupedCount(over)} over' : text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: isOver
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant,
        fontWeight: isOver ? FontWeight.w800 : FontWeight.w700,
      ),
    );
  }
}
