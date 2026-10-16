/// A garment's photographs, large enough to tell similar greys apart.
///
/// The thumbnails the app draws everywhere are 32 to 84 px wide and prefer the
/// cutout, which is right for scanning a column of garments and wrong for
/// answering "is this the charcoal one or the black one?". This is the other
/// half: tap a picture and see what was actually photographed, at the size of
/// the screen, with pinch and double-tap to look closer.
///
/// [showPhotoViewer] opens it; [EnlargeOnTap] is the wrapper that makes a
/// thumbnail open it, so every call site gets the same hit target, ripple and
/// semantics rather than each growing its own.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import '../data/images/image_store.dart';
import 'back_navigation.dart';
import 'garment_glyph.dart';

/// "Uniqlo · Sweater": what the garment is, built only from what is recorded,
/// so a garment with no brand reads just "Sweater". Shared by the garment
/// page's heading and the viewer's header so the two cannot disagree.
String garmentSubtitle(WardrobeItem item) => [
  if (item.brand case final Confident<String> brand) brand.value,
  item.type.value.label,
].where((part) => part.trim().isNotEmpty).join(' · ');

/// The longest side a photograph is decoded to in the viewer, in pixels.
///
/// Enough to zoom into on a phone, small enough (about 16MB of RGBA at 2048 x
/// 2048) that a 48-megapixel original cannot take the app down with it.
const int photoViewerMaxExtent = 2048;

/// How far the viewer zooms. One is the whole picture; five is a thread.
const double photoViewerMinScale = 1;
const double photoViewerMaxScale = 5;

/// What a double-tap zooms to.
const double _doubleTapScale = 2.5;

/// Full-size bytes for the stores with no files (the browser and the demo).
///
/// Deliberately not [imageBytesProvider]: that one keeps the last two dozen
/// photographs alive for scrolling back, which suits thumbnails and is exactly
/// wrong for pictures this large. This provider is released the moment the
/// viewer closes, and the viewer evicts its decoded copy from the image cache
/// then too.
final _viewerBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>(
      (ref, uri) => ref.watch(imageStoreProvider).read(uri),
    );

