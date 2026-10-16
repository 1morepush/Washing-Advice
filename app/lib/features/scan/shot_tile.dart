/// One photograph in a set that is about to be read, with its role and crop.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/theme.dart';
import 'scan_controller.dart' show ScanShot;
import 'scan_parts.dart';

/// A thumbnail that can be cropped by tapping it, under a menu saying what
/// the photograph shows.
///
/// [compact] is the smaller tile the bulk screen fits many of in a row; the
/// single-garment screen has room for the larger.
class ShotTile extends StatelessWidget {
  const ShotTile({
    required this.shot,
    required this.onRole,
    required this.onCrop,
    this.compact = false,
    super.key,
  });

  final ScanShot shot;
  final ValueChanged<PhotoRole> onRole;
  final VoidCallback onCrop;
  final bool compact;

  /// The parts worth offering. `condition` and `worn` are left out: filing a
  /// stain photo is a different question with its own screen. The care label
  /// is included, and is read in the same pass by the label reader.
  static const _offered = [
    PhotoRole.front,
    PhotoRole.back,
    PhotoRole.careTag,
    PhotoRole.detail,
    PhotoRole.logo,
    PhotoRole.brandTag,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extent = compact ? 96.0 : 108.0;

    return SizedBox(
      width: extent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tapping the picture crops it, with the badge saying so — an
          // affordance that has to be visible, because nobody taps a
          // thumbnail to find out what happens.
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onCrop,
              borderRadius: context.rinse.tileBorderRadius,
              child: Stack(
                children: [
                  ScanThumb(image: shot.image, size: extent),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: const PhotoBadge(icon: Icons.crop),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          PopupMenuButton<PhotoRole>(
            onSelected: onRole,
            tooltip: 'What this photo shows',
            itemBuilder: (_) => [
              for (final role in _offered)
                PopupMenuItem(value: role, child: Text(role.label)),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    shot.role.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: compact ? 18 : 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
