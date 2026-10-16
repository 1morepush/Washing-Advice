/// What the Rinse look adds to the wardrobe and the garment's page.
///
///  * a garment with no photograph is drawn as its own silhouette, in its own
///    colour, rather than as a colour disc that six different things share;
///  * the last row of the grid and of the list scrolls clear of the floating
///    "Add" button, on a roomy phone and on the narrowest one;
///  * the care symbols appear on the garment's page beside the words.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/wardrobe/item_detail_screen.dart';
import 'package:washing_advice/features/wardrobe/wardrobe_screen.dart';
import 'package:washing_advice/features/wardrobe/widgets/item_card.dart';
import 'package:washing_advice/features/wardrobe/widgets/item_tile.dart';
import 'package:washing_advice/widgets/care_symbol.dart';
import 'package:washing_advice/widgets/garment_glyph.dart';
import 'package:washing_advice/widgets/item_thumbnail.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;

  setUp(() => repository = InMemoryWardrobeRepository());

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(420, 900),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
        ],
        child: MaterialApp(theme: theme, home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a garment with no photograph', () {
    testWidgets('is its own silhouette in its own colour', (tester) async {
      final shorts = confidentItem(
        id: 'a',
        name: 'Gray shorts',
        type: ItemType.shorts,
        hex: '#8A8A8A',
      );
      final socks = confidentItem(
        id: 'b',
        name: 'Black socks',
        type: ItemType.socks,
        hex: '#101010',
      );
      await pumpScreen(
        tester,
        Scaffold(
          body: Row(
            children: [
              ItemThumbnail(item: shorts, size: 80),
              ItemThumbnail(item: socks, size: 80),
            ],
          ),
        ),
      );

      final glyphs = tester
          .widgetList<GarmentGlyph>(find.byType(GarmentGlyph))
          .toList();
      expect(glyphs.map((g) => g.kind), [GlyphKind.shorts, GlyphKind.socks]);
      expect(glyphs[0].fill, const Color(0xFF8A8A8A));
      expect(glyphs[1].fill, const Color(0xFF101010));
    });

    for (final (name, app) in [
      ('Light', AppTheme.light()),
      ('Dark', AppTheme.dark()),
      ('AMOLED', AppTheme.amoled()),
    ]) {
      testWidgets('is outlined with the garment edge in $name', (tester) async {
        final socks = confidentItem(
          id: 'b',
          name: 'Black socks',
          type: ItemType.socks,
          hex: '#101010',
        );
        await pumpScreen(
          tester,
          Scaffold(body: ItemThumbnail(item: socks, size: 80)),
          theme: app,
        );

        final glyph = tester.widget<GarmentGlyph>(find.byType(GarmentGlyph));
        expect(glyph.edge, app.extension<RinseShape>()!.garmentEdge);
        expect(glyph.edge.a, greaterThan(0));
      });
    }

    testWidgets('with no colour recorded still draws something', (
      tester,
    ) async {
      final base = confidentItem(
        id: 'c',
        name: 'Mystery',
        type: ItemType.tShirt,
      );
      final item = base.copyWith(
        colors: Confident(
          ColorPalette(const []),
          confidence: 0.1,
          source: Provenance.aiInference,
        ),
      );
      await pumpScreen(
        tester,
        Scaffold(body: ItemThumbnail(item: item, size: 80)),
      );

      expect(find.byType(GarmentGlyph), findsOneWidget);
    });
  });

  group('the last row clears the floating button', () {
    /// Enough garments that the wardrobe has to scroll on a phone.
    Future<void> stock({int count = 40}) => repository.saveAll([
      for (var i = 0; i < count; i++)
        confidentItem(
          id: 'item-$i',
          name: 'Garment ${i.toString().padLeft(2, '0')}',
          // Distinct, so the duplicate grouping leaves each in its own row.
          hex: '#${(0x100000 + i * 0x2371).toRadixString(16).padLeft(6, '0')}',
        ),
    ]);

    for (final size in [const Size(420, 900), const Size(320, 640)]) {
      for (final grid in [true, false]) {
        testWidgets('in the ${grid ? 'grid' : 'list'} at ${size.width.toInt()}x'
            '${size.height.toInt()}', (tester) async {
          await stock();
          await pumpScreen(tester, const WardrobeScreen(), size: size);
          if (!grid) {
            await tester.tap(find.byTooltip('Show as a list'));
            await tester.pumpAndSettle();
          }

          await tester.drag(
            find
                .byWidgetPredicate(
                  (w) => w is Scrollable && w.axis == Axis.vertical,
                )
                .last,
            const Offset(0, -100000),
          );
          await tester.pumpAndSettle();

          final button = tester.getRect(find.byType(FloatingActionButton));
          // The last tile or row, name, type and all: built in order, so the
          // last one in the tree is the last one in the wardrobe.
          final cells = grid ? find.byType(ItemCard) : find.byType(ItemTile);
          expect(cells, findsWidgets);
          final lastBottom = tester
              .getRect(find.byWidget(cells.evaluate().last.widget))
              .bottom;
          // Fully above the button, not merely beside it.
          expect(
            lastBottom,
            lessThanOrEqualTo(button.top),
            reason: 'the last garment is still under the Add button',
          );
        });
      }
    }
  });

  group('the garment page', () {
    testWidgets('shows care symbols alongside the words', (tester) async {
      await repository.save(
        confidentItem(id: 'tee', name: 'White cotton tee', hex: '#F3F2EC'),
      );
      await pumpScreen(tester, const ItemDetailScreen(id: ItemId('tee')));

      await tester.scrollUntilVisible(
        find.text('How to wash it'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.byType(CareSymbol), findsWidgets);
      // The words stay: the symbols are an addition, never the only source.
      expect(find.text('Wash'), findsOneWidget);
      expect(find.text('Bleach'), findsOneWidget);
    });

    testWidgets('draws the garment large even without a photograph', (
      tester,
    ) async {
      await repository.save(
        confidentItem(id: 'tee', name: 'White cotton tee', hex: '#F3F2EC'),
      );
      await pumpScreen(tester, const ItemDetailScreen(id: ItemId('tee')));

      expect(find.byType(GarmentGlyph), findsOneWidget);
    });
  });
}
