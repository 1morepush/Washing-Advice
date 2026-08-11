/// Fixing a cutout with a finger.
///
/// The remover is deterministic, so "try again" on the same photograph gives
/// exactly the same wrong answer. This is the other way out: paint back what
/// it ate, rub out what it left, and save the result as the new cutout.
///
/// The compositing and the geometry are in `mask_edit.dart` and tested against
/// real pixels; this file is gestures, chrome and loading.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/images/image_store.dart';
import '../../widgets/status_message.dart';
import 'cutout_controller.dart';
import 'mask_edit.dart';

/// The paint surface itself.
///
/// Named because a Material screen is full of `CustomPaint`s — the ink, the
/// slider, the segmented button — and a test putting a finger on the canvas
/// has to reach this one rather than whichever happens to be last in the tree.
const maskCanvasKey = ValueKey<String>('mask canvas');

class MaskEditorScreen extends ConsumerWidget {
  const MaskEditorScreen({required this.id, super.key});

  final ItemId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemProvider(id));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/item/${id.value}')),
        title: const Text('Tidy the cutout'),
      ),
      body: item.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StatusMessage.failure(
          title: 'Could not open this item',
          error: error,
        ),
        data: (value) {
          final photo = value?.photos.displayPhoto;
          if (value == null || photo == null) {
            return const StatusMessage(
              icon: Icons.image_not_supported_outlined,
              title: 'Nothing to tidy',
              detail: 'This item has no photograph to work from.',
            );
          }
          return _Editor(item: value, photo: photo);
        },
      ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.item, required this.photo});

  final WardrobeItem item;
  final ItemPhoto photo;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  ui.Image? _original;
  ui.Image? _cutout;

  final _strokes = <MaskStroke>[];
  MaskStroke? _live;

  /// Bumped on every pointer move so only the painter repaints, rather than
  /// rebuilding the widget tree for each of hundreds of events in a drag.
  final _revision = ValueNotifier<int>(0);

  MaskMode _mode = MaskMode.subtract;
  double _brush = 24;
  bool _loading = true;
  bool _saving = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // On CanvasKit these hold WASM heap the Dart collector does not account
    // for, so an editor opened and left a few times is a real leak.
    _original?.dispose();
    _cutout?.dispose();
    _revision.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = ref.read(imageStoreProvider);
    try {
      final originalBytes = await store.read(widget.photo.uri);
      if (originalBytes == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _failure = 'The photograph for this item is missing.';
          });
        }
        return;
      }

      final original = await decodeImageFromList(originalBytes);
      // Null when the remover failed outright — the editor still works, it
      // just starts from nothing and the whole garment is painted in. That is
      // the case most in need of a hand-drawn mask, so it must not be the one
      // that refuses to open.
      ui.Image? cutout;
      if (widget.photo.cutoutUri case final String uri) {
        final bytes = await store.read(uri);
        if (bytes != null) cutout = await decodeImageFromList(bytes);
      }

      if (!mounted) {
        original.dispose();
        cutout?.dispose();
        return;
      }
      setState(() {
        _original = original;
        _cutout = cutout;
        // Nothing to rub out of an empty mask, so open on the mode that can
        // actually do something.
        _mode = cutout == null ? MaskMode.add : MaskMode.subtract;
        _loading = false;
      });
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failure = 'Could not open the photograph. $error';
        });
      }
    }
  }

  Future<void> _save() async {
    final original = _original;
    if (original == null || _saving) return;

    setState(() => _saving = true);
    try {
      final bytes = await renderMask(
        original: original,
        cutout: _cutout,
        strokes: _strokes,
      );

      final store = ref.read(imageStoreProvider);
      // The name is a pure function of the photo and both stores key by name,
      // so repeated edits of the same photograph overwrite rather than leaving
      // a file per save.
      final uri = await store.save(
        bytes,
        name: cutoutNameFor(widget.item.id, widget.photo),
      );
      await discardSupersededCutout(store, widget.photo.cutoutUri, uri);

      await ref
          .read(wardrobeRepositoryProvider)
          .save(
            widget.item.copyWith(
              photos: widget.item.photos.withCutout(widget.photo.uri, uri),
              updatedAt: DateTime.now(),
            ),
          );

      ref.invalidate(itemProvider(widget.item.id));
      if (mounted) context.go('/item/${widget.item.id.value}');
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failure = 'Could not save the cutout. $error';
        });
      }
    }
  }

  void _begin(Offset local, MaskGeometry geometry) {
    _live = MaskStroke(
      mode: _mode,
      points: [geometry.toImage(local)],
      width: geometry.brushToImage(_brush),
    );
    _revision.value++;
  }

  void _extend(Offset local, MaskGeometry geometry) {
    if (_live case final MaskStroke stroke) {
      _live = stroke.extendedTo(geometry.toImage(local));
      _revision.value++;
    }
  }

  void _end() {
    if (_live case final MaskStroke stroke) {
      _strokes.add(stroke);
      _live = null;
      // A rebuild rather than a repaint: Undo becomes available, and that is
      // widget state rather than canvas state.
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failure case final String failure) {
      return StatusMessage(
        icon: Icons.broken_image_outlined,
        title: 'Could not tidy this cutout',
        detail: failure,
      );
    }

    final original = _original!;
    final imageSize = Size(
      original.width.toDouble(),
      original.height.toDouble(),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            _mode == MaskMode.add
                ? 'Paint over anything the app removed by mistake.'
                : 'Paint over anything left behind that is not the garment.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final geometry = MaskGeometry.fit(
                  imageSize,
                  constraints.biggest,
                );

                return Listener(
                  key: maskCanvasKey,
                  // Raw pointer events rather than a gesture recogniser: there
                  // is nothing here to disambiguate against, and a recogniser
                  // would swallow the first few millimetres of every stroke
                  // while it decided.
                  onPointerDown: (event) =>
                      _begin(event.localPosition, geometry),
                  onPointerMove: (event) =>
                      _extend(event.localPosition, geometry),
                  onPointerUp: (_) => _end(),
                  onPointerCancel: (_) => _end(),
                  child: CustomPaint(
                    painter: _MaskPainter(
                      original: original,
                      cutout: _cutout,
                      strokes: _strokes,
                      live: () => _live,
                      geometry: geometry,
                      imageSize: imageSize,
                      repaint: _revision,
                      checker: theme.colorScheme.surfaceContainerHighest,
                    ),
                    size: Size.infinite,
                  ),
                );
              },
            ),
          ),
        ),
        _Controls(
          mode: _mode,
          brush: _brush,
          canUndo: _strokes.isNotEmpty,
          saving: _saving,
          onMode: (mode) => setState(() => _mode = mode),
          onBrush: (width) => setState(() => _brush = width),
          onUndo: () => setState(_strokes.removeLast),
          onCancel: () => context.go('/item/${widget.item.id.value}'),
          onSave: _save,
        ),
      ],
    );
  }
}

