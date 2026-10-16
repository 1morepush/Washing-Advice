/// The pieces Settings is assembled from: a group, and the way a long
/// explanation sits behind a tap instead of in the middle of the list.
///
/// Settings used to be a column of headings each followed by a paragraph. The
/// paragraphs are worth having and are not worth reading every time, and with
/// them in line a switch was a screen's scroll away from the next one. Now a row
/// says what it is and what it is set to, and an info button beside the title
/// opens the explanation in a sheet. Nothing was cut: every sentence that was on
/// the page is behind one of these.
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/rinse_kit.dart';

/// Opens [text] in a sheet titled [title].
Future<void> showSettingInfo(
  BuildContext context, {
  required String title,
  required String text,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    ),
  ),
);

/// A small "what is this?" button that opens [text] in a sheet.
class InfoButton extends StatelessWidget {
  const InfoButton({required this.title, required this.text, super.key});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.info_outline, size: 20),
    tooltip: 'About $title',
    // The glyph stays small; the target does not. A compact button is about
    // 40 dp, under the 48 a thumb can be asked to hit.
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    onPressed: () => showSettingInfo(context, title: title, text: text),
  );
}

/// A row's title with its info button after it.
///
/// The title takes the room it needs and wraps, so a large text size pushes the
/// button to the end of a second line rather than off the screen.
class TitleWithInfo extends StatelessWidget {
  const TitleWithInfo(
    this.title, {
    required this.info,
    this.infoTitle,
    this.style,
    super.key,
  });

  final String title;

  /// The explanation behind the button.
  final String info;

  /// What the sheet is called, where the row's own title would not do.
  final String? infoTitle;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: Text(
          title,
          style:
              style ??
              Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      InfoButton(title: infoTitle ?? title, text: info),
    ],
  );
}

/// A named group of settings: a heading, then one card holding its rows.
///
/// [value] is what the group as a whole is set to, for the ones that are one
/// choice (Appearance), set bold on the right of the heading; groups of
/// several rows show each row's own value instead. Children are separated by
/// the card's soft row line where they are separate rows, and sit inside the
/// card's padding.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    required this.title,
    required this.children,
    this.value,
    this.info,
    super.key,
  });

  final String title;
  final String? value;

  /// An explanation of the whole group, behind a button beside its name.
  final String? info;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tall enough for the info button, so the heading never grows when
          // one is present.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                const SizedBox(width: 4),
                // With a value the title claims the room, which pushes the
                // value to the right edge; a long title still wraps rather
                // than squeezing the value out.
                Flexible(
                  flex: 3,
                  fit: value == null ? FlexFit.loose : FlexFit.tight,
                  child: Text(title, style: groupHeadingStyle(context)),
                ),
                if (value case final String value) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    flex: 2,
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: context.rinse.textAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                if (info case final String info)
                  InfoButton(title: title, text: info)
                else
                  const SizedBox(width: 4),
              ],
            ),
          ),
          RinseCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A line between two rows inside a [SettingsGroup]'s card.
class RowDivider extends StatelessWidget {
  const RowDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Divider(height: 1, color: context.rinse.lineSoft),
  );
}
