/// Laundry at large text: nothing loses a letter.
///
/// At 1.6x the three stage pills used to read "Baske…", "Wash…" and "Dryin…",
/// their counts gone, and the load card's label column broke "Temperature"
/// into "Temperat" and "ure". A name cut in half is worse than a name that
/// needs a scroll, so these pin the words whole across widths and text sizes.
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
import 'package:washing_advice/core/theme.dart' show rinseFontFamily;
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/main.dart';
import 'package:washing_advice/widgets/rinse_kit.dart';

import '../support/fixtures.dart';

void main() {
  late ProviderContainer container;

  // The real typeface: the test font draws every glyph a full em wide, which
  // would break any word on a phone and say nothing about the app.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader(rinseFontFamily);
    for (final file in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
      loader.addFont(rootBundle.load('assets/fonts/Nunito-$file.ttf'));
    }
    await loader.load();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final repository = InMemoryWardrobeRepository();
    await repository.save(
      confidentItem(
        id: 'b',
        name: 'Basket shirt',
      ).copyWith(lifecycle: LifecycleState.inLaundry),
    );
    container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(
          SettingsStore(await SharedPreferences.getInstance()),
        ),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        outfitRepositoryProvider.overrideWithValue(InMemoryOutfitRepository()),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> open(WidgetTester tester, double width, double scale) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WashingAdviceApp(initialLocation: '/laundry'),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Whether [finder]'s paragraph kept every character on screen and did not
  /// break inside a word: it is at least as wide as the widest word in it.
  void expectWhole(WidgetTester tester, Finder finder) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    expect(paragraph.didExceedMaxLines, isFalse);
    for (final word in paragraph.text.toPlainText().split(' ')) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: paragraph.text.style),
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout();
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(painter.width - 0.5),
        reason: '"$word" was broken or cut',
      );
      painter.dispose();
    }
  }

  for (final width in [320.0, 420.0]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('the stage pills keep their words whole at ${width}dp, '
          '${scale}x', (tester) async {
        await open(tester, width, scale);

        expect(tester.takeException(), isNull);
        for (final name in ['Basket', 'Washing', 'Drying']) {
          final label = find.descendant(
            of: find.byType(StagePill),
            matching: find.textContaining(name),
          );
          expect(label, findsOneWidget, reason: name);
          if (scale > 1.3) expectWhole(tester, label);
        }
        // The count rides with the name, never dropped for room.
        expect(find.text('Basket 1'), findsOneWidget);
      });

      testWidgets('the load card names "Temperature" whole at ${width}dp, '
          '${scale}x', (tester) async {
        await open(tester, width, scale);

        await tester.scrollUntilVisible(
          find.text('Temperature', skipOffstage: false),
          150,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axis == Axis.vertical,
              )
              .first,
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expectWhole(tester, find.text('Temperature'));
      });
    }
  }

  group('the open stage is always in view at 320dp, 2x text', () {
    List<StagePill> pills(WidgetTester tester) =>
        tester.widgetList<StagePill>(find.byType(StagePill)).toList();

    void expectOpenInView(WidgetTester tester, int stage) {
      final all = pills(tester);
      expect(all.map((p) => p.selected), [
        for (var i = 0; i < 3; i++) i == stage,
      ]);
      final rect = tester.getRect(find.byWidget(all[stage]));
      expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$rect');
      expect(rect.right, lessThanOrEqualTo(320.5), reason: '$rect');
    }

    for (final stage in [0, 1, 2]) {
      testWidgets('tapping stage $stage', (tester) async {
        await open(tester, 320, 2.0);
        // Drying starts beyond the edge, where no tap can reach it: the row
        // is scrolled by hand first, as a person would, then tapped.
        var rect = tester.getRect(find.byWidget(pills(tester)[stage]));
        if (rect.left > 300) {
          await tester.drag(
            find.byType(StagePill).first,
            const Offset(-200, 0),
          );
          await tester.pumpAndSettle();
          rect = tester.getRect(find.byWidget(pills(tester)[stage]));
        }
        final visible = Rect.fromLTRB(
          rect.left.clamp(0, 320),
          rect.top,
          rect.right.clamp(0, 320),
          rect.bottom,
        );
        await tester.tapAt(visible.center);
        await tester.pumpAndSettle();

        expectOpenInView(tester, stage);
      });

      testWidgets('swiping to stage $stage', (tester) async {
        await open(tester, 320, 2.0);
        for (var i = 0; i < stage; i++) {
          await tester.fling(
            find.byType(TabBarView),
            const Offset(-300, 0),
            1500,
          );
          await tester.pumpAndSettle();
        }

        expectOpenInView(tester, stage);
      });
    }

    testWidgets('a tap on a partly hidden pill opens that pill, not its '
        'neighbour', (tester) async {
      await open(tester, 320, 2.0);
      final washing = tester.getRect(find.byWidget(pills(tester)[1]));
      // Washing is clipped by the right edge: its visible sliver is Washing.
      expect(washing.right, greaterThan(320));
      await tester.tapAt(Offset((washing.left + 320) / 2, washing.center.dy));
      await tester.pumpAndSettle();

      expect(pills(tester).map((p) => p.selected), [false, true, false]);
    });
  });
}
