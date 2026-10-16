/// The few pieces every scan screen shares, so the capture, collect and review
/// steps read as one family: a photograph on a soft well, a heading with its
/// explanation under it, and the bar the buttons sit in.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/theme.dart';
import '../../widgets/care_symbol.dart';

/// A photograph the user took, clipped to the tile corner and set on the soft
/// well, so one that will not decode still reads as a tile rather than a hole.
///
/// Small thumbnails (a failed pile photo, a care label) take a tighter corner
/// so the radius stays in proportion to the picture.
class ScanThumb extends StatelessWidget {
  const ScanThumb({required this.image, required this.size, super.key});

  final ScanImage image;
  final double size;

  @override
  Widget build(BuildContext context) {
    final rinse = context.rinse;
    final scheme = Theme.of(context).colorScheme;
    final radius = size < 64
        ? BorderRadius.circular(rinse.tileRadius * 0.6)
        : rinse.tileBorderRadius;

    // On the well, so a photograph with transparent edges (a cutout) still
    // reads as a tile instead of a shape floating on the page.
    return ClipRRect(
      borderRadius: radius,
      child: ColoredBox(
        color: rinse.well,
        child: Image.memory(
          Uint8List.fromList(image.bytes),
          width: size,
          height: size,
          fit: BoxFit.cover,
          // A thumbnail that will not decode must not take the screen with it —
          // the photograph is still perfectly good to the server.
          errorBuilder: (_, _, _) => Container(
            width: size,
            height: size,
            color: rinse.well,
            child: Icon(
              Icons.image_not_supported_outlined,
              size: size / 3,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small label laid over a photograph — the crop badge, the "Label" tag, the
/// number on a collected shot. A scrim in the page's dark so it is legible on
/// a pale photograph and a dark one alike, in all three appearances.
class PhotoBadge extends StatelessWidget {
  const PhotoBadge({this.icon, this.text, this.color, super.key})
    : assert(icon != null || text != null);

  final IconData? icon;
  final String? text;

  /// The fill; the scrim by default.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onScrim = Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.scrim.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final IconData icon)
              Icon(icon, size: 14, color: onScrim),
            if (icon != null && text != null) const SizedBox(width: 4),
            if (text case final String text)
              // Laid over a photograph of a fixed size, so it does not grow
              // past the picture it labels at large text.
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: Text(
                  text,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: onScrim,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A screen's heading and the sentence under it: 20 / 800, then the
/// explanation in the quiet colour at body size rather than fine print.
class ScanHeading extends StatelessWidget {
  const ScanHeading(this.title, {this.body, super.key});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        if (body case final String body) ...[
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The strip of buttons under a scrolling step, clear of the home indicator.
class ScanActionBar extends StatelessWidget {
  const ScanActionBar({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

/// The care symbols for [care], each on its own soft tile. Nothing at all when
/// there is no symbol for any of it, rather than an empty strip.
class CareSymbolRow extends StatelessWidget {
  const CareSymbolRow({required this.care, super.key});

  final CareInstructions care;

  @override
  Widget build(BuildContext context) {
    final kinds = careSymbolsFor(care);
    if (kinds.isEmpty) return const SizedBox.shrink();

    final rinse = context.rinse;
    final ink = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final kind in kinds)
            DecoratedBox(
              decoration: BoxDecoration(
                color: rinse.well,
                borderRadius: BorderRadius.circular(rinse.tileRadius * 0.75),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: CareSymbol(kind: kind, color: ink, size: 28),
              ),
            ),
        ],
      ),
    );
  }
}
