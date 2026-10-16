import 'package:flutter/widgets.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'svg_path.dart';

/// The care symbols there is art for.
enum CareSymbolKind {
  wash30Gentle,
  wash30Mild,
  wash40,
  doNotBleach,
  doNotTumbleDry,
  tumbleDry,
  dryFlat,
  lineDry,
  iron,
  dryClean,
}

/// A label printed inside a symbol, in grid units.
class CareText {
  const CareText(
    this.text, {
    required this.x,
    required this.y,
    this.size = 9.5,
  });

  final String text;

  /// Horizontal centre.
  final double x;

  /// Baseline.
  final double y;
  final double size;
}

/// The drawing of one symbol on a [careViewBox] grid.
class CareArt {
  const CareArt({
    required this.label,
    this.strokes = const [],
    this.fills = const [],
    this.text,
  });

  /// Default accessibility label.
  final String label;

  /// Outlines, drawn as round-capped strokes.
  final List<String> strokes;

  /// Solid shapes (the dots).
  final List<String> fills;

  final CareText? text;
}

/// Side of the square grid [careArt] is drawn on.
const double careViewBox = 40;

const double _strokeWidth = 2.1;

// Wash tub, then the wave on the water, which the numerals sit beneath.
const _tub = 'M5 10 L9.5 27 H30.5 L35 10';
const _water = 'M7 12.5 Q10.5 9.5 14 12.5 T21 12.5 T28 12.5 T34 12';
const _square = 'M6 6 H34 V34 H6 Z';
const _drum = 'M10.5 20 A9.5 9.5 0 1 0 29.5 20 A9.5 9.5 0 1 0 10.5 20 Z';

/// The art, hand-ported from the design proposal. Circles are written as two
/// arcs so that everything is path data.
const Map<CareSymbolKind, CareArt> careArt = {
  CareSymbolKind.wash30Gentle: CareArt(
    label: 'Wash at 30°, very gentle',
    strokes: [_tub, _water, 'M9 31.5 H31 M9 35.5 H31'],
    text: CareText('30', x: 20, y: 24.5),
  ),
  CareSymbolKind.wash30Mild: CareArt(
    label: 'Wash at 30°, gentle',
    strokes: [_tub, _water, 'M9 32.5 H31'],
    text: CareText('30', x: 20, y: 24.5),
  ),
  CareSymbolKind.wash40: CareArt(
    label: 'Wash at 40°',
    strokes: [_tub, _water],
    text: CareText('40', x: 20, y: 24.5),
  ),
  CareSymbolKind.doNotBleach: CareArt(
    label: 'Do not bleach',
    strokes: ['M20 6 L35 32 H5 Z', 'M9 9 L31 35 M31 9 L9 35'],
  ),
  CareSymbolKind.doNotTumbleDry: CareArt(
    label: 'Do not tumble dry',
    strokes: [_square, _drum, 'M6 6 L34 34 M34 6 L6 34'],
  ),
  CareSymbolKind.tumbleDry: CareArt(
    label: 'Tumble dry',
    strokes: [_square, _drum],
    fills: [
      'M14.8 20 A1.7 1.7 0 1 0 18.2 20 A1.7 1.7 0 1 0 14.8 20 Z',
      'M21.8 20 A1.7 1.7 0 1 0 25.2 20 A1.7 1.7 0 1 0 21.8 20 Z',
    ],
  ),
  CareSymbolKind.dryFlat: CareArt(
    label: 'Dry flat',
    strokes: [_square, 'M11 20 H29'],
  ),
  CareSymbolKind.lineDry: CareArt(
    label: 'Line dry',
    strokes: [_square, 'M7 7 Q20 18 33 7'],
  ),
  CareSymbolKind.iron: CareArt(
    label: 'Iron on low heat',
    strokes: [
      'M4 30 L8.5 17.5 Q9.5 15 12.5 15 H30 Q34 15 34 19 V30 Z',
      'M14 15 Q14.5 9 20.5 9 H29',
    ],
    fills: ['M18.1 23.5 A1.9 1.9 0 1 0 21.9 23.5 A1.9 1.9 0 1 0 18.1 23.5 Z'],
  ),
  CareSymbolKind.dryClean: CareArt(
    label: 'Dry clean',
    strokes: ['M7 20 A13 13 0 1 0 33 20 A13 13 0 1 0 7 20 Z'],
    text: CareText('P', x: 20, y: 24.6, size: 13),
  ),
};

