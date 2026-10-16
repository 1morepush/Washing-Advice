/// The bottom bar's words stay whole at the largest text sizes.
///
/// At 1.8x on a 320 dp phone "Wardrobe" broke into "Wardro" and "be". The bar
/// now stops growing its labels early; this holds that line with the real
/// typeface, because the test font draws every glyph a full em wide and would
/// break any word.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/main.dart';

import '../support/fixtures.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader(rinseFontFamily);
    for (final file in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
      loader.addFont(rootBundle.load('assets/fonts/Nunito-$file.ttf'));
    }
    await loader.load();
  });

  for (final scale in [1.0, 1.8, 2.0, 3.0]) {
    testWidgets('every label is one line on 320 dp at ${scale}x text', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final repository = InMemoryWardrobeRepository();
      await repository.save(confidentItem(id: 'a', name: 'Blue jumper'));
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(
            SettingsStore(await SharedPreferences.getInstance()),
          ),
          wardrobeRepositoryProvider.overrideWithValue(repository),
          outfitRepositoryProvider.overrideWithValue(
            InMemoryOutfitRepository(),
          ),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
        ],
      );
      addTearDown(container.dispose);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const WashingAdviceApp(initialLocation: '/'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final label in ['Wardrobe', 'Laundry', 'Outfits', 'Ask', 'More']) {
        final text = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        );
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(
          // One selection box per line of text.
          paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: label.length),
          ),
          hasLength(1),
          reason: '"$label" wrapped',
        );
        expect(paragraph.didExceedMaxLines, isFalse);
      }
      // The bar keeps its height and its 48 dp targets.
      final bar = tester.getRect(find.byType(NavigationBar));
      expect(bar.height, lessThanOrEqualTo(68 + 34));
      for (final destination in tester.widgetList<NavigationDestination>(
        find.byType(NavigationDestination),
      )) {
        final box = tester.getRect(find.byWidget(destination));
        expect(box.height, greaterThanOrEqualTo(48));
        expect(box.width, greaterThanOrEqualTo(48));
      }
    });
  }
}
