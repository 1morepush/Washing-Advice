/// The "Rinse" look in its three modes, pinned to the tokens the design was
/// signed off with, and held to the contrast a person needs to read it.
///
/// The hex values below are restated on purpose: this is the one place that
/// checks the theme *is* the design, so its answers must not come from the
/// theme. Changing a token should mean changing a line here.
///
/// AMOLED's claim of true black is a claim about pixels and fails quietly
/// (`#0A0A0A` looks the same in a bright room), so it is checked as a value.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/theme.dart';

import '../support/contrast.dart';

const _black = Color(0xFF000000);

void main() {
  final light = AppTheme.light();
  final dark = AppTheme.dark();
  final amoled = AppTheme.amoled();
  final modes = {'light': light, 'dark': dark, 'amoled': amoled};

  group('the tokens', () {
    test('Light is the signed-off palette', () {
      final s = light.colorScheme;
      expect(s.brightness, Brightness.light);
      expect(s.surface, const Color(0xFFEEF4F8));
      expect(s.surfaceContainerLowest, const Color(0xFFFFFFFF));
      expect(s.surfaceContainerHighest, const Color(0xFFE2ECF4));
      expect(s.onSurface, const Color(0xFF0F2236));
      expect(s.onSurfaceVariant, const Color(0xFF5A6B7C));
      expect(s.outlineVariant, const Color(0xFFD3DEE8));
      expect(s.primary, const Color(0xFF1E73C8));
      expect(s.onPrimary, const Color(0xFFFFFFFF));
      expect(s.primaryContainer, const Color(0xFFD8E8F8));
      expect(s.tertiaryContainer, const Color(0xFFFFF0D3));
      expect(s.tertiary, const Color(0xFF6A4300));
      final rinse = light.extension<RinseShape>()!;
      expect(rinse.well, const Color(0xFFE5EEF5));
      expect(rinse.lineSoft, const Color(0xFFE3EAF1));
      final stages = light.extension<LaundryStageColors>()!;
      expect(stages.basket, const Color(0xFFE3A63F));
      expect(stages.onBasket, const Color(0xFF2A1A00));
      expect(stages.wash, const Color(0xFF1E73C8));
      expect(stages.dry, const Color(0xFF3FA58A));
    });

    test('Dark is the signed-off palette', () {
      final s = dark.colorScheme;
      expect(s.brightness, Brightness.dark);
      expect(s.surface, const Color(0xFF0C1620));
      expect(s.surfaceContainerLowest, const Color(0xFF132230));
      expect(s.surfaceContainerHighest, const Color(0xFF1A2D3F));
      expect(s.onSurface, const Color(0xFFE5EEF6));
      expect(s.onSurfaceVariant, const Color(0xFF93A7BA));
      expect(s.outlineVariant, const Color(0xFF26394C));
      expect(s.primary, const Color(0xFF6CB6F5));
      expect(s.onPrimary, const Color(0xFF062238));
      expect(s.primaryContainer, const Color(0xFF163552));
      expect(dark.extension<RinseShape>()!.well, const Color(0xFF182A3B));
      final stages = dark.extension<LaundryStageColors>()!;
      expect(stages.basket, const Color(0xFFE9B85E));
      expect(stages.wash, const Color(0xFF6CB6F5));
      expect(stages.dry, const Color(0xFF6BC7A9));
      expect(stages.onDry, const Color(0xFF06261C));
    });

    test('AMOLED is black where it is meant to be, and not nearly black', () {
      expect(amoled.colorScheme.surface, _black);
      expect(amoled.scaffoldBackgroundColor, _black);
      expect(amoled.appBarTheme.backgroundColor, _black);
      expect(amoled.navigationBarTheme.backgroundColor, _black);
      expect(amoled.cardTheme.color, _black);
      expect(amoled.colorScheme.surfaceContainerLowest, _black);
      expect(amoled.brightness, Brightness.dark);
    });

    test('AMOLED keeps the signed-off accents and a soft white for text', () {
      final s = amoled.colorScheme;
      expect(s.onSurface, const Color(0xFFDCE7F1));
      expect(s.onSurface, isNot(const Color(0xFFFFFFFF)));
      expect(s.primary, const Color(0xFF5FA8EB));
      expect(s.surfaceContainerHighest, const Color(0xFF0B131B));
      expect(amoled.extension<RinseShape>()!.well, const Color(0xFF0D1620));
      final stages = amoled.extension<LaundryStageColors>()!;
      expect(stages.basket, const Color(0xFFD8A84E));
      expect(stages.onBasket, const Color(0xFF1C1200));
    });

    test('the radii are 22 for cards and 16 for tiles, in every mode', () {
      for (final MapEntry(:key, :value) in modes.entries) {
        final rinse = value.extension<RinseShape>()!;
        expect(rinse.cardRadius, 22, reason: key);
        expect(rinse.tileRadius, 16, reason: key);
      }
    });
  });

  group('shape', () {
    test('a card has a soft shadow and no edge in Light', () {
      final rinse = light.extension<RinseShape>()!;
      expect(rinse.cardEdge, BorderSide.none);
      expect(rinse.cardShadow, hasLength(2));
      expect(light.cardTheme.elevation, greaterThan(0));
    });

    test('a card is flat and edgeless in Dark, where a fill does the work', () {
      final rinse = dark.extension<RinseShape>()!;
      expect(rinse.cardEdge, BorderSide.none);
      expect(rinse.cardShadow, isEmpty);
      expect(dark.cardTheme.elevation, 0);
    });

    test('a card has a one-pixel hairline in AMOLED', () {
      final rinse = amoled.extension<RinseShape>()!;
      expect(rinse.cardEdge.width, 1);
      expect(rinse.cardEdge.color, const Color(0xFF1D2A37));
      expect(
        contrastBetween(rinse.cardEdge.color, _black),
        greaterThanOrEqualTo(1.2),
        reason: 'the edge is there to be seen on black',
      );
      expect(rinse.cardShadow, isEmpty);
    });

    test('buttons, chips and the bar\'s pill are pills', () {
      for (final theme in modes.values) {
        expect(
          theme.filledButtonTheme.style!.shape!.resolve({}),
          isA<StadiumBorder>(),
        );
        expect(theme.chipTheme.shape, isA<StadiumBorder>());
        expect(theme.navigationBarTheme.indicatorShape, isA<StadiumBorder>());
      }
    });

    test('inputs have no outline, except on black where the fill is dim', () {
      for (final MapEntry(:key, :value) in modes.entries) {
        final enabled =
            value.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
        expect(
          enabled.borderSide.style == BorderStyle.none,
          key != 'amoled',
          reason: key,
        );
      }
    });

    test('titles are 26 / 800 and the app bar does not tint when scrolled', () {
      for (final theme in modes.values) {
        expect(theme.appBarTheme.titleTextStyle!.fontSize, 26);
        expect(theme.appBarTheme.titleTextStyle!.fontWeight, FontWeight.w800);
        expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
      }
    });

    test('all type is Nunito, with a floor on how small it gets', () {
      for (final theme in modes.values) {
        expect(theme.textTheme.bodyMedium!.fontFamily, rinseFontFamily);
        expect(theme.textTheme.headlineMedium!.fontSize, 26);
        expect(theme.textTheme.bodySmall!.fontSize, greaterThanOrEqualTo(13));
        expect(theme.textTheme.labelSmall!.fontSize, greaterThanOrEqualTo(12));
      }
    });

    testWidgets('AMOLED draws a card black with an edge you can see', (
      tester,
    ) async {
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
      expect(card.color, _black);
      final shape = card.shape! as RoundedRectangleBorder;
      expect(shape.side.color, const Color(0xFF1D2A37));
      expect(shape.borderRadius, BorderRadius.circular(22));
    });

    testWidgets('Light draws a card white and round with no edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: light,
          home: const Scaffold(
            body: Center(child: Card(child: SizedBox(width: 80, height: 80))),
          ),
        ),
      );
      final card = tester.widget<Material>(
        find.descendant(of: find.byType(Card), matching: find.byType(Material)),
      );
      expect(card.color, const Color(0xFFFFFFFF));
      final shape = card.shape! as RoundedRectangleBorder;
      expect(shape.side, BorderSide.none);
      expect(shape.borderRadius, BorderRadius.circular(22));
    });
  });

  group('contrast, in every mode', () {
    for (final MapEntry(key: name, value: theme) in modes.entries) {
      group(name, () {
        final s = theme.colorScheme;
        final bg = s.surface;
        final card = s.surfaceContainerLowest;
        final stages = theme.extension<LaundryStageColors>()!;
        final rinse = theme.extension<RinseShape>()!;
        final grounds = [bg, card, rinse.well, s.surfaceContainerHighest];

        test('body text is 4.5:1 on the ground, the card and a tile', () {
          for (final ground in grounds) {
            expect(
              contrastBetween(s.onSurface, ground),
              greaterThanOrEqualTo(4.5),
            );
          }
        });

        test('muted text is 4.5:1 on the ground, the card and a tile', () {
          for (final ground in grounds) {
            expect(
              contrastBetween(s.onSurfaceVariant, ground),
              greaterThanOrEqualTo(4.5),
            );
          }
        });

        test(
          'a switch is on a visible track with a visible thumb, off or on',
          () {
            final sw = theme.switchTheme;
            final off = sw.trackColor!.resolve({})!;
            final thumb = sw.thumbColor!.resolve({})!;
            // The surfaces a switch sits on: the page and a card.
            for (final ground in [bg, card]) {
              expect(
                contrastBetween(off, ground),
                greaterThanOrEqualTo(1.3),
                reason: '$name track on $ground',
              );
            }
            expect(contrastBetween(thumb, off), greaterThanOrEqualTo(3));
            // No drawn outline when off, except AMOLED's hairline.
            final outline = sw.trackOutlineColor!.resolve({})!;
            expect(
              outline == Colors.transparent ||
                  rinse.cardEdge != BorderSide.none,
              isTrue,
            );
            // On is the accent, with the on-accent thumb.
            expect(sw.trackColor!.resolve({WidgetState.selected}), s.primary);
            expect(
              contrastBetween(
                sw.thumbColor!.resolve({WidgetState.selected})!,
                s.primary,
              ),
              greaterThanOrEqualTo(3),
            );
          },
        );

        test('accent as TEXT (a text button) is 4.5:1 on every ground', () {
          final ink = theme.textButtonTheme.style!.foregroundColor!.resolve(
            {},
          )!;
          for (final ground in grounds) {
            expect(
              contrastBetween(ink, ground),
              greaterThanOrEqualTo(4.5),
              reason: '$name on $ground',
            );
          }
        });

        test('the accent is 3:1 against the ground, and its label 4.5:1', () {
          expect(contrastBetween(s.primary, bg), greaterThanOrEqualTo(3));
          expect(
            contrastBetween(s.onPrimary, s.primary),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastBetween(s.onPrimaryContainer, s.primaryContainer),
            greaterThanOrEqualTo(4.5),
          );
        });

        test('the text on each stage colour is 4.5:1', () {
          expect(
            contrastBetween(stages.onBasket, stages.basket),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastBetween(stages.onWash, stages.wash),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastBetween(stages.onDry, stages.dry),
            greaterThanOrEqualTo(4.5),
          );
        });

        test('the confidence colours can be read on their containers', () {
          for (final band in ConfidenceBand.values) {
            expect(
              contrastBetween(
                s.onConfidenceContainer(band),
                s.confidenceContainer(band),
              ),
              greaterThanOrEqualTo(4.5),
              reason: '$band',
            );
          }
          // As text on the ground itself.
          expect(contrastBetween(s.error, bg), greaterThanOrEqualTo(4.5));
          expect(contrastBetween(s.tertiary, bg), greaterThanOrEqualTo(4.5));
        });

        test('the selected place on the bar is told apart by icon and label, '
            'not by the pill alone', () {
          // The pill is a soft wash (as in the design), well under 3:1 on the
          // bar. What carries the selection is the filled icon in the deep
          // accent and the label in full ink, both 4.5:1 on the bar; the
          // unselected places are muted outlines.
          final nav = theme.navigationBarTheme;
          final bar = nav.backgroundColor!;
          final pill = nav.indicatorColor!;
          final selectedIcon = nav.iconTheme!.resolve({
            WidgetState.selected,
          })!.color!;
          final selectedLabel = nav.labelTextStyle!.resolve({
            WidgetState.selected,
          })!.color!;
          final idleLabel = nav.labelTextStyle!.resolve({})!.color!;

          expect(
            contrastBetween(selectedIcon, pill),
            greaterThanOrEqualTo(4.5),
          );
          expect(contrastBetween(selectedIcon, bar), greaterThanOrEqualTo(4.5));
          expect(
            contrastBetween(selectedLabel, bar),
            greaterThanOrEqualTo(4.5),
          );
          expect(contrastBetween(idleLabel, bar), greaterThanOrEqualTo(4.5));
          expect(selectedLabel, isNot(idleLabel));
          expect(pill, isNot(bar));
        });
      });
    }
  });

  group('the choice', () {
    test('Match phone follows the phone, and the others do not', () {
      expect(Appearance.system.themeMode, ThemeMode.system);
      expect(Appearance.light.themeMode, ThemeMode.light);
      expect(Appearance.dark.themeMode, ThemeMode.dark);
      expect(Appearance.amoled.themeMode, ThemeMode.dark);
    });

    test('is dark by the ordinary dark, except for AMOLED', () {
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
      expect(Appearance.system.surfaces, (
        whenLight: lightSurface,
        whenDark: darkSurface,
      ));
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

  group('stage colours', () {
    test('map a lifecycle state, and only the three laundry stages', () {
      final stages = light.extension<LaundryStageColors>()!;
      expect(stages.colorOf(LifecycleState.inLaundry), stages.basket);
      expect(stages.colorOf(LifecycleState.beingWashed), stages.wash);
      expect(stages.colorOf(LifecycleState.beingDried), stages.dry);
      expect(stages.colorOf(LifecycleState.active), isNull);
      expect(stages.onColorOf(LifecycleState.beingDried), stages.onDry);
    });
  });
}
