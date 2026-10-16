import 'package:flutter/widgets.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'svg_path.dart';

/// The silhouettes there is art for.
enum GlyphKind {
  tee,
  shirt,
  blouse,
  sweater,
  hoodie,
  jacket,
  jeans,
  shorts,
  socks,
  towel,
  trainers,
}

/// The drawing of one glyph, as SVG path data on a [garmentViewBox] grid.
class GarmentArt {
  const GarmentArt({required this.body, this.details = const []});

  /// The filled silhouette, which also takes the outline.
  final String body;

  /// Seams, collars, pockets and the like: strokes with no fill.
  final List<String> details;
}

/// Side of the square grid [garmentArt] is drawn on.
const double garmentViewBox = 64;

/// Outline width on [garmentViewBox] units, for the body.
const double _bodyEdgeWidth = 1.3;

/// Stroke width on [garmentViewBox] units, for the details.
const double _detailWidth = 1.4;

/// The art, hand-ported from the design proposal.
const Map<GlyphKind, GarmentArt> garmentArt = {
  GlyphKind.tee: GarmentArt(
    body:
        'M23 9 L16 11.5 L6 20 L12 29 L18 25.5 L18 56 L46 56 L46 25.5 '
        'L52 29 L58 20 L48 11.5 L41 9 Q32 17 23 9 Z',
  ),
  GlyphKind.shirt: GarmentArt(
    body:
        'M24 8 L16 11 L8 18 L5 46 L12 47 L17 26 L17 57 L47 57 L47 26 '
        'L52 47 L59 46 L56 18 L48 11 L40 8 L32 16 Z',
    details: ['M24 8 L32 16 L40 8 M32 16 V57'],
  ),
  GlyphKind.blouse: GarmentArt(
    body:
        'M25 9 L17 12 L9 19 L6 44 L13 45 L18 26 L18 57 L46 57 L46 26 '
        'L51 45 L58 44 L55 19 L47 12 L39 9 Q32 23 25 9 Z',
  ),
  GlyphKind.sweater: GarmentArt(
    body:
        'M24 9 Q32 14 40 9 L50 12 L57 20 L60 47 L52 49 L47 27 L47 55 '
        'Q47 57 45 57 L19 57 Q17 57 17 55 L17 27 L12 49 L4 47 L7 20 L14 12 Z',
    details: ['M17 52 H47 M5 44 L12 45.5 M59 44 L52 45.5'],
  ),
  GlyphKind.hoodie: GarmentArt(
    body:
        'M23 13 Q22 3 32 3 Q42 3 41 13 L50 15 L57 22 L60 48 L52 50 L47 28 '
        'L47 57 L17 57 L17 28 L12 50 L4 48 L7 22 L14 15 Z',
    details: ['M26 13 Q32 20 38 13 M23 43 H41 L39 51 H25 Z'],
  ),
  GlyphKind.jacket: GarmentArt(
    body:
        'M24 8 L15 11 L8 18 L5 50 L12 51 L17 27 L17 58 L47 58 L47 27 '
        'L52 51 L59 50 L56 18 L49 11 L40 8 L32 14 Z',
    details: [
      'M32 14 V58 M24 8 L28 18 L32 14 L36 18 L40 8 M21 40 H27 M37 40 H43',
    ],
  ),
  GlyphKind.jeans: GarmentArt(
    body: 'M17 6 H47 L49 58 H36 L32 24 L28 58 H15 Z',
    details: ['M17 11.5 H47 M22 11.5 Q22 18 17.5 19 M42 11.5 Q42 18 46.5 19'],
  ),
  GlyphKind.shorts: GarmentArt(
    body: 'M15 14 H49 L52 46 L35 48 L32 30 L29 48 L12 46 Z',
    details: ['M15 19 H49'],
  ),
  GlyphKind.socks: GarmentArt(
    body:
        'M24 6 H38 V36 L50 44 Q57 49 52 55 Q48 60 40 55 L27 47 Q24 45 24 41 Z',
    details: ['M24 12 H38'],
  ),
  GlyphKind.towel: GarmentArt(
    body: 'M13 8 H51 V56 H13 Z',
    details: ['M13 43 H51 M13 48 H51'],
  ),
  GlyphKind.trainers: GarmentArt(
    body:
        'M6 42 Q7 31 17 31 L27 27 Q31 36 42 37 L55 41 Q59 44 57 48 H9 '
        'Q5 47 6 42 Z',
    details: ['M7 45.5 H57.5 M24 31 L27 35 M28 30 L31 34'],
  ),
};

