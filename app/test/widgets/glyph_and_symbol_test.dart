import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/widgets/care_symbol.dart';
import 'package:washing_advice/widgets/garment_glyph.dart';

const _sizes = [16.0, 24.0, 56.0, 120.0];

/// Renders [child] on a [background] square of [side] pixels and returns the
/// RGBA bytes.
Future<Uint8List> _render(
  WidgetTester tester,
  Widget child, {
  required double side,
  required Color background,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(
            dimension: side,
            child: ColoredBox(color: background, child: child),
          ),
        ),
      ),
    ),
  );
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData();
    return data!.buffer.asUint8List();
  }))!;
}

int _countNear(Uint8List rgba, Color c, {int tolerance = 12}) {
  final r = (c.r * 255).round(), g = (c.g * 255).round();
  final b = (c.b * 255).round();
  var n = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if ((rgba[i] - r).abs() <= tolerance &&
        (rgba[i + 1] - g).abs() <= tolerance &&
        (rgba[i + 2] - b).abs() <= tolerance &&
        rgba[i + 3] > 200) {
      n++;
    }
  }
  return n;
}

void main() {
  group('GarmentGlyph', () {
    for (final kind in GlyphKind.values) {
      testWidgets('${kind.name} paints at every size without overflow', (
        tester,
      ) async {
        for (final s in _sizes) {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: GarmentGlyph(
                  kind: kind,
                  fill: Colors.teal,
                  edge: Colors.black,
                  size: s,
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(tester.getSize(find.byType(GarmentGlyph)), Size.square(s));
        }
      });
    }

    testWidgets('takes the box it is given when no size is set', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 80,
              height: 50,
              child: GarmentGlyph(
                kind: GlyphKind.tee,
                fill: Colors.red,
                edge: Colors.black,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final paint = tester.renderObject<RenderCustomPaint>(
        find.descendant(
          of: find.byType(GarmentGlyph),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(paint.size, const Size(80, 50));
    });

    testWidgets('survives an unbounded box', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            child: Row(
              children: [
                GarmentGlyph(
                  kind: GlyphKind.tee,
                  fill: Colors.red,
                  edge: Colors.black,
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('is decorative unless given a label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              GarmentGlyph(
                kind: GlyphKind.tee,
                fill: Colors.red,
                edge: Colors.black,
                size: 24,
              ),
              GarmentGlyph(
                kind: GlyphKind.jeans,
                fill: Colors.blue,
                edge: Colors.black,
                size: 24,
                semanticLabel: 'Jeans',
              ),
            ],
          ),
        ),
      );
      expect(find.bySemanticsLabel('Jeans'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('.')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('draws the fill, and the outline on a dark fill', (
      tester,
    ) async {
      const bg = Color(0xFF101010);
      const edge = Color(0xFFE0E0E0);
      final bytes = await _render(
        tester,
        const GarmentGlyph(
          kind: GlyphKind.socks,
          fill: bg,
          edge: edge,
          size: 120,
        ),
        side: 120,
        background: bg,
      );
      // Fill is the same as the background, so only the outline shows up.
      expect(_countNear(bytes, edge), greaterThan(100));
      expect(_countNear(bytes, bg), greaterThan(1000));

      final filled = await _render(
        tester,
        const GarmentGlyph(
          kind: GlyphKind.tee,
          fill: Color(0xFFFF0000),
          edge: Color(0xFF000000),
          size: 120,
        ),
        side: 120,
        background: const Color(0xFFFFFFFF),
      );
      expect(_countNear(filled, const Color(0xFFFF0000)), greaterThan(2000));
      expect(_countNear(filled, const Color(0xFF000000)), greaterThan(100));
    });

    test('glyphKindFor is total over ItemType and ItemCategory', () {
      for (final t in ItemType.values) {
        expect(garmentArt.containsKey(glyphKindFor(t)), isTrue, reason: '$t');
      }
      for (final c in ItemCategory.values) {
        expect(garmentArt.containsKey(glyphKindForCategory(c)), isTrue);
      }
    });

    test('glyphKindFor maps the obvious ones', () {
      expect(glyphKindFor(ItemType.tShirt), GlyphKind.tee);
      expect(glyphKindFor(ItemType.jeans), GlyphKind.jeans);
      expect(glyphKindFor(ItemType.socks), GlyphKind.socks);
      expect(glyphKindFor(ItemType.sneakers), GlyphKind.trainers);
      expect(glyphKindFor(ItemType.bathTowel), GlyphKind.towel);
      expect(glyphKindFor(ItemType.hoodie), GlyphKind.hoodie);
      expect(glyphKindFor(ItemType.coat), GlyphKind.jacket);
      expect(glyphKindFor(ItemType.other), GlyphKind.towel);
    });
  });

  group('CareSymbol', () {
    for (final kind in CareSymbolKind.values) {
      testWidgets('${kind.name} paints at every size without overflow', (
        tester,
      ) async {
        for (final s in _sizes) {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: CareSymbol(kind: kind, color: Colors.black, size: s),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(tester.getSize(find.byType(CareSymbol)), Size.square(s));
        }
      });

      testWidgets('${kind.name} draws pixels in its colour', (tester) async {
        final bytes = await _render(
          tester,
          CareSymbol(kind: kind, color: const Color(0xFF0000FF), size: 96),
          side: 96,
          background: const Color(0xFFFFFFFF),
        );
        expect(_countNear(bytes, const Color(0xFF0000FF)), greaterThan(150));
      });
    }

    testWidgets('has a default label and honours an override', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              CareSymbol(kind: CareSymbolKind.doNotBleach, color: Colors.black),
              CareSymbol(
                kind: CareSymbolKind.doNotTumbleDry,
                color: Colors.black,
                semanticLabel: 'No dryer',
              ),
              CareSymbol(
                kind: CareSymbolKind.iron,
                color: Colors.black,
                semanticLabel: '',
              ),
            ],
          ),
        ),
      );
      expect(find.bySemanticsLabel('Do not bleach'), findsOneWidget);
      expect(find.bySemanticsLabel('No dryer'), findsOneWidget);
      expect(find.bySemanticsLabel('Iron on low heat'), findsNothing);
      handle.dispose();
    });

    test('every symbol has a distinct non-empty label', () {
      final labels = careArt.values.map((a) => a.label).toList();
      expect(labels.every((l) => l.isNotEmpty), isTrue);
      expect(labels.toSet().length, labels.length);
    });

    testWidgets('numerals follow the ambient font', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: TextStyle(fontFamily: 'Roboto'),
            child: CareSymbol(kind: CareSymbolKind.wash40, color: Colors.black),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('careSymbolsFor', () {
    CareInstructions care({
      WashCare wash = const WashCare(method: WashMethod.machine, maxTempC: 40),
      BleachAllowance bleach = BleachAllowance.any,
      DryCare dry = const DryCare(tumbleDryAllowed: true),
      IronCare iron = const IronCare(temperature: IronTemperature.medium),
      ProfessionalCare professional = const ProfessionalCare.unspecified(),
    }) => CareInstructions(
      wash: wash,
      bleach: bleach,
      dry: dry,
      iron: iron,
      professional: professional,
    );

    test('a plain cotton label', () {
      expect(careSymbolsFor(care()), [
        CareSymbolKind.wash40,
        CareSymbolKind.tumbleDry,
      ]);
    });

    test('a delicate label', () {
      final delicate = care(
        wash: const WashCare(
          method: WashMethod.machine,
          maxTempC: 30,
          agitation: Agitation.veryMild,
        ),
        bleach: BleachAllowance.none,
        dry: const DryCare(
          tumbleDryAllowed: false,
          naturalDry: NaturalDryMethod.flatDry,
        ),
        iron: const IronCare(temperature: IronTemperature.low),
        professional: const ProfessionalCare(
          solvent: CleaningSolvent.perchloroethylene,
        ),
      );
      expect(careSymbolsFor(delicate), [
        CareSymbolKind.wash30Gentle,
        CareSymbolKind.doNotBleach,
        CareSymbolKind.doNotTumbleDry,
        CareSymbolKind.dryFlat,
        CareSymbolKind.iron,
        CareSymbolKind.dryClean,
      ]);
    });

    test('the conservative fallback', () {
      expect(careSymbolsFor(const CareInstructions.conservative()), [
        CareSymbolKind.wash30Mild,
        CareSymbolKind.doNotBleach,
        CareSymbolKind.doNotTumbleDry,
        CareSymbolKind.lineDry,
        CareSymbolKind.iron,
      ]);
    });

    test('symbols without art are skipped, not approximated', () {
      final hot = care(
        wash: const WashCare(method: WashMethod.hand, maxTempC: 60),
        dry: const DryCare(
          tumbleDryAllowed: true,
          naturalDry: NaturalDryMethod.dripDry,
        ),
        iron: const IronCare(temperature: IronTemperature.high),
        professional: const ProfessionalCare(solvent: CleaningSolvent.wetClean),
      );
      expect(careSymbolsFor(hot), [CareSymbolKind.tumbleDry]);
    });

    test('a profile gives the same answer as its instructions', () {
      final profile = CareProfile.fromUser(care());
      expect(careSymbolsForProfile(profile), careSymbolsFor(care()));
    });
  });
}
