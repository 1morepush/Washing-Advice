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
                Flexible(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (value case final String value) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
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

/// A quiet panel inside a card: for a summary, a form or a warning that is a
/// step apart from the rows around it.
///
/// A soft well in Light and Dark; in AMOLED the same well with the hairline
/// edge, because a fill that close to black does not hold a shape alone.
class InsetPanel extends StatelessWidget {
  const InsetPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.tint,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Replaces the well fill, for a problem.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final rinse = context.rinse;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: tint ?? rinse.well,
        borderRadius: rinse.tileBorderRadius,
        border: rinse.cardEdge == BorderSide.none
            ? null
            : Border.fromBorderSide(rinse.cardEdge),
      ),
      child: child,
    );
  }
}
