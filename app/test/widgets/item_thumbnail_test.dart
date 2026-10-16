/// Whether a garment can be seen against the tile it is drawn on.
///
/// A cutout is transparent, so what shows behind it decides whether a white
/// shirt or a black one is there at all. The backdrop is measured, not
/// guessed: the garment's stored colour is compared with the plain well, and
/// the well is only moved away from it, by the least that reaches the
/// legibility floor, when the two are too alike. A garment that already shows
/// gets the plain well, so the grid stays one quiet tile colour.
///
/// The failures this guards against are the first version making a charcoal
/// jumper vanish in Dark, and true black bringing it back; so every theme is
/// asked the same questions: does each garment clear the floor, and does one
/// that needs no help get none?
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/widgets/item_thumbnail.dart';

import '../support/contrast.dart';
import '../support/fixtures.dart';

/// A one-pixel PNG. The thumbnail only asks for bytes to hand to the image
/// widget, and a real image keeps the decoder from having an opinion.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

const _black = Color(0xFF000000);

void main() {
  late MemoryImageStore images;

  setUp(() => images = MemoryImageStore());

  /// A garment of [hex], with a cutout to put a backdrop behind.
  Future<WardrobeItem> garment(String hex) async {
    final uri = await images.save(_png, name: 'garment-${hex.substring(1)}');
    final item = confidentItem(id: 'g', name: 'Garment', hex: hex);
    return item.copyWith(
      photos: PhotoSet([
        ItemPhoto(
          uri: uri,
          cutoutUri: uri,
          role: PhotoRole.front,
          capturedAt: DateTime.utc(2026, 1, 1),
        ),
      ]),
    );
  }

  /// What is painted behind [item]'s cutout in [theme]: the backdrop laid over
  /// the screen it sits on, since the lift is translucent and the eye sees the
  /// two together.
  Future<Color> tileSeen(
    WidgetTester tester,
    ThemeData theme,
    WardrobeItem item,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageStoreProvider.overrideWithValue(images)],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(child: ItemThumbnail(item: item, size: 80)),
          ),
        ),
      ),
    );
    // Settled, not just built: the bytes arrive from the store a frame after
    // the first build, and a theme that has replaced another is still fading
    // in. Read halfway through that, a backdrop is a blend of two themes and
    // belongs to neither.
    await tester.pumpAndSettle();

    final backdrop = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(ItemThumbnail),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final tile = (backdrop.decoration as BoxDecoration).color!;
    return Color.alphaBlend(tile, theme.scaffoldBackgroundColor);
  }

  final amoled = AppTheme.amoled();
  final dark = AppTheme.dark();
  final light = AppTheme.light();

  // The code's own floor is 1.6; this is the same bar less a rounding margin.
  const floor = 1.5;

  final themes = {'light': light, 'dark': dark, 'amoled': amoled};
  const garments = {
    'charcoal': '#3C3F44',
    'navy': '#1F2A44',
    'black': '#1B1B1F',
    'white': '#F4F4F2',
    'cream': '#F1E4C8',
  };

  Color rgb(String hex) =>
      Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

  for (final MapEntry(key: themeName, value: theme) in themes.entries) {
    for (final MapEntry(key: name, value: hex) in garments.entries) {
      testWidgets('$name clears the legibility floor in $themeName', (
        tester,
      ) async {
        final item = await garment(hex);

        final seen = contrastBetween(
          rgb(hex),
          await tileSeen(tester, theme, item),
        );

        expect(seen, greaterThanOrEqualTo(floor));
      });
    }

    testWidgets('a garment that already contrasts gets the plain well in '
        '$themeName', (tester) async {
      final well = theme.extension<RinseShape>()!.well;
      // The opposite end from the theme: dark on Light, pale on Dark.
      final hex = identical(theme, light) ? '#3C3F44' : '#F4F4F2';
      final item = await garment(hex);
      expect(contrastBetween(rgb(hex), well), greaterThanOrEqualTo(1.6));

      expect(await tileSeen(tester, theme, item), well);
    });
  }

  test('a hero tile asks for more: charcoal reaches 2.5 on AMOLED', () {
    final shape = amoled.extension<RinseShape>()!;
    final tile = ItemThumbnail.backdropFor(
      garment: rgb('#3C3F44'),
      well: shape.well,
      lighter: amoled.colorScheme.onSurface,
      darker: _black,
      floor: 2.5,
    );
    expect(contrastBetween(rgb('#3C3F44'), tile), greaterThanOrEqualTo(2.4));
  });

  group('how little is added', () {
    testWidgets('a tile moves only as far as the floor needs', (tester) async {
      final well = amoled.extension<RinseShape>()!.well;
      final item = await garment('#1B1B1F');

      final tile = await tileSeen(tester, amoled, item);

      expect(tile, isNot(well));
      // Just over the floor, not a panel.
      expect(
        contrastBetween(rgb('#1B1B1F'), tile),
        lessThan(ItemThumbnail.legibilityFloor + 0.15),
      );
    });

    testWidgets('a dark cutout stays visible on true black', (tester) async {
      final item = await garment('#1B1B1F');

      final tile = await tileSeen(tester, amoled, item);

      expect(contrastBetween(tile, _black), greaterThan(1.3));
    });

    testWidgets('a garment with no stored colour sits on the well', (
      tester,
    ) async {
      final item = (await garment('#3C3F44')).copyWith(
        colors: Confident(
          ColorPalette(const []),
          confidence: 0.9,
          source: Provenance.aiInference,
        ),
      );
      expect(
        await tileSeen(tester, amoled, item),
        amoled.extension<RinseShape>()!.well,
      );
    });
  });
}