/// The symbols that apply to [care], in the order a label prints them: wash,
/// bleach, dry, iron, professional.
///
/// Only symbols there is art for are returned; anything else the model can say
/// (a 60° wash, three iron dots, a wet-clean circle) is left out rather than
/// drawn wrongly. The label's own words are still the source of truth for
/// those, so callers should keep showing the text too.
List<CareSymbolKind> careSymbolsFor(CareInstructions care) {
  final out = <CareSymbolKind>[];

  final wash = care.wash;
  if (wash.method == WashMethod.machine) {
    final temp = wash.maxTempC;
    if (temp != null && temp <= 30) {
      switch (wash.agitation) {
        case Agitation.veryMild:
          out.add(CareSymbolKind.wash30Gentle);
        case Agitation.mild:
          out.add(CareSymbolKind.wash30Mild);
        case Agitation.normal:
          break; // No art for a plain 30° tub.
      }
    } else if (temp != null && temp <= 40) {
      if (wash.agitation == Agitation.normal) out.add(CareSymbolKind.wash40);
    }
  }

  switch (care.bleach) {
    case BleachAllowance.none:
      out.add(CareSymbolKind.doNotBleach);
    case BleachAllowance.any:
    case BleachAllowance.nonChlorineOnly:
      break;
  }

  if (!care.dry.tumbleDryAllowed) {
    out.add(CareSymbolKind.doNotTumbleDry);
  } else {
    out.add(CareSymbolKind.tumbleDry);
  }
  switch (care.dry.naturalDry) {
    case NaturalDryMethod.flatDry:
      out.add(CareSymbolKind.dryFlat);
    case NaturalDryMethod.lineDry:
      out.add(CareSymbolKind.lineDry);
    case NaturalDryMethod.dripDry:
    case null:
      break;
  }

  switch (care.iron.temperature) {
    case IronTemperature.low:
      out.add(CareSymbolKind.iron);
    case IronTemperature.none:
    case IronTemperature.medium:
    case IronTemperature.high:
      break;
  }

  final pro = care.professional;
  if (!pro.doNotDryClean) {
    switch (pro.solvent) {
      case CleaningSolvent.perchloroethylene:
        out.add(CareSymbolKind.dryClean);
      case CleaningSolvent.hydrocarbon:
      case CleaningSolvent.wetClean:
      case null:
        break;
    }
  }
  return out;
}

/// [careSymbolsFor] for a whole profile.
List<CareSymbolKind> careSymbolsForProfile(CareProfile profile) =>
    careSymbolsFor(profile.instructions);

/// A laundry care symbol drawn in a single [color].
///
/// The numerals use the ambient font ([DefaultTextStyle]) in bold unless
/// [fontFamily] is given. Announced as [semanticLabel], or a default derived
/// from [kind] ("Do not bleach"); pass an empty string to hide it from
/// accessibility when the symbol sits next to text saying the same thing.
class CareSymbol extends StatelessWidget {
  const CareSymbol({
    super.key,
    required this.kind,
    required this.color,
    this.size = 28,
    this.semanticLabel,
    this.fontFamily,
  });

  final CareSymbolKind kind;
  final Color color;
  final double size;
  final String? semanticLabel;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final painter = _CarePainter(
      kind: kind,
      color: color,
      fontFamily: fontFamily ?? base.fontFamily,
      fontFamilyFallback: base.fontFamilyFallback,
    );
    final child = CustomPaint(size: Size.square(size), painter: painter);
    final label = semanticLabel ?? careArt[kind]!.label;
    if (label.isEmpty) return ExcludeSemantics(child: child);
    return Semantics(label: label, image: true, child: child);
  }
}

class _CarePainter extends CustomPainter {
  _CarePainter({
    required this.kind,
    required this.color,
    required this.fontFamily,
    required this.fontFamilyFallback,
  });

  final CareSymbolKind kind;
  final Color color;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (side <= 0) return;
    final art = careArt[kind]!;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / careViewBox);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color
      ..isAntiAlias = true;
    for (final d in art.strokes) {
      canvas.drawPath(parseSvgPath(d), stroke);
    }
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color
      ..isAntiAlias = true;
    for (final d in art.fills) {
      canvas.drawPath(parseSvgPath(d), fill);
    }

    final text = art.text;
    if (text != null) {
      final painter = TextPainter(
        text: TextSpan(
          text: text.text,
          style: TextStyle(
            color: color,
            fontSize: text.size,
            fontWeight: FontWeight.w700,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
            height: 1,
            decoration: TextDecoration.none,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final baseline = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      painter.paint(
        canvas,
        Offset(text.x - painter.width / 2, text.y - baseline),
      );
      painter.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CarePainter old) =>
      old.kind != kind ||
      old.color != color ||
      old.fontFamily != fontFamily ||
      old.fontFamilyFallback != fontFamilyFallback;
}
