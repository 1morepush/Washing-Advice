/// Short messages set inside a screen's content.
///
/// Two shapes. A [NoteRow] is a line with a small icon, coloured to say how
/// much it matters; a [Notice] is the same in a tinted panel, for something the
/// reader should not scroll past.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// An icon and a sentence on one line, both in [color].
class NoteRow extends StatelessWidget {
  const NoteRow({
    required this.icon,
    required this.text,
    required this.color,
    this.iconSize = 16,
    this.gap = 8,
    this.bottomPadding = 8,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color color;
  final double iconSize;

  /// Between the icon and the text.
  final double gap;

  final double bottomPadding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottomPadding),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: iconSize, color: color),
        SizedBox(width: gap),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

/// The tinted panel behind a [Notice], for a notice that needs more than an
/// icon and a sentence — an action beside it, or none of the icon.
class NoticePanel extends StatelessWidget {
  const NoticePanel({
    required this.child,
    this.padding = 12,
    this.warning = false,
    super.key,
  });

  final Widget child;
  final double padding;

  /// Warm amber (the theme's tertiary container) rather than the neutral
  /// tile, for a guess the reader should look at.
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: warning
          ? Theme.of(context).colorScheme.tertiaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: context.rinse.tileBorderRadius,
    ),
    child: child,
  );
}

/// An icon and a sentence in a tinted panel.
class Notice extends StatelessWidget {
  const Notice({
    required this.icon,
    required this.text,
    this.warning = false,
    super.key,
  });

  final IconData icon;
  final String text;

  /// See [NoticePanel.warning].
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final ink = warning
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return NoticePanel(
      warning: warning,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}
