/// The views a screen shows when it is not showing its content.
///
/// Asking for a photograph, having nothing yet, failing, finishing and waiting
/// were each written out longhand in every screen that needed them: thirty-odd
/// private widgets that were the same centred column with a different icon and
/// sentence, and that drifted apart — the same kind of failure was an
/// error-red icon in one place and a quiet grey one in another. They live here
/// so the next change to how the app says "nothing yet" is made once.
///
/// `StatusMessage` remains for the message that carries its own detail text
/// and raw error; these cover the rest.
library;

import 'package:flutter/material.dart';

import 'rinse_kit.dart';

/// The layout all of them share: a padded, centred column. It does not
/// scroll, so content taller than the screen (very large text) would overflow.
class _Centered extends StatelessWidget {
  const _Centered({required this.children, this.padded = true});

  final List<Widget> children;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final column = Column(mainAxisSize: MainAxisSize.min, children: children);
    return Center(
      child: padded
          ? Padding(padding: const EdgeInsets.all(32), child: column)
          : column,
    );
  }
}

TextStyle? _quiet(BuildContext context, TextStyle? base) =>
    base?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

/// Asks for a photograph: what to do, why, and the buttons that do it.
class IntroView extends StatelessWidget {
  const IntroView({
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
    this.note,
    this.actionsGap = 32,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  /// A smaller line under [message], for the aside that is not the point.
  final String? note;

  /// Laid out as given: the primary button and whatever alternatives the
  /// screen offers beside it.
  final List<Widget> actions;

  final double actionsGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _Centered(
      children: [
        IconBadge(icon, size: 112),
        const SizedBox(height: 24),
        Text(
          title,
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: _quiet(context, theme.textTheme.bodyMedium),
        ),
        if (note case final String note) ...[
          const SizedBox(height: 8),
          Text(
            note,
            textAlign: TextAlign.center,
            style: _quiet(context, theme.textTheme.bodySmall),
          ),
        ],
        SizedBox(height: actionsGap),
        ...actions,
      ],
    );
  }
}

/// There is nothing here yet, and what would change that.
class EmptyView extends StatelessWidget {
  const EmptyView({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _Centered(
      children: [
        IconBadge(icon),
        const SizedBox(height: 16),
        Text(
          title,
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: _quiet(context, theme.textTheme.bodyMedium),
        ),
        if (action case final Widget action) ...[
          const SizedBox(height: 24),
          action,
        ],
      ],
    );
  }
}

/// Something went wrong, in a sentence, with one way forward.
class FailureView extends StatelessWidget {
  const FailureView({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _Centered(
      children: [
        const IconBadge(Icons.error_outline, size: 80, error: true),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

/// Finished, with what to do next.
class SuccessView extends StatelessWidget {
  const SuccessView({
    required this.title,
    required this.actions,
    this.headingTitle = true,
    super.key,
  });

  final String title;
  final List<Widget> actions;

  /// False leaves [title] in the surrounding text style, for a one-word
  /// confirmation that should not read as a heading.
  final bool headingTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _Centered(
      children: [
        const IconBadge(Icons.check_circle_outline, size: 96),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: headingTitle ? TextAlign.center : null,
          style: headingTitle ? theme.textTheme.titleLarge : null,
        ),
        const SizedBox(height: 24),
        ...actions,
      ],
    );
  }
}

/// Working on it.
///
/// With a [detail] it reads as a screen of its own — a heading and a promise
/// about how long — and is padded like one; without, it is a spinner and a
/// line.
class LoadingView extends StatelessWidget {
  const LoadingView({
    required this.title,
    this.detail,
    this.heading = false,
    this.gap = 16,
    super.key,
  });

  final String title;
  final String? detail;

  /// Whether [title] is set as a heading rather than body text.
  final bool heading;

  /// Between the spinner and the title.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _Centered(
      padded: detail != null,
      children: [
        const CircularProgressIndicator(),
        SizedBox(height: gap),
        Text(title, style: heading ? theme.textTheme.titleLarge : null),
        if (detail case final String detail) ...[
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: _quiet(context, theme.textTheme.bodySmall),
          ),
        ],
      ],
    );
  }
}