/// Where the viewer for [id] lives, so that a history step, a reload or a
/// shared link lands on the same photograph.
///
/// [offerOpen] is carried as a flag that is only written when it is false: a
/// bare `/photo/<id>` is what somebody arriving from outside should see, with
/// the way on to the garment.
String photoViewerLocation(ItemId id, {int page = 0, bool offerOpen = true}) {
  final query = {if (page > 0) 'page': '$page', if (!offerOpen) 'open': '0'};
  return Uri(
    path: '/photo/${id.value}',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

/// Opens the viewer on [item]'s photographs, starting at the one its
/// thumbnail shows.
///
/// It is a route of the app's router, not a dialog pushed on the side, so the
/// browser's Back, an edge-swipe and a reload all treat it as the screen it is.
///
/// With [offerOpen] the viewer carries an "Open garment" button, for pictures
/// met away from the garment's own page; the garment page passes false.
Future<void> showPhotoViewer(
  BuildContext context,
  WardrobeItem item, {
  bool offerOpen = true,
}) {
  final shown = item.photos.displayPhoto;
  final page = shown == null
      ? 0
      : math.max(0, item.photos.photos.indexOf(shown));
  return GoRouter.of(
    context,
  ).push<void>(photoViewerLocation(item.id, page: page, offerOpen: offerOpen));
}

/// The route's page: the viewer for the garment called [id].
///
/// Looks the garment up as the garment page does, so one that has gone since
/// the link was made says so, with a way out, instead of a blank screen.
class PhotoViewerScreen extends ConsumerWidget {
  const PhotoViewerScreen({
    required this.id,
    this.page = 0,
    this.offerOpen = true,
    super.key,
  });

  final ItemId id;
  final int page;
  final bool offerOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemProvider(id));
    final found = item.valueOrNull;
    if (found != null) {
      return _PhotoViewer(item: found, initialPage: page, offerOpen: offerOpen);
    }
    return Scaffold(
      backgroundColor: _ground,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: item.isLoading
                  ? const _Loading()
                  : Text(
                      item.hasError
                          ? 'Could not open this photo.'
                          : 'This item no longer exists.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: _inkQuiet),
                    ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _CloseButton(
                onPressed: () => context.backOr('/item/${id.value}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A fade between the viewer and what is under it, none under reduced motion.
Page<void> photoViewerPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final instant = MediaQuery.disableAnimationsOf(context);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    opaque: true,
    fullscreenDialog: true,
    transitionDuration: instant
        ? Duration.zero
        : const Duration(milliseconds: 180),
    reverseTransitionDuration: instant
        ? Duration.zero
        : const Duration(milliseconds: 140),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// Wraps a thumbnail so that pressing it opens the viewer.
///
/// A tap by default. Where the picture sits inside something whose tap already
/// means something (a row that opens the garment, a tile that selects it),
/// pass [onLongPress] and the tap keeps its meaning.
///
/// The thumbnail stays the size it was; what grows is the target around it,
/// to 48dp, so a 40dp picture is still easy to hit. That does make the wrapper
/// 48dp where the picture is smaller, which the call sites account for.
class EnlargeOnTap extends StatelessWidget {
  const EnlargeOnTap({
    required this.item,
    required this.child,
    this.onLongPress = false,
    this.offerOpen = true,
    this.borderRadius,
    super.key,
  });

  final WardrobeItem item;
  final Widget child;

  /// Open on a long-press instead of a tap.
  final bool onLongPress;

  /// Passed to [showPhotoViewer].
  final bool offerOpen;

  /// The shape of the ripple; the app's tile radius unless the picture is
  /// clipped to something else.
  final BorderRadius? borderRadius;

  static const double minTarget = 48;

  @override
  Widget build(BuildContext context) {
    void open() => showPhotoViewer(context, item, offerOpen: offerOpen);
    final radius = borderRadius ?? context.rinse.tileBorderRadius;

    return Semantics(
      container: true,
      button: true,
      label: 'Enlarge photo of ${item.displayName}',
      onTap: onLongPress ? null : open,
      onLongPress: onLongPress ? open : null,
      customSemanticsActions: onLongPress
          ? {const CustomSemanticsAction(label: 'Enlarge photo'): open}
          : null,
      // The picture and the ripple are one thing to a screen reader; the label
      // above says what it does.
      child: ExcludeSemantics(
        // The margin round a small picture answers too, which is the point of
        // it; the ripple belongs to the picture itself.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onLongPress ? null : open,
          onLongPress: onLongPress ? open : null,
          child: _MinTarget(
            size: minTarget,
            child: Stack(
              children: [
                child,
                // No ripple for a long-press: an InkResponse always claims
                // the tap too, and here the tap belongs to whatever the
                // picture sits inside (it opens the garment, or picks it).
                if (!onLongPress)
                  Positioned.fill(
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkResponse(
                        containedInkWell: true,
                        highlightShape: BoxShape.rectangle,
                        customBorder: RoundedRectangleBorder(
                          borderRadius: radius,
                        ),
                        onTap: open,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sizes itself to its child, or to [size] where the child is smaller and the
/// constraints allow, and centres the child. Under tight constraints it does
/// nothing, so a thumbnail told to fill a cell still fills it.
class _MinTarget extends SingleChildRenderObjectWidget {
  const _MinTarget({required this.size, required super.child});

  final double size;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMinTarget(size);

  @override
  void updateRenderObject(BuildContext context, _RenderMinTarget renderObject) {
    renderObject.minSize = size;
  }
}

class _RenderMinTarget extends RenderShiftedBox {
  _RenderMinTarget(this._minSize) : super(null);

  double _minSize;
  set minSize(double value) {
    if (value == _minSize) return;
    _minSize = value;
    markNeedsLayout();
  }

  Size _sizeFor(Size child, BoxConstraints constraints) =>
      constraints.constrain(
        Size(math.max(child.width, _minSize), math.max(child.height, _minSize)),
      );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.constrain(Size.zero);
    return _sizeFor(child.getDryLayout(constraints), constraints);
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size.zero);
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = _sizeFor(child.size, constraints);
    (child.parentData! as BoxParentData).offset = Offset(
      (size.width - child.size.width) / 2,
      (size.height - child.size.height) / 2,
    );
  }
}

// -----------------------------------------------------------------------------
// The viewer
// -----------------------------------------------------------------------------

// A photograph is looked at on black in every appearance mode: it is the
// ground a picture is judged against, not a themed surface, so these are fixed
// rather than drawn from the colour scheme.
const Color _ground = Colors.black;
const Color _ink = Colors.white;
const Color _inkQuiet = Color(0xB3FFFFFF);
const Color _chip = Color(0x33FFFFFF);

class _PhotoViewer extends ConsumerStatefulWidget {
  const _PhotoViewer({
    required this.item,
    required this.initialPage,
    required this.offerOpen,
  });

  final WardrobeItem item;

  /// The photograph to open on, from the address.
  final int initialPage;

  /// Whether to offer "Open garment".
  final bool offerOpen;

  @override
  ConsumerState<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends ConsumerState<_PhotoViewer> {
  late final List<ItemPhoto> _photos = widget.item.photos.photos;
  late final PageController _pages;
  final Map<int, TransformationController> _controllers = {};
  final Map<int, GlobalKey> _imageKeys = {};
  final Map<int, Size> _viewports = {};
  final GlobalKey _pageAreaKey = GlobalKey();
  Offset _doubleTapAt = Offset.zero;
  late int _page;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage.clamp(0, math.max(0, _photos.length - 1));
    _pages = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pages.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TransformationController _controllerFor(int index) =>
      _controllers.putIfAbsent(index, () {
        final controller = TransformationController();
        controller.addListener(() {
          if (index != _page || !mounted) return;
          final scale = controller.value.getMaxScaleOnAxis();
          if ((scale - _scale).abs() > 0.001) setState(() => _scale = scale);
        });
        return controller;
      });

  bool get _zoomed => _scale > 1.01;

  void _onPageChanged(int index) {
    // Every other picture goes back to whole: a new photograph should never
    // arrive already magnified.
    for (final entry in _controllers.entries) {
      entry.value.value = Matrix4.identity();
    }
    setState(() {
      _page = index;
      _scale = 1;
    });
    // The address follows the photograph, replacing rather than adding, so a
    // reload lands on this one and Back still leaves the viewer in one step.
    GoRouter.maybeOf(context)?.replace(
      photoViewerLocation(
        widget.item.id,
        page: index,
        offerOpen: widget.offerOpen,
      ),
    );
  }

  void _goTo(int index) {
    if (index < 0 || index >= _photos.length || _zoomed) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  /// Multiplies the current picture's zoom by [factor] about [focal] (the
  /// middle of the picture when null), within the limits.
  void _zoomBy(double factor, [Offset? focal]) {
    final viewport = _viewports[_page];
    if (viewport == null) return;
    final controller = _controllerFor(_page);
    final current = controller.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(
      photoViewerMinScale,
      photoViewerMaxScale,
    );
    if (target <= photoViewerMinScale + 0.001) {
      controller.value = Matrix4.identity();
      return;
    }
    final at = focal ?? viewport.center(Offset.zero);
    final ratio = target / current;
    final next =
        Matrix4.translationValues(at.dx, at.dy, 0.0) *
        Matrix4.diagonal3Values(ratio, ratio, 1.0) *
        Matrix4.translationValues(-at.dx, -at.dy, 0.0) *
        controller.value;
    // Keep the picture over the screen: left alone, zooming out about a corner
    // would leave it adrift.
    final shift = next.getTranslation();
    next.setTranslationRaw(
      shift.x.clamp(viewport.width * (1 - target), 0.0),
      shift.y.clamp(viewport.height * (1 - target), 0.0),
      0.0,
    );
    controller.value = next;
  }

  void _toggleZoom(Offset focal) {
    if (_zoomed) {
      _controllerFor(_page).value = Matrix4.identity();
    } else {
      _zoomBy(_doubleTapScale, focal);
    }
  }

  void _close() => context.backOr('/item/${widget.item.id.value}');

  bool _opening = false;

  /// Replaces the viewer with the garment's page, so Back from the page does
  /// not return to a viewer. Once only: a second tap before the page arrives
  /// would otherwise replace the same entry twice.
  void _openGarment() {
    if (_opening) return;
    _opening = true;
    context.pushReplacement('/item/${widget.item.id.value}');
  }

  /// A double-tap zooms about the finger.
  void _onDoubleTap() {
    final area = _pageAreaKey.currentContext?.findRenderObject();
    if (area is! RenderBox || !area.attached) return;
    final local = area.globalToLocal(_doubleTapAt);
    if (!(Offset.zero & area.size).contains(local)) return;
    _toggleZoom(local);
  }

  /// A tap on the picture does nothing (it is where fingers land); a tap
  /// anywhere else on the black closes.
  void _onTapUp(TapUpDetails details) {
    final box = _imageKeys[_page]?.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached && _photos.isNotEmpty) {
      final local = box.globalToLocal(details.globalPosition);
      if ((Offset.zero & box.size).contains(local)) return;
    }
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final subtitle = garmentSubtitle(item);
    final textTheme = Theme.of(context).textTheme;
    final hasPhotos = _photos.isNotEmpty;
    final role = hasPhotos ? _photos[_page].role.label : null;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _goTo(_page - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _goTo(_page + 1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: _ground,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  color: _ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: _inkQuiet,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _CloseButton(onPressed: _close),
                      ],
                    ),
                  ),
                  Expanded(
                    child: hasPhotos
                        ? GestureDetector(
                            key: _pageAreaKey,
                            // Tap and double-tap on one detector: a tap waits
                            // out the double-tap window only here, where a
                            // second tap is possible, and not on the buttons.
                            onTapUp: _onTapUp,
                            onDoubleTapDown: (details) =>
                                _doubleTapAt = details.globalPosition,
                            onDoubleTap: _onDoubleTap,
                            child: ScrollConfiguration(
                              // A mouse can drag between pictures too; the
                              // default leaves that to touch.
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(
                                    dragDevices: PointerDeviceKind.values
                                        .toSet(),
                                  ),
                              child: PageView.builder(
                                controller: _pages,
                                itemCount: _photos.length,
                                onPageChanged: _onPageChanged,
                                // Zoomed in, a drag pans the picture; paging
                                // waits until it is whole again.
                                physics: _zoomed
                                    ? const NeverScrollableScrollPhysics()
                                    : null,
                                itemBuilder: (_, index) => _PhotoPage(
                                  item: item,
                                  photo: _photos[index],
                                  controller: _controllerFor(index),
                                  imageKey: _imageKeys.putIfAbsent(
                                    index,
                                    GlobalKey.new,
                                  ),
                                  onViewport: (size) =>
                                      _viewports[index] = size,
                                ),
                              ),
                            ),
                          )
                        : _NoPhoto(item: item),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (role != null)
                          Text(
                            role,
                            textAlign: TextAlign.center,
                            style: textTheme.titleSmall?.copyWith(
                              color: _ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (_photos.length > 1) ...[
                          const SizedBox(height: 6),
                          _PageDots(count: _photos.length, current: _page),
                        ],
                        if (hasPhotos || widget.offerOpen) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (hasPhotos)
                                _ZoomButton(
                                  icon: Icons.remove,
                                  tooltip: 'Zoom out',
                                  onPressed: _scale > photoViewerMinScale + 0.01
                                      ? () => _zoomBy(0.5)
                                      : null,
                                ),
                              if (widget.offerOpen)
                                FilledButton(
                                  onPressed: _openGarment,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _ink,
                                    foregroundColor: _ground,
                                    minimumSize: const Size(48, 48),
                                  ),
                                  child: const Text('Open garment'),
                                ),
                              if (hasPhotos)
                                _ZoomButton(
                                  icon: Icons.add,
                                  tooltip: 'Zoom in',
                                  onPressed: _scale < photoViewerMaxScale - 0.01
                                      ? () => _zoomBy(2)
                                      : null,
                                ),
                            ],
                          ),
                        ],
                      ],
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

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: 'Close',
    icon: const Icon(Icons.close),
    style: IconButton.styleFrom(
      backgroundColor: _chip,
      foregroundColor: _ink,
      minimumSize: const Size.square(48),
      fixedSize: const Size.square(48),
    ),
  );
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    icon: Icon(icon),
    style: IconButton.styleFrom(
      backgroundColor: _chip,
      foregroundColor: _ink,
      disabledBackgroundColor: const Color(0x14FFFFFF),
      disabledForegroundColor: const Color(0x66FFFFFF),
      minimumSize: const Size.square(48),
      fixedSize: const Size.square(48),
    ),
  );
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Photo ${current + 1} of $count',
    child: ExcludeSemantics(
      child: Row(
        key: const ValueKey('photo-viewer-dots'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == current ? _ink : const Color(0x55FFFFFF),
              ),
            ),
        ],
      ),
    ),
  );
}

/// One photograph, zoomable.
class _PhotoPage extends StatelessWidget {
  const _PhotoPage({
    required this.item,
    required this.photo,
    required this.controller,
    required this.imageKey,
    required this.onViewport,
  });

  final WardrobeItem item;
  final ItemPhoto photo;
  final TransformationController controller;
  final GlobalKey imageKey;
  final void Function(Size) onViewport;

  @override
  Widget build(BuildContext context) {
    // The original first: it is what was photographed, where a cutout's edges
    // are cropped and a black garment on transparency is hard to read. The
    // cutout is the fallback for an original that cannot be read.
    final candidates = [
      photo.uri,
      if (photo.cutoutUri != null) photo.cutoutUri!,
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final viewport = box.biggest;
        onViewport(viewport);
        return Semantics(
          image: true,
          label: 'Photo of ${item.displayName}, ${photo.role.label}',
          child: InteractiveViewer(
            transformationController: controller,
            minScale: photoViewerMinScale,
            maxScale: photoViewerMaxScale,
            child: SizedBox.fromSize(
              size: viewport,
              child: Center(
                child: _PhotoSource(
                  item: item,
                  candidates: candidates,
                  index: 0,
                  viewport: viewport,
                  imageKey: imageKey,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tries [candidates] in order from [index]: the first that loads is drawn,
/// and when none does, the failure message.
class _PhotoSource extends ConsumerWidget {
  const _PhotoSource({
    required this.item,
    required this.candidates,
    required this.index,
    required this.viewport,
    required this.imageKey,
  });

  final WardrobeItem item;
  final List<String> candidates;
  final int index;
  final Size viewport;
  final GlobalKey imageKey;

  Widget get _next => index + 1 < candidates.length
      ? _PhotoSource(
          item: item,
          candidates: candidates,
          index: index + 1,
          viewport: viewport,
          imageKey: imageKey,
        )
      : _Unreadable(item: item);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uri = candidates[index];
    final store = ref.watch(imageStoreProvider);
    final path = switch (store) {
      final FileBackedImageStore files => files.pathFor(uri),
      _ => null,
    };

    final ImageProvider base;
    if (path != null) {
      base = FileImage(File(path));
    } else {
      final bytes = ref.watch(_viewerBytesProvider(uri));
      if (bytes.isLoading) return const _Loading();
      final data = bytes.valueOrNull;
      if (data == null) return _next;
      base = MemoryImage(data);
    }

    return _DecodedImage(
      key: ValueKey(uri),
      provider: ResizeImage(
        base,
        width: photoViewerMaxExtent,
        height: photoViewerMaxExtent,
        // `fit`: the longer side is scaled to the limit and the shape kept,
        // never squashed to a square, never enlarged past what was stored.
        policy: ResizeImagePolicy.fit,
      ),
      viewport: viewport,
      imageKey: imageKey,
      fallback: _next,
      // A cutout has no background of its own, and on the black ground a dark
      // garment would simply not be there; the original never needs this.
      onTile: index > 0,
    );
  }
}

/// Resolves [provider] itself so that it knows the picture's shape and can
/// draw it exactly as large as the screen allows: an `Image` in a loose box
/// would stop at its stored size, and a small cutout would sit tiny in the
/// middle of a large screen.
class _DecodedImage extends StatefulWidget {
  const _DecodedImage({
    required this.provider,
    required this.viewport,
    required this.imageKey,
    required this.fallback,
    this.onTile = false,
    super.key,
  });

  final ImageProvider provider;
  final Size viewport;
  final GlobalKey imageKey;
  final Widget fallback;

  /// Whether to lay the picture on a lighter tile than the ground.
  final bool onTile;

  @override
  State<_DecodedImage> createState() => _DecodedImageState();
}

class _DecodedImageState extends State<_DecodedImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream != null) return;
    final stream = widget.provider.resolve(
      createLocalImageConfiguration(context),
    );
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted) {
          info.dispose();
          return;
        }
        setState(() {
          _info?.dispose();
          _info = info.clone();
        });
      },
      onError: (_, _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _stream = stream..addListener(listener);
    _listener = listener;
  }

  @override
  void dispose() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _info?.dispose();
    // Flutter's image cache would otherwise keep this picture, decoded, under
    // a key that holds the stored bytes too, for as long as it stays among the
    // newest hundred megabytes. Dropped with the viewer: the decoded pixels and
    // that key. (The thumbnails' own cache entries are separate and stay.)
    widget.provider.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    final info = _info;
    if (info == null) return const _Loading();

    final width = info.image.width.toDouble();
    final height = info.image.height.toDouble();
    final scale = math.min(
      widget.viewport.width / width,
      widget.viewport.height / height,
    );
    return SizedBox(
      key: widget.imageKey,
      width: width * scale,
      height: height * scale,
      child: ColoredBox(
        color: widget.onTile ? const Color(0xFF3C3C3C) : Colors.transparent,
        child: RawImage(
          image: info.image,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading photo',
    child: const SizedBox.square(
      dimension: 32,
      child: CircularProgressIndicator(strokeWidth: 3, color: _ink),
    ),
  );
}

/// The garment's silhouette in its own colour on a quiet tile, with [message]
/// under it.
class _GlyphTile extends StatelessWidget {
  const _GlyphTile({required this.item, required this.message});

  final WardrobeItem item;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = item.colors.value.colors;
    final fill = colors.isEmpty
        ? const Color(0x80FFFFFF)
        : Color(0xFF000000 | colors.first.rgb);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 280,
                  maxHeight: 280,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x14FFFFFF),
                      borderRadius: context.rinse.tileBorderRadius,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: GarmentGlyph(
                        kind: glyphKindFor(item.type.value),
                        fill: fill,
                        // Pale, because the tile is dark: a black sock needs
                        // its outline to be there at all.
                        edge: const Color(0x99FFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: _inkQuiet),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) =>
      _GlyphTile(item: item, message: 'No photo yet');
}

class _Unreadable extends StatelessWidget {
  const _Unreadable({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) =>
      _GlyphTile(item: item, message: 'Could not load this photo');
}
