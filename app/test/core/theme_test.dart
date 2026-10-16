/// The three looks the app can wear, and that the third is really black.
///
/// "True black" is a claim about pixels, and it fails quietly: `#0A0A0A` looks
/// the same as `#000000` in a bright room and is a lit pixel on exactly the
/// screens the theme exists for. So the first group below checks the values
/// rather than the look, and the rest check the things that would make a black
/// ground unusable — cards with no edge, containers that merge into it, an app
/// bar that turns grey when a list passes under it.
///
/// Light and Dark are held to "still what they were". Adding a third look
/// reached into the code that builds both, and nothing about the third was
/// supposed to change either of them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/core/theme.dart';

import '../support/contrast.dart';

const _black = Color(0xFF000000);

void main() {
  final amoled = AppTheme.amoled();
  final dark = AppTheme.dark();
  final light = AppTheme.light();

  group('true black', () {
    test('is black where it is meant to be, and not merely nearly black', () {
      expect(amoled.colorScheme.surface, _black);
      expect(amoled.scaffoldBackgroundColor, _black);
      expect(amoled.appBarTheme.backgroundColor, _black);
      expect(amoled.navigationBarTheme.backgroundColor, _black);
    });

    test('shows the selected place on the bar: pill 3:1, icon 4.5:1', () {
      final pill = amoled.navigationBarTheme.indicatorColor!;
      expect(contrastBetween(pill, _black), greaterThanOrEqualTo(3));
      expect(
        contrastBetween(amoled.colorScheme.onSecondaryContainer, pill),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('is still a dark theme to everything that asks', () {
      // Material picks light or dark system icons, text selection colours and
      // a good deal else from this.
      expect(amoled.brightness, Brightness.dark);
    });

    test('differs from Dark in the surfaces and in nothing else', () {
      // Put Dark's seven surface roles back and what is left must be Dark.
      // Written this way round so that it restates none of the near-blacks —
      // and so that an accent or a text colour changed along the way, which
      // is the quiet kind of mistake, has nowhere to hide.
      final scheme = amoled.colorScheme;
      final restored = scheme.copyWith(
        surface: dark.colorScheme.surface,
        surfaceDim: dark.colorScheme.surfaceDim,
        surfaceContainerLowest: dark.colorScheme.surfaceContainerLowest,
        surfaceContainerLow: dark.colorScheme.surfaceContainerLow,
        surfaceContainer: dark.colorScheme.surfaceContainer,
        surfaceContainerHigh: dark.colorScheme.surfaceContainerHigh,
        surfaceContainerHighest: dark.colorScheme.surfaceContainerHighest,
      );

      expect(restored, dark.colorScheme);
    });

    test('has containers that climb from black in steps, and stay dark', () {
      final scheme = amoled.colorScheme;
      final climb = [
        scheme.surfaceContainerLowest,
        scheme.surfaceContainerLow,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
      ];

      expect(climb.first, _black);
      for (var i = 1; i < climb.length; i++) {
        // Equal levels are no hierarchy, and a step under about 5% is one
        // nobody will see on a phone.
        expect(
          climb[i].computeLuminance(),
          greaterThan(climb[i - 1].computeLuminance()),
          reason: 'container $i is lighter than the one before it',
        );
        expect(
          contrastBetween(climb[i], climb[i - 1]),
          greaterThanOrEqualTo(1.05),
          reason: 'container $i is a visible step above the one before it',
        );
      }

      // The top of the climb is a shade above black. It is also darker than
      // anything Dark fills a surface with, which is the "no large grey areas"
      // half of the brief: a filled input here must not look like a panel.
      expect(
        contrastBetween(climb.last, _black),
        lessThan(1.6),
        reason: 'the lightest fill is a shade above black, not a grey',
      );
      expect(
        climb.last.computeLuminance(),
        lessThan(dark.colorScheme.surfaceContainerHighest.computeLuminance()),
      );
    });

    test('keeps the text soft, and still easy to read on black', () {
      // Pure white on black is glare with no gain in legibility. The seed's own
      // off-white is what Dark uses and what this must keep using.
      final text = amoled.colorScheme.onSurface;

      expect(text, isNot(const Color(0xFFFFFFFF)));
      expect(text, dark.colorScheme.onSurface);
      expect(contrastBetween(text, _black), greaterThanOrEqualTo(7));
    });

    test('fills an input far enough above black to see it', () {
      // The settings URL field, the chat box and the search field. A filled
      // input with no border is a rectangle of this colour and nothing else.
      final fill = amoled.inputDecorationTheme.fillColor!;

      expect(fill, amoled.colorScheme.surfaceContainerHighest);
      expect(contrastBetween(fill, _black), greaterThanOrEqualTo(1.2));
    });

    testWidgets('draws a card black, with an edge you can see', (tester) async {
      // Edges instead of lighter fills is the whole of how this theme keeps
      // things apart, so the edge has to be there and has to show on black.
      await tester.pumpWidget(
        MaterialApp(
          theme: amoled,
          home: const Scaffold(
            body: Center(child: Card(child: SizedBox(width: 80, height: 80))),
          ),
        ),
      );

      final card = tester.widget<Material>(
        find.descendant(of: find.byType(Card), matching: find.byType(Material)),
      );
      final edge = (card.shape! as RoundedRectangleBorder).side.color;

      expect(card.color, _black);
      expect(edge, amoled.colorScheme.outlineVariant);
      expect(contrastBetween(edge, _black), greaterThanOrEqualTo(2));
      expect(
        contrastBetween(edge, _black),
        greaterThanOrEqualTo(
          contrastBetween(
            dark.colorScheme.outlineVariant,
            dark.colorScheme.surface,
          ),
        ),
        reason: 'the edge shows at least as well as it does in Dark',
      );
    });

    group('an app bar with a list scrolling under it', () {
      /// The colour the bar is actually painted once the list has moved.
      ///
      /// What Material does with the bar's colour, its tint and its elevation,
      /// worked out the way Material does it rather than guessed from the
      /// theme: the question is what ends up on screen.
      Future<Color> paintedBar(WidgetTester tester, ThemeData theme) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              appBar: AppBar(title: const Text('Wardrobe')),
              body: ListView(
                children: [
                  for (var i = 0; i < 40; i++)
                    SizedBox(height: 80, child: Text('row $i')),
                ],
              ),
            ),
          ),
        );
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();

        final bar = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(AppBar),
                matching: find.byType(Material),
              )
              .first,
        );
        return ElevationOverlay.applySurfaceTint(
          bar.color!,
          bar.surfaceTintColor,
          bar.elevation,
        );
      }

      testWidgets('stays black', (tester) async {
        // The blue-grey band that the tint would paint across a black screen
        // is the thing this theme exists to avoid.
        expect(await paintedBar(tester, amoled), _black);
      });

      testWidgets('is tinted in Dark, so the check above can fail', (
        tester,
      ) async {
        // Without this the test above would pass just as happily if Material
        // had stopped tinting anything.
        expect(await paintedBar(tester, dark), isNot(dark.colorScheme.surface));
      });
    });
  });

  group('light and dark', () {
    // The seed, restated on purpose. Everything else in this file reads the
    // theme it is checking; this one is checking that the theme still *is* the
    // seed's, so it needs an answer that does not come from the theme. Changing
    // the brand colour should mean changing this line.
    const seed = Color(0xFF3F5B8C);

    test('are still the seed\'s own schemes, with nothing overridden', () {
      expect(
        light.colorScheme,
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
      );
      expect(
        dark.colorScheme,
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      );
    });

    test('keep Material\'s own card fill, bottom bar and scroll tint', () {
      // What the true-black adjustments switch off for black must be left on
      // for everything else.
      for (final theme in [light, dark]) {
        expect(theme.cardTheme.color, isNull);
        expect(theme.navigationBarTheme.backgroundColor, isNull);
        expect(theme.navigationBarTheme.indicatorColor, isNull);
        expect(
          theme.appBarTheme.surfaceTintColor,
          theme.colorScheme.surfaceTint,
        );
      }
    });
  });

  group('the choice', () {
    test('Match phone follows the phone, and the others do not', () {
      expect(Appearance.system.themeMode, ThemeMode.system);
      expect(Appearance.light.themeMode, ThemeMode.light);
      expect(Appearance.dark.themeMode, ThemeMode.dark);
      // Not a mode of the framework's own: it asks for dark and is handed a
      // darker one.
      expect(Appearance.amoled.themeMode, ThemeMode.dark);
    });

    test('is dark by the ordinary dark, except for AMOLED', () {
      // Match phone must still hand a phone in dark mode the ordinary dark;
      // only the true-black choice swaps it.
      for (final choice in Appearance.values) {
        final expected = choice == Appearance.amoled ? amoled : dark;
        expect(
          choice.darkTheme.colorScheme.surface,
          expected.colorScheme.surface,
          reason: choice.name,
        );
      }
    });

    test('tells the browser which surface to put under the page', () {
      final lightSurface = light.colorScheme.surface;
      final darkSurface = dark.colorScheme.surface;

      // Match phone leaves it to the phone, so each mode keeps its own.
      expect(Appearance.system.surfaces, (
        whenLight: lightSurface,
        whenDark: darkSurface,
      ));
      // An explicit look is the same whatever the phone says, which is the
      // point of choosing one.
      expect(Appearance.light.surfaces, (
        whenLight: lightSurface,
        whenDark: lightSurface,
      ));
      expect(Appearance.dark.surfaces, (
        whenLight: darkSurface,
        whenDark: darkSurface,
      ));
      expect(Appearance.amoled.surfaces, (
        whenLight: amoled.colorScheme.surface,
        whenDark: amoled.colorScheme.surface,
      ));
    });
  });
}
