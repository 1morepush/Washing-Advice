/// Framing a photograph on the garment.
///
/// Opened over whatever screen collected the shot and handed back the cropped
/// image, so neither scan flow has to know where the bytes went in between.
///
/// The geometry is all in `crop.dart`, in image pixels, so what is exported is
/// what was on screen rather than a second calculation that can disagree with
/// the first.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../widgets/status_message.dart';
import '../wardrobe/mask_edit.dart' show MaskGeometry;
import 'crop.dart';

/// Opens the cropper for [image] and returns the cropped version.
///
/// Null when the user backed out, which is different from returning the
/// original: a caller that treated the two the same would re-encode a
/// photograph somebody had decided not to touch.
Future<ScanImage?> showCropper(BuildContext context, ScanImage image) =>
    Navigator.of(context).push<ScanImage>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CropScreen(image: image),
      ),
    );

class CropScreen extends StatefulWidget {
  const CropScreen({required this.image, super.key});

  final ScanImage image;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  ui.Image? _decoded;
  Rect? _crop;
  CropHandle? _holding;
  bool _saving = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // On CanvasKit this holds WASM heap the Dart collector does not account
    // for, so a cropper opened and left a few times is a real leak.
    _decoded?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final image = await decodeImageFromList(
        Uint8List.fromList(widget.image.bytes),
      );
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _decoded = image;
        _crop = wholeFrame(
          Size(image.width.toDouble(), image.height.toDouble()),
        );
      });
    } on Exception catch (error) {
      if (mounted) setState(() => _failure = '$error');
    }
  }

  Size get _imageSize =>
      Size(_decoded!.width.toDouble(), _decoded!.height.toDouble());

  Future<void> _apply() async {
    final decoded = _decoded;
    final crop = _crop;
    if (decoded == null || crop == null || _saving) return;

    setState(() => _saving = true);
    try {
      final cropped = await cropScanImage(
        image: widget.image,
        decoded: decoded,
        crop: crop,
      );
      if (mounted) Navigator.of(context).pop(cropped);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failure = 'The crop could not be applied. $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('Frame the garment'),
      ),
      body: switch ((_failure, _decoded)) {
        (final String failure, _) => StatusMessage(
          icon: Icons.broken_image_outlined,
          title: 'Could not open the photo',
          detail: failure,
        ),
        (_, null) => const Center(child: CircularProgressIndicator()),
        (_, final ui.Image decoded) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Drag the corners in so the garment fills the frame. The '
                'background is worked out from the edges of the photo, so the '
                'less of the room is in shot the better the cutout.',
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
                      _imageSize,
                      constraints.biggest,
                    );

                    return Listener(
                      key: cropCanvasKey,
                      onPointerDown: (event) {
                        setState(() {
                          _holding = handleAt(
                            _crop!,
                            geometry.toImage(event.localPosition),
                            // A comfortable finger radius, converted once so
                            // the tolerance is the same on any screen.
                            tolerance: geometry.brushToImage(28),
                          );
                        });
                      },
                      onPointerMove: (event) {
                        if (_holding case final CropHandle handle) {
                          setState(() {
                            _crop = dragHandle(
                              crop: _crop!,
                              handle: handle,
                              point: geometry.toImage(event.localPosition),
                              delta: Offset(
                                event.delta.dx / geometry.scale,
                                event.delta.dy / geometry.scale,
                              ),
                              imageSize: _imageSize,
                            );
                          });
                        }
                      },
                      onPointerUp: (_) => setState(() => _holding = null),
                      onPointerCancel: (_) => setState(() => _holding = null),
                      child: CustomPaint(
                        painter: _CropPainter(
                          image: decoded,
                          crop: _crop!,
                          geometry: geometry,
                          scrim: theme.colorScheme.scrim,
                          line: theme.colorScheme.onSurface,
                        ),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () =>
                                setState(() => _crop = wholeFrame(_imageSize)),
                      child: const Text('Reset'),
                    ),
                    const Spacer(),
                    if (_saving)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    FilledButton(
                      onPressed: _saving ? null : _apply,
                      child: const Text('Use this'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      },
    );
  }
}

/// The paint surface, named so a test can put a finger on this one rather than
/// on whichever `CustomPaint` a Material screen happens to end with.
const cropCanvasKey = ValueKey<String>('crop canvas');

class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.image,
    required this.crop,
    required this.geometry,
    required this.scrim,
    required this.line,
  });

  final ui.Image image;
  final Rect crop;
  final MaskGeometry geometry;
  final Color scrim;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final destination = geometry.destination;
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      destination,
      Paint(),
    );

    // The kept region in widget space, which is what everything below draws
    // against — the crop itself is in image pixels.
    final kept = Rect.fromLTRB(
      destination.left + crop.left * geometry.scale,
      destination.top + crop.top * geometry.scale,
      destination.left + crop.right * geometry.scale,
      destination.top + crop.bottom * geometry.scale,
    );

    // Darkened outside rather than hidden, so it stays obvious what is being
    // given up rather than only what is being kept.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(destination),
        Path()..addRect(kept),
      ),
      Paint()..color = scrim.withValues(alpha: 0.6),
    );

    canvas.drawRect(
      kept,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = line,
    );

    final handle = Paint()..color = line;
    for (final corner in [
      kept.topLeft,
      kept.topRight,
      kept.bottomLeft,
      kept.bottomRight,
    ]) {
      canvas.drawCircle(corner, 8, handle);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.crop != crop ||
      old.image != image ||
      old.geometry.destination != geometry.destination;
}
