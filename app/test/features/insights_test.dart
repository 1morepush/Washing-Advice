/// The insights screen.
///
/// What is under test is that the screen shows the core's figures and does not
/// invent its own. The figures themselves are covered exhaustively by
/// `analytics_test.dart` in the core, and asserting them again here would pin
/// the same behaviour in two places.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/insights/insights_screen.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty wardrobe invites a first garment', (tester) async {
    // Rather than a screen of zeroes, which reads as broken to someone who has
    // simply not started.
    await pump(tester);

    expect(find.text('Nothing to measure yet'), findsOneWidget);
    expect(find.text('Add a garment'), findsOneWidget);
  });

  testWidgets('readiness leads, because it is the actionable number', (
    tester,
  ) async {
    await repository.saveAll([
      confidentItem(id: 'tee', name: 'White tee'),
      guessedItem(id: 'mystery', name: 'Mystery shirt'),
    ]);

    await pump(tester);

    expect(find.text('Ready to sort'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    // And it offers the next step rather than only stating the problem.
    expect(find.text('Scan the next label'), findsOneWidget);
  });

  testWidgets('a fully catalogued wardrobe says so', (tester) async {
    await repository.saveAll([confidentItem(id: 'tee', name: 'White tee')]);

    await pump(tester);

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Scan the next label'), findsNothing);
  });

  testWidgets('spend is shown per currency, never summed', (tester) async {
    // The screen must not paper over the core's refusal to invent a rate.
    await repository.saveAll([
      confidentItem(
        id: 'tee',
        name: 'Tee',
        purchase: PurchaseInfo(priceMinorUnits: 2500, currencyCode: 'EUR'),
      ),
      confidentItem(
        id: 'jeans',
        name: 'Jeans',
        type: ItemType.jeans,
        purchase: PurchaseInfo(priceMinorUnits: 8000, currencyCode: 'USD'),
      ),
    ]);

    await pump(tester);

    // A card each, not 105 of something. They get their own row precisely
    // because the count of currencies is not fixed and a fourth column
    // truncated them.
    expect(find.text('25 EUR'), findsOneWidget);
    expect(find.text('80 USD'), findsOneWidget);
  });

  testWidgets('never worn is reported separately from long unworn', (
    tester,
  ) async {
    await repository.saveAll([
      confidentItem(
        id: 'never',
        name: 'Never worn',
        usage: const UsageStats.none(),
      ),
      confidentItem(
        id: 'idle',
        name: 'Idle jumper',
        type: ItemType.sweater,
        usage: UsageStats(
          timesWorn: 4,
          lastWornAt: DateTime.now().subtract(const Duration(days: 200)),
        ),
      ),
    ]);

    await pump(tester);

    expect(find.text('NEVER WORN (1)'), findsOneWidget);
    expect(find.text('NOT WORN IN THREE MONTHS'), findsOneWidget);
  });

  group('the figures line up as one band', () {
    /// The card behind a stat's label.
    Size cardAround(WidgetTester tester, String label) => tester.getSize(
      find.ancestor(of: find.text(label), matching: find.byType(Card)).first,
    );

    testWidgets('the three counts are the same height', (tester) async {
      // Only one of these labels wraps to a second line — "wears recorded" —
      // and a `Row` centres children of different heights rather than
      // levelling them, so that one card grew and the row read as misaligned.
      await repository.saveAll([
        confidentItem(id: 'a', name: 'A'),
        confidentItem(id: 'b', name: 'B'),
      ]);
      tester.view.physicalSize = const Size(390, 3000);

      await pump(tester);

      expect(
        cardAround(tester, 'items').height,
        cardAround(tester, 'wears recorded').height,
      );
      expect(
        cardAround(tester, 'washes').height,
        cardAround(tester, 'wears recorded').height,
      );
    });

    testWidgets('a single currency fills the width like every other row', (
      tester,
    ) async {
      // The gap between cards used to be emitted after each one including the
      // last, leaving this row a gap short of the right edge while the cards
      // above and below it ran the full width.
      await repository.saveAll([
        confidentItem(
          id: 'priced',
          name: 'Priced',
          usage: const UsageStats(timesWorn: 2),
          purchase: PurchaseInfo(
            priceMinorUnits: 4500,
            currencyCode: 'EUR',
            purchasedAt: DateTime.now(),
          ),
        ),
      ]);
      tester.view.physicalSize = const Size(390, 3000);

      await pump(tester);

      expect(
        cardAround(tester, 'spent').width,
        // The full-width card directly above it, made of three cards and two
        // gaps — the same span this one row should cover on its own.
        cardAround(tester, 'items').width +
            cardAround(tester, 'wears recorded').width +
            cardAround(tester, 'washes').width +
            24,
      );
    });
  });
}
