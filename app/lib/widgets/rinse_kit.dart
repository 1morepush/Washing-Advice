/// The small shared pieces of the Rinse look, so screens compose them instead
/// of re-deriving radii, edges and tints.
///
/// Everything here reads `RinseShape`, `LaundryStageColors` and the
/// `ColorScheme`; none of it has a colour of its own.
///
///  * [RinseCard] — a card with padding and an optional tap.
///  * [GroupCard] — a card of rows under an optional label, hairlines between.
///  * [SectionLabel] — the small heading above a group or a list.
///  * [GarmentWell] — the soft tinted square a garment sits on.
///  * [CountBadge] — the little "×3" pill on a tile.
///  * [StagePill] — one of the Basket / Washing / Drying selectors.
///  * [InsetPanel] — a quiet well inside a card, for a summary or a warning.
///  * [AppBarTitle] — an app bar title that shrinks to fit rather than ellipsise.
///  * [IconBadge] — an icon on a soft round tint, for empty and status views.
///  * [RinseNavBar] — the bottom bar with its top hairline.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A card: [RinseShape.cardRadius] corners, a soft shadow in Light, a fill in
/// Dark and a hairline in AMOLED — all of it from the theme's `Card`.
///
/// With [onTap] the whole card is a button and ripples inside its corners.
class RinseCard extends StatelessWidget {
  const RinseCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Overrides the card fill, for a selected or highlighted card.
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// The heading of a named group of settings — 16 / 800 — shared by the
/// Settings groups and the notes that sit among them, so every group on that
/// screen is titled the same way.
TextStyle? groupHeadingStyle(BuildContext context) => Theme.of(
  context,
).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800);

/// The small heading above a group of rows or a list: 13 / 800, muted.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 6),
    super.key,
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// A card of rows, with a [RinseShape.lineSoft] hairline between them and an
/// optional [title] inside the top. For Settings groups and the like.
class GroupCard extends StatelessWidget {
  const GroupCard({required this.children, this.title, super.key});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final soft = context.rinse.lineSoft;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final String title)
            SectionLabel(
              title,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 || title != null) Divider(height: 1, color: soft),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// The soft square a garment sits on: [RinseShape.well] at
/// [RinseShape.tileRadius]. With [selected] an accent ring is drawn inside the
/// edge, so a picked garment is plain at a glance without a badge.
class GarmentWell extends StatelessWidget {
  const GarmentWell({
    required this.child,
    this.size,
    this.selected = false,
    this.color,
    super.key,
  });

  final Widget child;

  /// A fixed square, or null to fill what the parent gives.
  final double? size;
  final bool selected;

  /// Replaces the well colour (a thumbnail's backdrop is one).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final rinse = context.rinse;
    final radius = rinse.tileBorderRadius;
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2.5,
                )
              : null,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? rinse.well,
            borderRadius: radius,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A small pill laid on a tile, "×3": the page's ink with the ground's colour
/// on it.
class CountBadge extends StatelessWidget {
  const CountBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.onSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.surface,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// One of the three stage selectors (Basket, Washing, Drying): a pill with a
/// coloured dot when idle, filled with the stage colour when [selected].
///
/// [color] and [onColor] come from [LaundryStageColors].
class StagePill extends StatelessWidget {
  const StagePill({
    required this.label,
    required this.color,
    required this.onColor,
    required this.selected,
    this.count,
    this.onTap,
    this.compact = false,
    super.key,
  });

  final String label;

  /// Tighter padding, and a label that scales down rather than ellipsising,
  /// for three pills sharing a narrow phone's width.
  final bool compact;

  /// The number in the stage, shown after the label, or null for none.
  final int? count;
  final Color color;
  final Color onColor;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? onColor : scheme.onSurface;
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w800);

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? color : scheme.surfaceContainerHighest,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 10,
                vertical: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? onColor : color,
                    ),
                  ),
                  SizedBox(width: compact ? 4 : 6),
                  Flexible(
                    child: compact
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              count == null ? label : '$label $count',
                              maxLines: 1,
                              style: style,
                            ),
                          )
                        : Text(
                            count == null ? label : '$label $count',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bottom bar wearing the design's top hairline. `NavigationBar` has no
/// border of its own, so the line is drawn here.
class RinseNavBar extends StatelessWidget {
  const RinseNavBar({required this.bar, super.key});

  /// The `NavigationBar` to put the line on.
  final Widget bar;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: bar,
  );
}

/// An icon on a soft round tint: the accent by default, the error colours when
/// [error]. Heads the empty, intro, success and failure views.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {this.size = 88, this.error = false, super.key});

  final IconData icon;

  /// The diameter of the tint; the icon is 45% of it.
  final double size;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: error ? scheme.errorContainer : scheme.primaryContainer,
      ),
      child: Icon(
        icon,
        size: size * 0.45,
        color: error ? scheme.onErrorContainer : scheme.onPrimaryContainer,
      ),
    );
  }
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

/// An app bar title that scales down to fit a narrow phone instead of ending
/// in an ellipsis. Short titles are untouched; only a long one ("Add several
/// garments" at 320 px) is shrunk, and only as far as it must be.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerStart,
    child: Text(text, maxLines: 1),
  );
}
