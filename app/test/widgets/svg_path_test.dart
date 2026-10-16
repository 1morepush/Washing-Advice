import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/widgets/care_symbol.dart';
import 'package:washing_advice/widgets/garment_glyph.dart';
import 'package:washing_advice/widgets/svg_path.dart';

Rect bounds(String d) => parseSvgPath(d).getBounds();

void main() {
  group('parseSvgPath commands', () {
    test('M and L, absolute', () {
      final b = bounds('M10 20 L30 40');
      expect(b, const Rect.fromLTRB(10, 20, 30, 40));
    });

    test('m and l, relative', () {
      // Relative to the previous point, not to the origin.
      final b = bounds('m10 10 l5 5 l5 -2');
      expect(b, const Rect.fromLTRB(10, 10, 20, 15));
    });

    test('H and V, absolute and relative', () {
      expect(bounds('M5 5 H20 V30'), const Rect.fromLTRB(5, 5, 20, 30));
      expect(bounds('M5 5 h10 v10'), const Rect.fromLTRB(5, 5, 15, 15));
      expect(bounds('M5 5 H1'), const Rect.fromLTRB(1, 5, 5, 5));
    });

    test('C absolute reaches its end point', () {
      final p = parseSvgPath('M0 0 C0 10 10 10 10 0');
      final b = p.getBounds();
      expect(b.left, 0);
      expect(b.right, 10);
      expect(b.bottom, greaterThan(5));
    });

    test('c relative equals C absolute', () {
      final a = bounds('M2 3 C2 13 12 13 12 3');
      final r = bounds('M2 3 c0 10 10 10 10 0');
      expect(r, a);
    });

    test('S reflects the previous control point', () {
      // Explicit form of: M0 0 C0 10 10 10 10 0 S20 -10 20 0
      // The reflected first control is (10, -10).
      final s = bounds('M0 0 C0 10 10 10 10 0 S20 -10 20 0');
      final c = bounds('M0 0 C0 10 10 10 10 0 C10 -10 20 -10 20 0');
      expect(s, c);
    });

    test('S with no previous curve uses the current point', () {
      final s = bounds('M0 0 S10 10 20 0');
      final c = bounds('M0 0 C0 0 10 10 20 0');
      expect(s, c);
    });

    test('s relative', () {
      final s = bounds('M0 0 C0 10 10 10 10 0 s10 -10 10 0');
      final c = bounds('M0 0 C0 10 10 10 10 0 C10 -10 20 -10 20 0');
      expect(s, c);
    });

    test('Q and q', () {
      final a = bounds('M0 0 Q10 20 20 0');
      expect(a.left, 0);
      expect(a.right, 20);
      // getBounds is the control hull; the curve itself peaks at half of it.
      expect(a.bottom, 20);
      final m = parseSvgPath('M0 0 Q10 20 20 0').computeMetrics().first;
      expect(
        m.getTangentForOffset(m.length / 2)!.position.dy,
        closeTo(10, 0.01),
      );
      expect(bounds('M0 0 q10 20 20 0'), a);
    });

    test('T reflects the previous quadratic control point', () {
      final t = bounds('M0 0 Q5 10 10 0 T20 0');
      final q = bounds('M0 0 Q5 10 10 0 Q15 -10 20 0');
      expect(t, q);
      expect(bounds('M0 0 Q5 10 10 0 t10 0'), q);
    });

    test('T after a non-quadratic command uses the current point', () {
      final t = bounds('M0 0 L10 0 T20 10');
      final q = bounds('M0 0 L10 0 Q10 0 20 10');
      expect(t, q);
    });

    test('Z closes to the start and relative moves continue from it', () {
      final p = parseSvgPath('M10 10 L20 10 L20 20 Z m5 5 l1 1');
      // After Z the current point is (10,10), so m5 5 lands on (15,15).
      expect(p.getBounds(), const Rect.fromLTRB(10, 10, 20, 20));
      expect(p.contains(const Offset(17, 13)), isTrue);
      expect(
        parseSvgPath('M0 0 L4 0 L4 4 z').contains(const Offset(3, 1)),
        isTrue,
      );
    });

    test('A draws a half circle', () {
      final b = bounds('M0 10 A10 10 0 0 1 20 10');
      expect(b.left, closeTo(0, 0.01));
      expect(b.right, closeTo(20, 0.01));
      // Sweep flag 1 is clockwise, which in SVG y-down space goes over the top.
      expect(b.top, closeTo(0, 0.01));
      expect(b.bottom, closeTo(10, 0.01));
      final down = bounds('M0 10 A10 10 0 0 0 20 10');
      expect(down.top, closeTo(10, 0.01));
      expect(down.bottom, closeTo(20, 0.01));
    });

    test('a relative, and compact flags', () {
      final rel = bounds('M0 10 a10 10 0 0 1 20 0');
      expect(rel.top, closeTo(0, 0.01));
      final compact = bounds('M0 10 a10 10 0 011 0');
      // "011 0" is flags 0,1 then x=1... too small a radius is scaled up; we
      // only need that it parses and ends at x=1.
      expect(compact.right, greaterThanOrEqualTo(1));
    });

    test('a zero radius arc is a straight line', () {
      expect(
        bounds('M0 0 A0 5 0 0 1 10 10'),
        const Rect.fromLTRB(0, 0, 10, 10),
      );
    });

    test('two arcs make a full circle', () {
      final b = bounds(
        'M10.5 20 A9.5 9.5 0 1 0 29.5 20 A9.5 9.5 0 1 0 10.5 20 Z',
      );
      expect(b.left, closeTo(10.5, 0.01));
      expect(b.right, closeTo(29.5, 0.01));
      expect(b.top, closeTo(10.5, 0.01));
      expect(b.bottom, closeTo(29.5, 0.01));
    });
  });

  group('parseSvgPath syntax', () {
    test('implicit repeated L after M', () {
      expect(bounds('M0 0 10 0 10 10'), const Rect.fromLTRB(0, 0, 10, 10));
    });

    test('implicit repeated m is relative l', () {
      expect(bounds('m0 0 10 0 0 10'), const Rect.fromLTRB(0, 0, 10, 10));
    });

    test('implicit repeats of H, C and Q', () {
      expect(bounds('M0 0 H5 10 3'), const Rect.fromLTRB(0, 0, 10, 0));
      expect(
        bounds('M0 0 C0 5 5 5 5 0 5 -5 10 -5 10 0'),
        bounds('M0 0 C0 5 5 5 5 0 C5 -5 10 -5 10 0'),
      );
      expect(
        bounds('M0 0 Q5 5 10 0 15 -5 20 0'),
        bounds('M0 0 Q5 5 10 0 Q15 -5 20 0'),
      );
    });

    test('numbers: leading dot, exponents, signs, packed', () {
      expect(bounds('M.5 .5 L1.5 2.5'), const Rect.fromLTRB(.5, .5, 1.5, 2.5));
      expect(bounds('M0 0 L-1.2e1 1e1'), const Rect.fromLTRB(-12, 0, 0, 10));
      expect(bounds('M0 0 L1E1 +5'), const Rect.fromLTRB(0, 0, 10, 5));
      // "1.5.5" is 1.5 then .5; "3-4" is 3 then -4.
      expect(bounds('M1.5.5L3-4'), const Rect.fromLTRB(1.5, -4, 3, .5));
    });

    test('separators: commas, newlines, none', () {
      expect(bounds('M1,2\nL3,\t4'), const Rect.fromLTRB(1, 2, 3, 4));
      expect(bounds('M1 2L3 4'), const Rect.fromLTRB(1, 2, 3, 4));
      expect(bounds('  M1 2   L3 4  '), const Rect.fromLTRB(1, 2, 3, 4));
    });

    test('empty data is an empty path', () {
      expect(parseSvgPath(''), isA<Path>());
      expect(parseSvgPath('   ').getBounds(), Rect.zero);
    });

    test('malformed data throws FormatException', () {
      expect(() => parseSvgPath('L1 1'), throwsFormatException);
      expect(() => parseSvgPath('1 1'), throwsFormatException);
      expect(() => parseSvgPath('M1'), throwsFormatException);
      expect(() => parseSvgPath('M1 2 X3 4'), throwsFormatException);
      expect(() => parseSvgPath('M1 2 L3'), throwsFormatException);
      expect(() => parseSvgPath('M1 2 Z 3'), throwsFormatException);
      expect(() => parseSvgPath('M0 0 A1 1 0 2 0 5 5'), throwsFormatException);
      expect(() => parseSvgPath('M0 0 L1e 1'), throwsFormatException);
    });
  });

  group('the proposal art', () {
    test('every garment path parses and sits inside the 64 grid', () {
      for (final entry in garmentArt.entries) {
        final all = [entry.value.body, ...entry.value.details];
        for (final d in all) {
          final b = parseSvgPath(d).getBounds();
          expect(
            b.width + b.height,
            greaterThan(0),
            reason: '${entry.key}: $d',
          );
          expect(b.left, greaterThanOrEqualTo(0), reason: '${entry.key}');
          expect(b.top, greaterThanOrEqualTo(0), reason: '${entry.key}');
          expect(b.right, lessThanOrEqualTo(garmentViewBox));
          expect(b.bottom, lessThanOrEqualTo(garmentViewBox));
        }
      }
    });

    test('there is art for every glyph kind', () {
      expect(garmentArt.keys.toSet(), GlyphKind.values.toSet());
    });

    test('every care path parses and sits inside the 40 grid', () {
      for (final entry in careArt.entries) {
        final art = entry.value;
        expect(art.strokes, isNotEmpty);
        for (final d in [...art.strokes, ...art.fills]) {
          final b = parseSvgPath(d).getBounds();
          expect(
            b.width + b.height,
            greaterThan(0),
            reason: '${entry.key}: $d',
          );
          expect(b.left, greaterThanOrEqualTo(0), reason: '${entry.key}');
          expect(b.top, greaterThanOrEqualTo(0), reason: '${entry.key}');
          expect(b.right, lessThanOrEqualTo(careViewBox));
          expect(b.bottom, lessThanOrEqualTo(careViewBox));
        }
        final t = art.text;
        if (t != null) {
          expect(t.x, inInclusiveRange(0, careViewBox));
          expect(t.y, inInclusiveRange(0, careViewBox));
        }
      }
      expect(careArt.keys.toSet(), CareSymbolKind.values.toSet());
    });
  });
}
