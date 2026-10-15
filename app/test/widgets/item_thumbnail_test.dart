/// Whether a garment can be seen against the tile it is drawn on.
///
/// A cutout is transparent, so what shows behind it decides whether a white
/// shirt or a black one is there at all. The backdrop is chosen from the
/// garment's colour class and the theme's brightness, and the first version
/// of it made a charcoal jumper disappear in dark mode — which is the failure
/// this file exists to stop coming back in a new theme.
///
/// True black brought it back once already, from a different direction: the
/// dark backdrop is a fraction of the text colour laid over whatever is behind
/// it, and over black that fraction lands on charcoal. So the question asked of
/// every theme here is the same one: how well does this garment show against
/// the tile, and is that as well as it did in Dark?
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

  group('on true black', () {
    // Charcoal is the demo wardrobe's jumper; the other two are the ends of
    // what the darks pile holds, a black sock and a navy hoodie.
    for (final (name, hex) in [
      ('a charcoal jumper', '#3C3F44'),
      ('a black sock', '#1B1B1F'),
      ('a navy hoodie', '#1F2A44'),
    ]) {
      testWidgets('$name shows against its backdrop as well as in Dark', (
        tester,
      ) async {
        final item = await garment(hex);
        final colour = Color(
          0xFF000000 | int.parse(hex.substring(1), radix: 16),
        );

        final onBlack = contrastBetween(
          colour,
          await tileSeen(tester, amoled, item),
        );
        final inDark = contrastBetween(
          colour,
          await tileSeen(tester, dark, item),
        );

        // A reference rather than a number, so this says what it means: the
        // garment must not be harder to see because the theme got darker.
        expect(onBlack, greaterThanOrEqualTo(inDark));
      });
    }

    testWidgets('the charcoal jumper is not lost against the black', (
      tester,
    ) async {
      // The same check as above with the bar written out, so a failure reads
      // as what it is. The first version of the darks backdrop landed at about
      // 1.09 here — the jumper was there and could not be seen.
      final item = await garment('#3C3F44');

      final seen = contrastBetween(
        const Color(0xFF3C3F44),
        await tileSeen(tester, amoled, item),
      );

      expect(seen, greaterThan(1.3));
    });

    testWidgets('a backdrop is clearly distinct from the black around it', (
      tester,
    ) async {
      final item = await garment('#3C3F44');

      final tile = await tileSeen(tester, amoled, item);

      expect(contrastBetween(tile, _black), greaterThan(2));
    });

    testWidgets('a white shirt sits a shade above black, not on a panel', (
      tester,
    ) async {
      // Whites and lights are drawn on the lightest container. It has to show
      // — a tile the colour of the ground is no tile — and it has to stay the
      // near-black the theme promises, or white tees get grey boxes.
      final item = await garment('#F4F4F2');

      final tile = await tileSeen(tester, amoled, item);

      expect(tile, isNot(_black));
      expect(tile, amoled.colorScheme.surfaceContainerHighest);
      expect(contrastBetween(tile, _black), greaterThanOrEqualTo(1.2));
      expect(
        tile.computeLuminance(),
        lessThan(dark.colorScheme.surfaceContainerHighest.computeLuminance()),
      );
    });

    testWidgets('and the shirt itself shows well against it', (tester) async {
      final item = await garment('#F4F4F2');

      final tile = await tileSeen(tester, amoled, item);

      expect(contrastBetween(const Color(0xFFF4F4F2), tile), greaterThan(10));
    });
  });

  group('in dark, where it has always been', () {
    testWidgets('a darks backdrop is still 30% of the text colour', (
      tester,
    ) async {
      // The true-black adjustment must not leak into the ordinary dark theme,
      // which looks as it did before there was a third.
      final item = await garment('#3C3F44');

      final seen = await tileSeen(tester, dark, item);

      expect(
        seen,
        Color.alphaBlend(
          dark.colorScheme.onSurface.withValues(alpha: 0.30),
          dark.scaffoldBackgroundColor,
        ),
      );
    });
  });
}
