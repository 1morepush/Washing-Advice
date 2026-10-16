/// Laundry at large text: nothing loses a letter.
///
/// At 1.6x the three stage pills used to read "Baske…", "Wash…" and "Dryin…",
/// their counts gone, and the load card's label column broke "Temperature"
/// into "Temperat" and "ure". A name cut in half is worse than a name that
/// needs a scroll, so these pin the words whole across widths and text sizes.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/main.dart';
import 'package:washing_advice/widgets/rinse_kit.dart';

import '../support/fixtures.dart';

/// Page padding, card padding and block padding either side of a label.
const _cardInset = 96.0;

void main() {
  late ProviderContainer container;

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
  void expectWhole(WidgetTester tester, Finder finder, double width) {
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
        // The test font is far wider than Nunito, so a word may exceed the
        // card itself; it must then fill the card, not a fixed column.
        greaterThanOrEqualTo(math.min(painter.width, width - _cardInset) - 0.5),
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
          if (scale > 1.3) expectWhole(tester, label, width);
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
        expectWhole(tester, find.text('Temperature'), width);
      });
    }
  }
}
