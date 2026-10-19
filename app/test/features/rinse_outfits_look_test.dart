/// How Outfits, Ask and More look in each of the three appearances.
///
/// The behaviour of these screens is covered beside each feature. What is held
/// here is what the Rinse look promises and a plain finder cannot see: the two
/// sources of outfit can be told apart in every mode, and the two sides of a
/// conversation do not share a colour.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/features/chat/chat_screen.dart';
import 'package:washing_advice/features/more/more_screen.dart';
import 'package:washing_advice/features/outfits/outfit_source.dart';
import 'package:washing_advice/widgets/rinse_kit.dart';

import '../support/contrast.dart';

final _themes = <String, ThemeData Function()>{
  'light': AppTheme.light,
  'dark': AppTheme.dark,
  'amoled': AppTheme.amoled,
};

void main() {
  for (final MapEntry(key: mode, value: build) in _themes.entries) {
    group('in $mode', () {
      final theme = build();
      final scheme = theme.colorScheme;

      testWidgets('the two outfit sources are told apart, and readable', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: Column(
                children: [
                  OutfitCard(source: OutfitSource.wardrobe, child: Text('a')),
                  OutfitCard(source: OutfitSource.stylist, child: Text('b')),
                ],
              ),
            ),
          ),
        );

        // The labels carry their own words and their own colours.
        expect(find.text('From your wardrobe'), findsOneWidget);
        expect(find.text('Stylist idea'), findsOneWidget);
        const wardrobe = OutfitSource.wardrobe;
        const stylist = OutfitSource.stylist;
        // Told apart by hue (blue against amber), not by lightness: the two
        // fills are both deliberately soft, so luminance alone says little.
        double hue(Color c) => HSLColor.fromColor(c).hue;
        final apart =
            (hue(wardrobe.accent(scheme)) - hue(stylist.accent(scheme))).abs();
        expect(
          apart > 90 && apart < 270,
          isTrue,
          reason: 'the two accents must be different hues, got $apart',
        );
        expect(
          wardrobe.container(scheme),
          isNot(equals(stylist.container(scheme))),
        );
        for (final source in OutfitSource.values) {
          expect(
            contrastBetween(
              source.onContainer(scheme),
              source.container(scheme),
            ),
            greaterThan(4.5),
            reason: '${source.label} must be readable on its own fill',
          );
        }

        // And the card behind the stylist's is washed, the wardrobe's is not.
        final cards = tester.widgetList<Card>(find.byType(Card)).toList();
        expect(cards, hasLength(2));
        expect(cards[0].color, isNull);
        expect(cards[1].color, isNot(equals(scheme.surfaceContainerLowest)));

        // No outline of its own: only the theme's edge, which is none outside
        // true black.
        final shape = cards[1].shape! as RoundedRectangleBorder;
        expect(shape.side, theme.extension<RinseShape>()!.cardEdge);
      });

      testWidgets('More is one grouped card of four places', (tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: theme, home: const MoreScreen()),
        );

        expect(find.byType(GroupCard), findsOneWidget);
        for (final place in ['Ask', 'Packing', 'Insights', 'Settings']) {
          expect(find.text(place), findsOneWidget);
        }
      });

      testWidgets('Ask: my bubble is the accent, theirs is a card', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [
            wardrobeRepositoryProvider.overrideWithValue(
              InMemoryWardrobeRepository(),
            ),
            eventLogProvider.overrideWithValue(InMemoryEventLog()),
            aiGatewayProvider.overrideWithValue(_Gateway()),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(theme: theme, home: const ChatScreen()),
          ),
        );
        await tester.enterText(find.byType(TextField), 'my question');
        await tester.tap(find.byIcon(Icons.arrow_upward));
        await tester.pumpAndSettle();

        Color? fillBehind(String text) {
          final box = tester.widget<Container>(
            find
                .ancestor(of: find.text(text), matching: find.byType(Container))
                .first,
          );
          return (box.decoration! as BoxDecoration).color;
        }

        final mine = fillBehind('my question')!;
        final theirs = fillBehind('A reply.')!;
        expect(mine, scheme.primary);
        expect(theirs, scheme.surfaceContainerLowest);
        expect(
          contrastBetween(scheme.onPrimary, mine),
          greaterThan(4.5),
          reason: 'my text must be readable on the accent',
        );
        expect(
          contrastBetween(scheme.onSurface, theirs),
          greaterThan(4.5),
          reason: 'their text must be readable on the card',
        );
        // Against the page, theirs is a shadow in Light, a lighter fill in
        // Dark and a hairline in AMOLED, where the fill is the page's black.
        final lifted =
            theirs != scheme.surface ||
            theme.extension<RinseShape>()!.cardEdge != BorderSide.none;
        expect(lifted, isTrue);
      });
    });
  }
}

class _Gateway extends AiGateway {
  _Gateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  @override
  Future<String> askQuestion({
    required String question,
    required List<WardrobeItem> wardrobe,
    List<({bool fromUser, String text})> history = const [],
  }) async => 'A reply.';
}
