/// One photograph in a set that is about to be read, with its role and crop.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'scan_controller.dart' show ScanShot;

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
          InkWell(
            onTap: onCrop,
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    Uint8List.fromList(shot.image.bytes),
                    width: extent,
                    height: extent,
                    fit: BoxFit.cover,
                    // A thumbnail that will not decode must not take the
                    // screen with it — the photograph is still perfectly good
                    // to the server.
                    errorBuilder: (_, _, _) => Container(
                      width: extent,
                      height: extent,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.crop, size: compact ? 14 : 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
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
                if (compact)
                  Flexible(
                    child: Text(
                      shot.role.label,
                      style: theme.textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Text(shot.role.label, style: theme.textTheme.labelMedium),
                Icon(
                  Icons.arrow_drop_down,
                  size: compact ? 16 : 18,
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