class _MaskPainter extends CustomPainter {
  _MaskPainter({
    required this.original,
    required this.cutout,
    required this.strokes,
    required this.live,
    required this.geometry,
    required this.imageSize,
    required this.checker,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ui.Image original;
  final ui.Image? cutout;
  final List<MaskStroke> strokes;

  /// Read at paint time rather than captured, so the stroke under the finger
  /// is the current one without rebuilding the painter for every event.
  final MaskStroke? Function() live;

  final MaskGeometry geometry;
  final Size imageSize;
  final Color checker;

  @override
  void paint(Canvas canvas, Size size) {
    // Something behind the transparency, or the removed background reads as
    // the page rather than as absence.
    canvas.drawRect(geometry.destination, Paint()..color = checker);

    paintMask(
      canvas,
      original: original,
      cutout: cutout,
      strokes: [...strokes, ?live()],
      destination: geometry.destination,
      imageSize: imageSize,
    );
  }

  @override
  bool shouldRepaint(_MaskPainter old) =>
      old.original != original ||
      old.cutout != cutout ||
      old.strokes.length != strokes.length ||
      old.geometry.destination != geometry.destination;
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.mode,
    required this.brush,
    required this.canUndo,
    required this.saving,
    required this.onMode,
    required this.onBrush,
    required this.onUndo,
    required this.onCancel,
    required this.onSave,
  });

  final MaskMode mode;
  final double brush;
  final bool canUndo;
  final bool saving;
  final ValueChanged<MaskMode> onMode;
  final ValueChanged<double> onBrush;
  final VoidCallback onUndo;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<MaskMode>(
                  segments: const [
                    ButtonSegment(
                      value: MaskMode.subtract,
                      icon: Icon(Icons.auto_fix_normal),
                      label: Text('Remove'),
                    ),
                    ButtonSegment(
                      value: MaskMode.add,
                      icon: Icon(Icons.brush_outlined),
                      label: Text('Restore'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (chosen) => onMode(chosen.first),
                ),
              ),
              IconButton(
                onPressed: canUndo ? onUndo : null,
                icon: const Icon(Icons.undo),
                tooltip: 'Undo the last stroke',
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.circle, size: 10),
              Expanded(
                child: Slider(
                  value: brush,
                  min: 8,
                  max: 72,
                  onChanged: onBrush,
                ),
              ),
              const Icon(Icons.circle, size: 22),
            ],
          ),
          Row(
            children: [
              // Cancel is the only exit that writes nothing. An editor that
              // silently commits on back-navigation is worse than one with no
              // editor at all.
              TextButton(
                onPressed: saving ? null : onCancel,
                child: const Text('Cancel'),
              ),
              const Spacer(),
              if (saving)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              FilledButton(
                onPressed: saving ? null : onSave,
                child: const Text('Save cutout'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
