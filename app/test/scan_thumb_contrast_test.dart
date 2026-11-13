/// A cutout has no background of its own, so a dark garment on a dark tile (or
/// a white one on a light tile) must not disappear. Checked in all three
/// appearances, against the theme's own well.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/features/scan/scan_parts.dart';

import 'support/worn_fakes.dart';

void main() {
  final themes = {
    'Light': AppTheme.light(),
    'Dark': AppTheme.dark(),
    'AMOLED': AppTheme.amoled(),
  };

  Future<Color> wellOf(
    WidgetTester tester,
    ThemeData theme,
    int? garmentRgb,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: ScanThumb(image: wornPng, size: 64, garmentRgb: garmentRgb),
        ),
      ),
    );
    return tester
        .widget<ColoredBox>(
          find.descendant(
            of: find.byType(ScanThumb),
            matching: find.byType(ColoredBox),
          ),
        )
        .color;
  }

  double lightness(Color colour) => colour.computeLuminance();

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    group(name, () {
      testWidgets('a garment about as light as the well gets a better ground', (
        tester,
      ) async {
        final plain = theme.extension<RinseShape>()!.well;
        final dark = theme.brightness == Brightness.dark;
        // The garment that is the well's own lightness: black on a dark well,
        // white on a light one.
        final garment = dark ? 0x000000 : 0xFFFFFF;

        final well = await wellOf(tester, theme, garment);

        expect(well, isNot(plain), reason: 'it would have vanished');
        expect(
          (lightness(well) - lightness(Color(0xFF000000 | garment))).abs(),
          greaterThan(
            (lightness(plain) - lightness(Color(0xFF000000 | garment))).abs(),
          ),
          reason: 'and the new ground is further from the garment',
        );
      });

      testWidgets('a garment that already contrasts keeps the plain well', (
        tester,
      ) async {
        final plain = theme.extension<RinseShape>()!.well;
        final dark = theme.brightness == Brightness.dark;

        expect(await wellOf(tester, theme, dark ? 0xFFFFFF : 0x000000), plain);
      });

      testWidgets('a photograph keeps the plain well', (tester) async {
        expect(
          await wellOf(tester, theme, null),
          theme.extension<RinseShape>()!.well,
        );
      });
    });
  }
}
