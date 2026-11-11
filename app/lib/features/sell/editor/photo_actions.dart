/// What can be done to one photograph on a listing: make it the cover, move it
/// earlier or later, take it off.
///
/// Two places offer these, the strip and the full-screen viewer, and they must
/// not mean different things by them. So the words, the confirmation and the
/// calls into the session are here, once; the places differ only in how they
/// lay the choices out (a sheet under the tile, a row of buttons under the
/// large picture). Every button is a button with a word on it, and none needs
/// a drag.
///
/// The rules for what a move does to the cover are the core's
/// (`makePhotoCover`, `movePhoto`, `removePhotoAt`); the session applies them.
/// What is decided here is only what to say.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'edit_session.dart';

/// One thing that can be done to a photograph.
enum PhotoAction {
  makeCover('Make this the cover'),
  earlier('Move earlier'),
  later('Move later'),
  remove('Remove photo');

  const PhotoAction(this.label);

  final String label;
}

/// The actions that make sense for the photograph at [index] of [total].
///
/// Not offered rather than offered and ignored: "move earlier" on the first
/// photograph would be a button that does nothing.
List<PhotoAction> photoActionsFor(ListingPhoto photo, int index, int total) => [
  if (index != 0 || photo.shot != ListingShot.cover) PhotoAction.makeCover,
  if (index > 0) PhotoAction.earlier,
  if (index < total - 1) PhotoAction.later,
  PhotoAction.remove,
];

/// One line on what an action does to the cover, where it does anything.
String? photoActionNote(PhotoAction action, int index) => switch (action) {
  PhotoAction.earlier when index == 1 => 'It becomes the cover.',
  PhotoAction.later when index == 0 => 'The next photo becomes the cover.',
  _ => null,
};

/// Does [action] to the photograph at [index].
///
/// Returns the index the photograph is at afterwards, or null if it is gone
/// (removed, or the person said no), so a viewer can follow it. Removing asks
/// first.
Future<int?> doPhotoAction(
  BuildContext context,
  ListingEditSession session,
  PhotoAction action,
  int index,
) async {
  switch (action) {
    case PhotoAction.makeCover:
      session.makeCover(index);
      return 0;
    case PhotoAction.earlier:
      session.movePhotoTo(index, index - 1);
      return index - 1;
    case PhotoAction.later:
      session.movePhotoTo(index, index + 1);
      return index + 1;
    case PhotoAction.remove:
      await confirmAndRemovePhoto(context, session, index);
      return null;
  }
}

/// Asks, then removes the photograph at [index]. True if it was removed.
Future<bool> confirmAndRemovePhoto(
  BuildContext context,
  ListingEditSession session,
  int index,
) async {
  final photos = session.listing.photos;
  if (index < 0 || index >= photos.length) return false;

  final photo = photos[index];
  final garments = await session.garmentHoldsPhoto(index);
  if (!context.mounted) return false;

  final sure = await showDialog<bool>(
    context: context,
    builder: (_) => _ConfirmRemove(
      photo: photo,
      garments: garments,
      becomesCover: index == 0 && photos.length > 1,
      last: photos.length == 1,
    ),
  );
  if (sure != true) return false;

  await session.removePhoto(index);
  return true;
}

class _ConfirmRemove extends StatelessWidget {
  const _ConfirmRemove({
    required this.photo,
    required this.garments,
    required this.becomesCover,
    required this.last,
  });

  final ListingPhoto photo;

  /// Whether a garment also holds the picture, so only the listing lets go.
  final bool garments;
  final bool becomesCover;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final what = garments
        ? 'It comes off this listing. The picture stays with the garment in '
              'your wardrobe.'
        : 'It comes off this listing and the picture is deleted from this '
              "phone. This can't be undone.";
    final then = becomesCover
        ? ' The next photo becomes the cover.'
        : last
        ? ' The listing will have no photos until you add one.'
        : '';

    return AlertDialog(
      scrollable: true,
      title: Text('Remove the ${photo.shot.label.toLowerCase()} photo?'),
      content: Text('$what$then'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep it'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.errorContainer,
            foregroundColor: scheme.onErrorContainer,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    );
  }
}

/// Asks which of the actions to do to the photograph at [index]; null if the
/// person changes their mind.
Future<PhotoAction?> showPhotoActions(
  BuildContext context, {
  required ListingPhoto photo,
  required int index,
  required int total,
}) => showModalBottomSheet<PhotoAction>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _PhotoActionSheet(photo: photo, index: index, total: total),
);

class _PhotoActionSheet extends StatelessWidget {
  const _PhotoActionSheet({
    required this.photo,
    required this.index,
    required this.total,
  });

  final ListingPhoto photo;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                '${photo.shot.label} photo, ${index + 1} of $total',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final action in photoActionsFor(photo, index, total))
              ListTile(
                title: Text(
                  action.label,
                  style: action == PhotoAction.remove
                      ? TextStyle(color: theme.colorScheme.error)
                      : null,
                ),
                subtitle: switch (photoActionNote(action, index)) {
                  final String note => Text(note),
                  null => null,
                },
                onTap: () => Navigator.of(context).pop(action),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
