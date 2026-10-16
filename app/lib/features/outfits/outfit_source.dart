/// Where an outfit idea came from, said on the idea itself.
///
/// The Ideas tab shows two kinds of outfit under one occasion, and they are
/// different in kind. One is arithmetic the app can defend line by line:
/// colour distance, wear counts, what has been worn together. The other is a
/// model's taste, checked only to the extent that the garments exist and can be
/// worn today. Putting them on one screen is only honest if it is never
/// possible to mistake one for the other, so every card carries a label naming
/// its source, the two are sectioned, and the model's cards are tinted and the
/// arithmetic's are not. Nothing about *how* either is produced lives here.
library;

import 'package:flutter/material.dart';

enum OutfitSource {
  wardrobe(
    label: 'From your wardrobe',
    icon: Icons.checkroom_outlined,
    heading: 'Suggested from what you own',
    caption:
        'Built from your clothes: colours, how often each is worn and which '
        'pieces you already pair. Every line is a reason the app can check.',
  ),
  stylist(
    label: 'Stylist idea',
    icon: Icons.auto_awesome_outlined,
    heading: 'Ideas from the stylist',
    caption:
        'A model’s opinion, not arithmetic. Each idea is checked against '
        'what you own, but whether it looks good is taste.',
  );

  const OutfitSource({
    required this.label,
    required this.icon,
    required this.heading,
    required this.caption,
  });

  /// What the card says, in a few words.
  final String label;
  final IconData icon;

  /// The section's title and what to make of it.
  final String heading;
  final String caption;

  /// The colour that stands for this source.
  Color accent(ColorScheme scheme) => switch (this) {
    wardrobe => scheme.primary,
    stylist => scheme.tertiary,
  };

  /// The fill of the label, and the tint of the card behind it.
  Color container(ColorScheme scheme) => switch (this) {
    wardrobe => scheme.primaryContainer,
    stylist => scheme.tertiaryContainer,
  };

  Color onContainer(ColorScheme scheme) => switch (this) {
    wardrobe => scheme.onPrimaryContainer,
    stylist => scheme.onTertiaryContainer,
  };
}

/// The small tag at the top of every outfit card.
class SourceLabel extends StatelessWidget {
  const SourceLabel(this.source, {super.key});

  final OutfitSource source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: source.container(scheme),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(source.icon, size: 14, color: source.onContainer(scheme)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  source.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: source.onContainer(scheme),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card an outfit sits in, tinted by where it came from.
///
/// The wardrobe's cards are the app's ordinary card. The stylist's are washed
/// with its accent, so that scrolling past a screenful of them still tells you
/// whose taste you are reading without reading the label.
class OutfitCard extends StatelessWidget {
  const OutfitCard({required this.source, required this.child, super.key});

  final OutfitSource source;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: source == OutfitSource.stylist
          ? Color.alphaBlend(
              source.container(scheme).withValues(alpha: 0.35),
              scheme.surface,
            )
          : null,
      shape: source == OutfitSource.stylist
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: source.accent(scheme)),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [SourceLabel(source), const SizedBox(height: 12), child],
        ),
      ),
    );
  }
}

/// The heading that opens one source's section of the Ideas list.
class SourceHeader extends StatelessWidget {
  const SourceHeader(this.source, {super.key});

  final OutfitSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                source.icon,
                size: 20,
                color: source.accent(theme.colorScheme),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(source.heading, style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            source.caption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A message inside a section: loading, empty or failed.
///
/// Inline rather than the full-screen status views, which centre themselves in
/// the space they are given and have none to be given inside a list.
class SectionNote extends StatelessWidget {
  const SectionNote({
    required this.icon,
    required this.title,
    this.detail,
    this.technical,
    this.action,
    this.busy = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? detail;

  /// The raw error, small and last.
  final String? technical;
  final Widget? action;

  /// Shows a spinner in place of the icon.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, color: quiet),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    if (detail case final String detail) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: quiet,
                        ),
                      ),
                    ],
                    if (action case final Widget action) ...[
                      const SizedBox(height: 8),
                      action,
                    ],
                    if (technical case final String technical) ...[
                      const SizedBox(height: 8),
                      Text(
                        technical,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: quiet.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
