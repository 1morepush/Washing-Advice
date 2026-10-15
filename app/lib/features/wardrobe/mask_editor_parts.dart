/// The painter, the controls and the stroke record for the mask editor.
///
/// Split from the editor, which is the gesture handling and saving.
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'mask_edit.dart';

class MaskPainter extends CustomPainter {
  MaskPainter({
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
  bool shouldRepaint(MaskPainter old) =>
      old.original != original ||
      old.cutout != cutout ||
      old.strokes.length != strokes.length ||
      old.geometry.destination != geometry.destination;
}

class MaskControls extends StatelessWidget {
  const MaskControls({
    required this.mode,
    required this.brush,
    required this.canUndo,
    required this.saving,
    required this.refining,
    required this.onMode,
    required this.onBrush,
    required this.onUndo,
    required this.onRefine,
    required this.onCancel,
    required this.onSave,
    super.key,
  });

  final MaskMode mode;
  final double brush;
  final bool canUndo;
  final bool saving;
  final bool refining;
  final ValueChanged<MaskMode> onMode;
  final ValueChanged<double> onBrush;
  final VoidCallback onUndo;
  final VoidCallback onRefine;
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
                tooltip: 'Undo',
              ),
            ],
          ),
          // Offered rather than automatic, and labelled with what it does to
          // *this* canvas rather than named after the technology. The rough
          // work is what makes it work: the remover failed on the original
          // because of everything around the garment, and once that is gone it
          // is being asked a much easier question.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: saving || refining ? null : onRefine,
              icon: refining
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(
                refining
                    ? 'Tidying the edges…'
                    : 'Let the app finish the edges',
              ),
            ),
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

/// The canvas as it stood before an AI pass replaced it.
///
/// Both halves, because a pass changes both: it bakes the strokes into a new
/// cutout and clears them. Restoring only the image would leave the strokes
/// applied twice.
class MaskPass {
  const MaskPass({required this.cutout, required this.strokes});

  final ui.Image? cutout;
  final List<MaskStroke> strokes;
}
