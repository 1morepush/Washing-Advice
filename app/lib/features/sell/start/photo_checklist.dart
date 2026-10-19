/// The shots a listing is photographed from, one row each.
///
/// The checklist is the briefing's: the cover, the back, the brand tag and the
/// size label, and under them any flaws and whatever else helps. Each row says
/// why a buyer wants the shot, in the core's words — a seller who knows a size
/// label answers the most common message is a seller who takes the photograph —
/// and has a button, not a gesture, to take it. Rows are stacked rather than set
/// in a line with their button beside them, because the text and the button
/// would otherwise share a small phone's width, and at a large text size the
/// words lose.
///
/// Holds no state. What has been taken is the screen's, and this draws it.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../widgets/notice.dart';
import '../../../widgets/rinse_kit.dart';
import '../../scan/scan_parts.dart' show PhotoBadge, ScanHeading, ScanThumb;
import 'photo_set.dart';

class PhotoChecklist extends StatelessWidget {
  const PhotoChecklist({
    required this.photos,
    required this.busy,
    required this.onTake,
    required this.onRemove,
    required this.onAddMore,
    super.key,
  });

  final ListingPhotoSet photos;

  /// Whether the camera is open, so a second request for it would be refused.
  final bool busy;

  /// Takes a photograph for [ListingShot].
  final ValueChanged<ListingShot> onTake;

  /// Takes the [index]th photograph of a shot back.
  final void Function(ListingShot shot, int index) onRemove;

  /// Picks more from the photo library.
  final VoidCallback onAddMore;

  /// The shots every listing is asked for, in the order the core declares them.
  static final _asked = [
    for (final shot in ListingShot.values)
      if (shot.isChecklist) shot,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ScanHeading(
          'Photograph it',
          body:
              'Start with the cover. The rest are what buyers look for before '
              'they message you. Nothing is sent until you tap Write the '
              'listing.',
        ),
        const SizedBox(height: 12),
        Text(
          '${photos.count} of $depopPhotoLimit photos',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (photos.isFull) ...[
          const SizedBox(height: 8),
          const Notice(
            icon: Icons.photo_library_outlined,
            text:
                'That is the $depopPhotoLimit photos Depop takes. Remove one '
                'to add another.',
          ),
        ],
        const SizedBox(height: 12),
        GroupCard(
          children: [
            for (final shot in _asked)
              _ShotRow(
                key: ValueKey('shot-${shot.name}'),
                shot: shot,
                image: photos.imageFor(shot),
                // The cover is the one to start with, so until it is taken it
                // is the one button that is not quiet.
                emphasised: shot == ListingShot.cover && !photos.hasCover,
                canAdd: !busy && !photos.isFull,
                busy: busy,
                onTake: () => onTake(shot),
                onRemove: () => onRemove(shot, 0),
              ),
            _PileRow(
              key: const ValueKey('shot-flaw'),
              title: 'Flaws (optional)',
              why: ListingShot.flaw.why,
              action: 'Add a flaw photo',
              actionIcon: Icons.photo_camera_outlined,
              removeLabel: 'Remove flaw photo',
              images: photos.imagesFor(ListingShot.flaw),
              enabled: !busy && !photos.isFull,
              onAdd: () => onTake(ListingShot.flaw),
              onRemove: (index) => onRemove(ListingShot.flaw, index),
            ),
            _PileRow(
              key: const ValueKey('shot-other'),
              title: 'More photos',
              why: ListingShot.other.why,
              action: 'Add more photos',
              actionIcon: Icons.photo_library_outlined,
              removeLabel: 'Remove photo',
              images: photos.imagesFor(ListingShot.other),
              enabled: !busy && !photos.isFull,
              onAdd: onAddMore,
              onRemove: (index) => onRemove(ListingShot.other, index),
            ),
          ],
        ),
      ],
    );
  }
}

/// A shot with one place: the picture, why it matters, and Take or Retake.
class _ShotRow extends StatelessWidget {
  const _ShotRow({
    required this.shot,
    required this.image,
    required this.emphasised,
    required this.canAdd,
    required this.busy,
    required this.onTake,
    required this.onRemove,
    super.key,
  });

  final ListingShot shot;
  final ScanImage? image;
  final bool emphasised;

  /// Whether a photograph could be added here: there is room and the camera is
  /// free. Retaking needs no room, only the camera.
  final bool canAdd;
  final bool busy;
  final VoidCallback onTake;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final taken = image != null;
    final onPressed = (taken ? !busy : canAdd) ? onTake : null;
    final label = Text(taken ? 'Retake' : 'Take');
    const icon = Icon(Icons.photo_camera_outlined);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(
            leading: _Slot(shot: shot, image: image),
            title: shot.label,
            why: shot.why,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: emphasised
                    ? FilledButton.icon(
                        onPressed: onPressed,
                        icon: icon,
                        label: label,
                      )
                    : FilledButton.tonalIcon(
                        onPressed: onPressed,
                        icon: icon,
                        label: label,
                      ),
              ),
              if (taken) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove the ${shot.label.toLowerCase()} photo',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A kind of photograph there can be several of: its words, the ones taken, and
/// a button for another.
class _PileRow extends StatelessWidget {
  const _PileRow({
    required this.title,
    required this.why,
    required this.action,
    required this.actionIcon,
    required this.removeLabel,
    required this.images,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    super.key,
  });

  final String title;
  final String why;
  final String action;
  final IconData actionIcon;
  final String removeLabel;
  final List<ScanImage> images;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(title: title, why: why),
        if (images.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (index, image) in images.indexed)
                _RemovableThumb(
                  image: image,
                  tooltip: images.length == 1
                      ? removeLabel
                      : '$removeLabel ${index + 1}',
                  onRemove: () => onRemove(index),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: enabled ? onAdd : null,
          icon: Icon(actionIcon),
          label: Text(action),
        ),
      ],
    ),
  );
}

/// A title and the reason for it, with the picture before them when there is
/// room for one.
class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.why, this.leading});

  final Widget? leading;
  final String title;
  final String why;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading case final Widget leading) ...[
          leading,
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                why,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The photograph taken for a shot, or a well waiting for one.
class _Slot extends StatelessWidget {
  const _Slot({required this.shot, required this.image});

  final ListingShot shot;
  final ScanImage? image;

  static const _size = 64.0;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    if (image == null) {
      return GarmentWell(
        size: _size,
        child: Icon(
          Icons.photo_camera_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Semantics(
      image: true,
      label: '${shot.label} photo',
      child: ScanThumb(image: image, size: _size),
    );
  }
}

/// A photograph in a pile, with a way to take it back laid over its corner.
class _RemovableThumb extends StatelessWidget {
  const _RemovableThumb({
    required this.image,
    required this.tooltip,
    required this.onRemove,
  });

  final ScanImage image;
  final String tooltip;
  final VoidCallback onRemove;

  static const _size = 88.0;

  /// The least a finger is given to hit, on the corner of a small picture.
  static const _target = 44.0;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _size,
    child: Stack(
      children: [
        ScanThumb(image: image, size: _size),
        Positioned(
          top: 0,
          right: 0,
          child: Tooltip(
            message: tooltip,
            child: InkResponse(
              onTap: onRemove,
              radius: _target / 2,
              child: const SizedBox.square(
                dimension: _target,
                child: Center(child: PhotoBadge(icon: Icons.close)),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
