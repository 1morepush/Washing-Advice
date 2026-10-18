/// Looking at a listing's photographs, and saying what a new one is of.
///
/// The garment page has a photograph viewer, and it does not fit here: it is a
/// route keyed by a garment, built on that garment's photographs, with the
/// garment's own address in the browser. A listing's photographs are a list of
/// stored pictures with no garment necessarily behind them, so this is the
/// same idea made small — one picture at a time, swipe for the next, pinch to
/// look closer — and nothing more.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../core/theme.dart';
import '../../../widgets/garment_glyph.dart';
import '../../../widgets/rinse_kit.dart';
import '../../../widgets/stored_image.dart';

/// What stands in for a photograph that cannot be shown: the silhouette of what
/// is being sold, on the well every garment sits on.
class PhotoSilhouette extends StatelessWidget {
  const PhotoSilhouette({required this.type, super.key});

  final ItemType type;

  @override
  Widget build(BuildContext context) => GarmentWell(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: GarmentGlyph(
        kind: glyphKindFor(type),
        fill: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
        edge: context.rinse.garmentEdge,
      ),
    ),
  );
}

/// Opens [photos] full screen, on the one at [index].
Future<void> showListingPhotos(
  BuildContext context, {
  required List<ListingPhoto> photos,
  required int index,
  required ItemType type,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ListingPhotoPager(photos: photos, index: index, type: type),
  ),
);

/// The photographs of a listing, one to a page.
class ListingPhotoPager extends StatefulWidget {
  const ListingPhotoPager({
    required this.photos,
    required this.index,
    required this.type,
    super.key,
  });

  final List<ListingPhoto> photos;
  final int index;
  final ItemType type;

  @override
  State<ListingPhotoPager> createState() => _ListingPhotoPagerState();
}

class _ListingPhotoPagerState extends State<ListingPhotoPager> {
  late final PageController _pages = PageController(
    initialPage: widget.index.clamp(0, widget.photos.length - 1),
  );
  late int _page = _pages.initialPage;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: AppBarTitle(
          '${photos[_page].shot.label} · ${_page + 1} of ${photos.length}',
        ),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: photos.length,
        onPageChanged: (page) => setState(() => _page = page),
        itemBuilder: (context, index) =>
            _ZoomablePhoto(photo: photos[index], type: widget.type),
      ),
    );
  }
}

/// One photograph, whole, that can be pinched closer.
///
/// Dragging moves the picture only once it is magnified. Before that a drag is
/// a swipe to the next page, and an [InteractiveViewer] that always took drags
/// would leave the pager unable to turn.
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.photo, required this.type});

  final ListingPhoto photo;
  final ItemType type;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final TransformationController _transform = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    transformationController: _transform,
    maxScale: 4,
    panEnabled: _zoomed,
    child: SizedBox.expand(
      child: StoredImage(
        uri: widget.photo.uri,
        fit: BoxFit.contain,
        fallback: PhotoSilhouette(type: widget.type),
        semanticLabel: '${widget.photo.shot.label} photo',
      ),
    ),
  );
}

/// Asks what a photograph that is about to be taken is of.
///
/// The shots buyers are still waiting for come first, under their own heading,
/// each with the reason a buyer wants it; then every other kind. Null when
/// the person changes their mind.
Future<ListingShot?> showShotPicker(
  BuildContext context, {
  required Set<ListingShot> missing,
}) => showModalBottomSheet<ListingShot>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ShotPicker(missing: missing),
);

class _ShotPicker extends StatelessWidget {
  const _ShotPicker({required this.missing});

  final Set<ListingShot> missing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wanted = [
      for (final shot in ListingShot.values)
        if (missing.contains(shot)) shot,
    ];
    final others = [
      for (final shot in ListingShot.values)
        if (!missing.contains(shot)) shot,
    ];

    Widget tile(ListingShot shot) => ListTile(
      title: Text(shot.label),
      subtitle: Text(shot.why),
      onTap: () => Navigator.of(context).pop(shot),
    );

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'What is the photo of?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (wanted.isNotEmpty) ...[
              const SectionLabel('Buyers are waiting for these'),
              for (final shot in wanted) tile(shot),
              if (others.isNotEmpty) const SectionLabel('Anything else'),
            ],
            for (final shot in others) tile(shot),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