/// The glyph that best stands for an item type.
///
/// There are eleven silhouettes and over fifty types, so most types borrow
/// the nearest shape. Where nothing is near (a hat, a bag, a belt) the plain
/// cloth rectangle is used rather than a misleading garment. The `switch` has
/// no default so that adding an [ItemType] forces a decision here.
GlyphKind glyphKindFor(ItemType type) => switch (type) {
  ItemType.tShirt => GlyphKind.tee,
  ItemType.tankTop => GlyphKind.tee,
  ItemType.activewearTop => GlyphKind.tee,
  ItemType.bra => GlyphKind.tee,
  ItemType.longSleeveShirt => GlyphKind.shirt,
  ItemType.dressShirt => GlyphKind.shirt,
  ItemType.poloShirt => GlyphKind.shirt,
  ItemType.pajamas => GlyphKind.shirt,
  ItemType.blouse => GlyphKind.blouse,
  ItemType.dress => GlyphKind.blouse,
  ItemType.jumpsuit => GlyphKind.blouse,
  ItemType.sweater => GlyphKind.sweater,
  ItemType.cardigan => GlyphKind.sweater,
  ItemType.sweatshirt => GlyphKind.sweater,
  ItemType.hoodie => GlyphKind.hoodie,
  ItemType.jacket => GlyphKind.jacket,
  ItemType.blazer => GlyphKind.jacket,
  ItemType.coat => GlyphKind.jacket,
  ItemType.vest => GlyphKind.jacket,
  ItemType.robe => GlyphKind.jacket,
  ItemType.jeans => GlyphKind.jeans,
  ItemType.trousers => GlyphKind.jeans,
  ItemType.chinos => GlyphKind.jeans,
  ItemType.leggings => GlyphKind.jeans,
  ItemType.shorts => GlyphKind.shorts,
  ItemType.skirt => GlyphKind.shorts,
  ItemType.underwear => GlyphKind.shorts,
  ItemType.activewearBottom => GlyphKind.shorts,
  ItemType.swimwear => GlyphKind.shorts,
  ItemType.socks => GlyphKind.socks,
  ItemType.tights => GlyphKind.socks,
  ItemType.gloves => GlyphKind.socks,
  ItemType.sneakers => GlyphKind.trainers,
  ItemType.boots => GlyphKind.trainers,
  ItemType.dressShoes => GlyphKind.trainers,
  ItemType.sandals => GlyphKind.trainers,
  ItemType.handTowel => GlyphKind.towel,
  ItemType.bathTowel => GlyphKind.towel,
  ItemType.bedSheet => GlyphKind.towel,
  ItemType.pillowcase => GlyphKind.towel,
  ItemType.duvetCover => GlyphKind.towel,
  ItemType.blanket => GlyphKind.towel,
  ItemType.scarf => GlyphKind.towel,
  ItemType.hat => GlyphKind.towel,
  ItemType.belt => GlyphKind.towel,
  ItemType.tie => GlyphKind.towel,
  ItemType.handbag => GlyphKind.towel,
  ItemType.backpack => GlyphKind.towel,
  ItemType.other => GlyphKind.towel,
};

/// The glyph for a whole category, for when only the category is known.
GlyphKind glyphKindForCategory(ItemCategory category) => switch (category) {
  ItemCategory.top => GlyphKind.tee,
  ItemCategory.bottom => GlyphKind.jeans,
  ItemCategory.outerwear => GlyphKind.jacket,
  ItemCategory.fullBody => GlyphKind.blouse,
  ItemCategory.underwear => GlyphKind.shorts,
  ItemCategory.legwear => GlyphKind.socks,
  ItemCategory.sleepwear => GlyphKind.shirt,
  ItemCategory.activewear => GlyphKind.tee,
  ItemCategory.swimwear => GlyphKind.shorts,
  ItemCategory.footwear => GlyphKind.trainers,
  ItemCategory.accessory => GlyphKind.towel,
  ItemCategory.household => GlyphKind.towel,
};

/// A flat drawing of a garment: a [fill] silhouette with an [edge] outline and
/// detail strokes, so a black sock stays visible on a dark tile.
///
/// Decorative by default and so hidden from accessibility; pass
/// [semanticLabel] when the glyph is the only thing saying what the item is.
/// With no [size] it fills the shorter side of whatever box it is given
/// (48 when that box is unbounded). The drawing is square and centred.
class GarmentGlyph extends StatelessWidget {
  const GarmentGlyph({
    super.key,
    required this.kind,
    required this.fill,
    required this.edge,
    this.size,
    this.semanticLabel,
  });

  final GlyphKind kind;
  final Color fill;
  final Color edge;
  final double? size;
  final String? semanticLabel;

  static const double _unboundedFallback = 48;

  @override
  Widget build(BuildContext context) {
    final painter = _GlyphPainter(kind: kind, fill: fill, edge: edge);
    Widget child;
    if (size != null) {
      child = CustomPaint(size: Size.square(size!), painter: painter);
    } else {
      child = LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth, h = constraints.maxHeight;
          final side = (w.isFinite && h.isFinite)
              ? (w < h ? w : h)
              : (w.isFinite ? w : (h.isFinite ? h : _unboundedFallback));
          return CustomPaint(size: Size.square(side), painter: painter);
        },
      );
    }
    if (semanticLabel == null) return ExcludeSemantics(child: child);
    return Semantics(label: semanticLabel, image: true, child: child);
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.kind, required this.fill, required this.edge});

  final GlyphKind kind;
  final Color fill;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (side <= 0) return;
    final art = garmentArt[kind]!;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / garmentViewBox);

    final body = cachedSvgPath(art.body);
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fill
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _bodyEdgeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = edge
        ..isAntiAlias = true,
    );
    final detail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _detailWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = edge
      ..isAntiAlias = true;
    for (final d in art.details) {
      canvas.drawPath(cachedSvgPath(d), detail);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.kind != kind || old.fill != fill || old.edge != edge;
}
