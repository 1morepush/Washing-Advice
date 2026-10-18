/// The photographs at the top of the listing: the strip of them, adding
/// another, and which ones buyers are still waiting for.
///
/// Photographs lead the screen because they lead the Depop form, and because
/// they are the part of a listing a buyer decides on. The strip shows them in
/// the order Depop will, so the first is the cover.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../data/capture/image_capture_source.dart';
import '../../../widgets/stored_image.dart';
import 'edit_session.dart';
import 'fields.dart';
import 'photo_views.dart';

/// How wide and tall one photograph is drawn in the strip.
const double _tile = 104;

class PhotosSection extends ConsumerStatefulWidget {
  const PhotosSection({
    required this.listing,
    required this.session,
    super.key,
  });

  final Listing listing;
  final ListingEditSession session;

  @override
  ConsumerState<PhotosSection> createState() => _PhotosSectionState();
}

class _PhotosSectionState extends ConsumerState<PhotosSection> {
  bool _adding = false;

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _add() async {
    final shot = await showShotPicker(
      context,
      missing: widget.listing.missingShots,
    );
    if (shot == null || !mounted) return;

    setState(() => _adding = true);
    try {
      final image = await ref.read(imageCaptureProvider).capture();
      // Backing out of the camera is not a failure and says nothing.
      if (image == null) return;

      final kept = await widget.session.addPhoto(image, shot);
      if (!kept && mounted) {
        _say('That photo could not be saved. Try again.');
      }
    } on CaptureFailure catch (failure) {
      if (mounted) _say(failure.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final photos = listing.photos;
    final full = photos.length >= depopPhotoLimit;
    final missing = listing.missingShots;

    return EditorSection(
      title: 'Photos',
      intro:
          '${photos.length} of $depopPhotoLimit. The first one is the cover '
          'buyers see first.',
      children: [
        if (photos.isEmpty)
          const QuietText('No photos yet. Add the cover first.')
        else
          // A row inside a scroll view and not a list: it takes the height of
          // its captions at any text size, which a list of fixed height would
          // have to guess.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, photo) in photos.indexed)
                  Padding(
                    padding: EdgeInsets.only(
                      right: index == photos.length - 1 ? 0 : 10,
                    ),
                    child: _PhotoTile(
                      photo: photo,
                      index: index,
                      total: photos.length,
                      type: listing.itemType,
                      onTap: () => showListingPhotos(
                        context,
                        photos: photos,
                        index: index,
                        type: listing.itemType,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 12),
          QuietText(
            'Missing: ${missing.map((shot) => shot.label.toLowerCase()).join(', ')}'
            ' — buyers ask for these',
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: full || _adding ? null : _add,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add photo'),
          ),
        ),
        if (full) ...[
          const SizedBox(height: 8),
          const QuietText('Depop takes up to 8 photos.'),
        ],
      ],
    );
  }
}

/// One photograph in the strip, with what it is of under it.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.index,
    required this.total,
    required this.type,
    required this.onTap,
  });

  final ListingPhoto photo;
  final int index;
  final int total;
  final ItemType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = context.rinse.tileBorderRadius;

    return Semantics(
      button: true,
      label:
          '${photo.shot.label} photo, ${index + 1} of $total. '
          'Tap to see it large.',
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox(
        width: _tile,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: radius,
              child: SizedBox.square(
                dimension: _tile,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    StoredImage(
                      uri: photo.uri,
                      fallback: PhotoSilhouette(type: type),
                    ),
                    Material(
                      type: MaterialType.transparency,
                      child: InkWell(onTap: onTap),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              photo.shot.label,
              maxLines: 2,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
