/// The price: looking it up, checking it, adding to it, and choosing it.
///
/// The price is what the screen is for, and nothing on it is a claim without
/// something behind it. So what these hold is the evidence trail: that a lookup
/// says how it went whatever the server did, that every price found is a link
/// to the page it came from, that what the person adds changes the suggestion,
/// that the suggestion says why, and that the figure at the end — what is left
/// after Depop's share — follows the price they actually typed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/features/sell/editor/price_results.dart';
import 'package:washing_advice/features/sell/editor/price_suggestion.dart';
import 'package:washing_advice/features/sell/editor/typed_prices.dart';

import '../../support/fixtures.dart';
import 'listing_editor_harness.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> type(WidgetTester tester, String label, String text) async {
    await tester.enterText(field(label), text);
    await tester.pump();
  }

  Future<void> lookUp(WidgetTester tester) async {
    await tester.tap(find.text('Look up prices'));
    await tester.pumpAndSettle();
  }

  Finder addPrice() => find.descendant(
    of: find.byType(TypedPrices),
    matching: find.widgetWithText(FilledButton, 'Add'),
  );

  /// Waits out the pause after the last change, so no save is left pending.
  Future<void> saved(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  const checkItYourself = 'Check it yourself';

  group('looking up prices', () {
    testWidgets('searches for the phrases in the boxes, which come from the '
        'listing', (tester) async {
      final listing = sampleListing(
        facts: ListingFacts(
          title: 'Nike vintage crewneck sweatshirt grey',
          itemType: ItemType.sweatshirt,
          searchQueries: const SearchQueries(
            depop: 'nike vintage crewneck grey',
            retail: 'nike club fleece crew grey',
          ),
        ),
      );
      final app = await openEditor(tester, listing: listing, size: tallScreen);

      expect(
        tester.widget<TextField>(field('Search Depop for')).controller!.text,
        'nike vintage crewneck grey',
      );
      expect(
        tester.widget<TextField>(field('Search shops for')).controller!.text,
        'nike club fleece crew grey',
      );

      await lookUp(tester);

      expect(app.gateway.searched.single['queries'], {
        'depop': 'nike vintage crewneck grey',
        'retail': 'nike club fleece crew grey',
      });
    });

    testWidgets('searches for what the person changed them to', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await type(tester, 'Search Depop for', 'nike 90s crewneck');
      await type(tester, 'Search shops for', 'nike club fleece crew');
      await lookUp(tester);

      expect(app.gateway.searched.single['queries'], {
        'depop': 'nike 90s crewneck',
        'retail': 'nike club fleece crew',
      });
      // And what they wrote is kept, to be searched with again.
      final stored = (await app.stored('draft-1'))!;
      expect(stored.editedQueries!.depop, 'nike 90s crewneck');
    });

    testWidgets('follows the title until the person writes their own', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(title: 'Nike crewneck'),
        size: tallScreen,
      );
      String depop() =>
          tester.widget<TextField>(field('Search Depop for')).controller!.text;
      expect(depop(), 'Nike crewneck');

      await type(tester, 'Title', 'Nike 90s crewneck grey');
      expect(depop(), 'Nike 90s crewneck grey');

      // Theirs from the moment they type in it: later edits to the title do not
      // overwrite it.
      await type(tester, 'Search Depop for', 'my own words');
      await type(tester, 'Title', 'Nike something else entirely');
      expect(depop(), 'my own words');
      await saved(tester);
    });

    testWidgets('shows the stored result of a search that was run', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );
      expect(find.textContaining('Not looked up yet'), findsOneWidget);

      await lookUp(tester);

      expect(find.textContaining('Prices checked'), findsOneWidget);
      expect(
        find.text('Vintage Nike grey crewneck sweatshirt'),
        findsOneWidget,
      );
      // On the listing, so it is still there when it is opened again.
      final stored = (await app.stored('draft-1'))!;
      expect(stored.priceSearch, app.gateway.search);
      await saved(tester);
    });

    testWidgets('shows that it is working, and then why it is taking long', (
      tester,
    ) async {
      final gateway = FakePriceGateway()..hold = Completer<void>();
      await openEditor(
        tester,
        listing: sampleListing(),
        gateway: gateway,
        size: tallScreen,
      );

      await tester.tap(find.text('Look up prices'));
      await tester.pump();

      expect(find.text('Looking up prices…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('The server sleeps'), findsNothing);
      // The button is not pressed twice.
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Looking up prices…'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );

      await tester.pump(wakingAfter + const Duration(seconds: 1));
      expect(find.textContaining('The server sleeps'), findsOneWidget);

      gateway.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Look up prices'), findsOneWidget);
      expect(find.textContaining('The server sleeps'), findsNothing);
      await saved(tester);
    });

    testWidgets('says why when it needs something first', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(title: ''),
        size: tallScreen,
      );

      expect(
        find.text('Add a title first. The search uses it.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Look up prices'),
            )
            .onPressed,
        isNull,
      );

      await type(tester, 'Title', 'Nike crewneck grey');
      expect(find.text('Add a title first. The search uses it.'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Look up prices'),
            )
            .onPressed,
        isNotNull,
      );
      await saved(tester);
    });

    testWidgets('wants a phrase of at least three letters in each box', (
      tester,
    ) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      await type(tester, 'Search shops for', 'ab');

      expect(
        find.text('Each search phrase needs at least 3 letters.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Look up prices'),
            )
            .onPressed,
        isNull,
      );
      await saved(tester);
    });

    testWidgets('says when the server could not be reached, and keeps the '
        'listing', (tester) async {
      final gateway = FakePriceGateway()
        ..error = const ScanFailure('The server is asleep.');
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        gateway: gateway,
        size: tallScreen,
      );

      await lookUp(tester);

      expect(find.text('The server is asleep.'), findsOneWidget);
      expect(find.text('Look up prices'), findsOneWidget);
      expect((await app.stored('draft-1'))!.priceSearch, isNull);
      await saved(tester);
    });
  });

  group('what the search says, by how it went', () {
    const messages = {
      PriceSearchStatus.notConfigured:
          "Live price search isn't set up on this server yet. It needs a "
          'free Tavily key on the server (see the README). Meanwhile, check '
          'the links below.',
      PriceSearchStatus.quotaExceeded:
          'The free price-search allowance is used up for now. Check the '
          'links below, or try again later.',
      PriceSearchStatus.unavailable:
          "The price search didn't answer. Try again.",
    };

    for (final status in messages.keys) {
      testWidgets('${status.name} has its own sentence', (tester) async {
        await openEditor(
          tester,
          listing: sampleListing(priceSearch: sampleSearch(status: status)),
          size: tallScreen,
        );

        expect(find.text(messages[status]!), findsOneWidget);
        for (final other in messages.keys.where((other) => other != status)) {
          expect(find.text(messages[other]!), findsNothing);
        }
        expect(find.textContaining('Prices checked'), findsNothing);
        // What would be on the page if the search had answered.
        expect(find.text('On Depop'), findsNothing);
      });

      testWidgets('${status.name} keeps Check it yourself', (tester) async {
        await openEditor(
          tester,
          listing: sampleListing(priceSearch: sampleSearch(status: status)),
          size: tallScreen,
        );

        expect(find.text(checkItYourself), findsOneWidget);
        expect(find.text('Depop search'), findsOneWidget);
        expect(find.text('eBay sold listings'), findsOneWidget);
        expect(find.text('Google Shopping'), findsOneWidget);
      });

      testWidgets('${status.name} is what a lookup shows when the server says '
          'so', (tester) async {
        final gateway = FakePriceGateway(search: sampleSearch(status: status));
        final app = await openEditor(
          tester,
          listing: sampleListing(),
          gateway: gateway,
          size: tallScreen,
        );

        await lookUp(tester);

        expect(find.text(messages[status]!), findsOneWidget);
        // Kept, with the phrases it tried.
        expect((await app.stored('draft-1'))!.priceSearch!.status, status);
        await saved(tester);
      });
    }

    testWidgets('ok says when the prices were checked, and what was found', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(priceSearch: sampleSearch()),
        size: tallScreen,
      );

      expect(find.text('Prices checked 2 hours ago'), findsOneWidget);
      expect(find.text('On Depop'), findsOneWidget);
      expect(find.text('New in shops'), findsOneWidget);
      expect(find.text(checkItYourself), findsOneWidget);
    });

    testWidgets('ok says "just now" for a search that has just run', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(
          priceSearch: sampleSearch(at: DateTime.now().toUtc()),
        ),
        size: tallScreen,
      );

      expect(find.text('Prices checked just now'), findsOneWidget);
    });

    testWidgets('ok shows each comparable with what is known of it', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(priceSearch: sampleSearch()),
        size: tallScreen,
      );

      expect(
        find.text('Vintage Nike grey crewneck sweatshirt'),
        findsOneWidget,
      );
      expect(find.text(r'$32.00'), findsOneWidget);
      expect(find.text('Sold'), findsOneWidget);
      expect(find.text('For sale'), findsOneWidget);
      // In the tile, and not the chip of the same name in the condition.
      expect(
        find.descendant(
          of: find.byType(PriceResults),
          matching: find.text('Used - Good'),
        ),
        findsOneWidget,
      );
      expect(find.text('Same item'), findsNWidgets(3));
      expect(find.text('Same Nike crewneck, also grey'), findsOneWidget);
      expect(find.text('Same Nike crewneck, still for sale'), findsOneWidget);
    });

    testWidgets('ok says when a page does not say whether it sold', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(
          priceSearch: sampleSearch(
            comparables: [
              SaleComparable(
                title: 'Nike hoodie',
                url: Uri.parse('https://www.depop.com/products/x/'),
                priceCents: 2500,
                match: ComparableMatch.similar,
              ),
            ],
          ),
        ),
        size: tallScreen,
      );

      expect(find.text('Status unknown'), findsOneWidget);
      expect(find.text('Similar'), findsOneWidget);
      expect(find.text('Sold'), findsNothing);
      expect(find.text('For sale'), findsNothing);
    });

    testWidgets('ok shows what it costs new, and where', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(priceSearch: sampleSearch()),
        size: tallScreen,
      );

      expect(find.text('Nike Club Fleece crew sweatshirt'), findsOneWidget);
      expect(find.text(r'$65.00'), findsOneWidget);
      expect(find.text('nike.com'), findsOneWidget);
    });

    testWidgets('ok says what was left out, naming only what was', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(
          priceSearch: sampleSearch(
            excluded: const ExcludedCounts(notUsd: 2, notComparable: 4),
          ),
        ),
        size: tallScreen,
      );

      expect(
        find.text('Not shown: 2 not in US dollars, 4 not alike'),
        findsOneWidget,
      );
    });

    testWidgets('ok names all three reasons when there are three', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(
          priceSearch: sampleSearch(
            excluded: const ExcludedCounts(
              notUsd: 2,
              unverifiedPrice: 1,
              notComparable: 4,
            ),
          ),
        ),
        size: tallScreen,
      );

      expect(
        find.text(
          'Not shown: 2 not in US dollars, 1 price not on the page, '
          '4 not alike',
        ),
        findsOneWidget,
      );
    });

    testWidgets('ok says nothing about what was left out when nothing was', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(priceSearch: sampleSearch()),
        size: tallScreen,
      );

      expect(find.textContaining('Not shown'), findsNothing);
    });

    testWidgets('ok with nothing usable says so, which is not the same as '
        'not looking', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(
          priceSearch: sampleSearch(
            comparables: const [],
            retail: const [],
            excluded: const ExcludedCounts(notComparable: 5),
          ),
        ),
        size: tallScreen,
      );

      expect(
        find.text(
          'The search found nothing usable for these phrases. Try different '
          'words, or check the links below.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Not looked up yet'), findsNothing);
      expect(find.text('Not shown: 5 not alike'), findsOneWidget);
      expect(find.text('On Depop'), findsNothing);
      expect(find.text(checkItYourself), findsOneWidget);
    });

    testWidgets('ok with only shop prices says what is missing on Depop', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(
          priceSearch: sampleSearch(comparables: const []),
        ),
        size: tallScreen,
      );

      expect(find.text('No usable Depop listings.'), findsOneWidget);
      expect(find.text('Nike Club Fleece crew sweatshirt'), findsOneWidget);
    });
  });

  group('looking again', () {
    testWidgets('keeps the earlier prices when the new search fails, and '
        'says so', (tester) async {
      final checked = DateTime.utc(2026, 10, 12, 9);
      final listing = sampleListing(priceSearch: sampleSearch(at: checked));
      final gateway = FakePriceGateway(
        search: sampleSearch(status: PriceSearchStatus.unavailable),
      );
      final app = await openEditor(
        tester,
        listing: listing,
        gateway: gateway,
        size: tallScreen,
      );

      await lookUp(tester);

      expect(
        find.text(
          "The new search didn't answer — showing prices checked Oct 12, 2026.",
        ),
        findsOneWidget,
      );
      // The earlier prices are still the ones on the page, and in the store.
      expect(
        find.text('Vintage Nike grey crewneck sweatshirt'),
        findsOneWidget,
      );
      expect(find.textContaining('Prices checked'), findsOneWidget);
      expect((await app.stored('draft-1'))!.priceSearch, listing.priceSearch);
      await saved(tester);
    });

    testWidgets('replaces them when the new search found prices', (
      tester,
    ) async {
      final gateway = FakePriceGateway(
        search: sampleSearch(
          comparables: [
            SaleComparable(
              title: 'A newer find',
              url: Uri.parse('https://www.depop.com/products/new/'),
              priceCents: 2200,
              sold: true,
              match: ComparableMatch.same,
            ),
          ],
        ),
      );
      await openEditor(
        tester,
        listing: sampleListing(
          priceSearch: sampleSearch(at: DateTime.utc(2026, 10, 1)),
        ),
        gateway: gateway,
        size: tallScreen,
      );

      await lookUp(tester);

      expect(find.text('A newer find'), findsOneWidget);
      expect(find.text('Vintage Nike grey crewneck sweatshirt'), findsNothing);
      expect(find.textContaining("The new search didn't answer"), findsNothing);
      await saved(tester);
    });

    testWidgets('stops saying the new search failed when the next one works', (
      tester,
    ) async {
      final gateway = FakePriceGateway(
        search: sampleSearch(status: PriceSearchStatus.quotaExceeded),
      );
      await openEditor(
        tester,
        listing: sampleListing(priceSearch: sampleSearch()),
        gateway: gateway,
        size: tallScreen,
      );
      await lookUp(tester);
      expect(
        find.textContaining("The new search didn't answer"),
        findsOneWidget,
      );

      gateway.search = sampleSearch(at: DateTime.now().toUtc());
      await lookUp(tester);

      expect(find.textContaining("The new search didn't answer"), findsNothing);
      expect(find.text('Prices checked just now'), findsOneWidget);
      await saved(tester);
    });
  });

  group('the links', () {
    testWidgets('on a Depop listing open its page', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(priceSearch: sampleSearch()),
        size: tallScreen,
      );

      await tester.tap(find.text('Vintage Nike grey crewneck sweatshirt'));
      await tester.pump();

      expect(app.links.opened, [
        Uri.parse('https://www.depop.com/products/example-1/'),
      ]);
    });

    testWidgets('on a shop price open the shop\'s page', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(priceSearch: sampleSearch()),
        size: tallScreen,
      );

      await tester.tap(find.text('Nike Club Fleece crew sweatshirt'));
      await tester.pump();

      expect(
        app.links.last,
        Uri.parse('https://www.nike.com/t/club-fleece-crew'),
      );
    });

    testWidgets('to check it yourself open the same searches', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(
          editedQueries: const SearchQueries(
            depop: "Levi's & Co 501",
            retail: 'levis 501 new',
          ),
        ),
        size: tallScreen,
      );

      await tester.tap(find.text('Depop search'));
      await tester.tap(find.text('eBay sold listings'));
      await tester.tap(find.text('Google Shopping'));
      await tester.pump();

      expect(app.links.opened, [
        depopSearchLink("Levi's & Co 501"),
        ebaySoldLink("Levi's & Co 501"),
        googleShoppingLink("Levi's & Co 501"),
      ]);
      // The ampersand is part of the phrase, not a second parameter.
      expect(app.links.opened.first.queryParameters['q'], "Levi's & Co 501");
    });

    testWidgets('search for the phrase as it is now in the box', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await type(tester, 'Search Depop for', 'nike 90s crewneck');
      await tester.tap(find.text('Depop search'));
      await tester.pump();

      expect(app.links.last, depopSearchLink('nike 90s crewneck'));
      await saved(tester);
    });

    testWidgets('say why eBay is there', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      expect(
        find.textContaining('show what things actually sold for'),
        findsOneWidget,
      );
    });

    testWidgets('say so when one will not open', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(priceSearch: sampleSearch()),
        size: tallScreen,
      );
      app.links.succeeds = false;

      await tester.tap(find.text('eBay sold listings'));
      await tester.pump();

      expect(find.text("That link couldn't be opened."), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('prices the person found', () {
    testWidgets('are added in dollars, listed, and stored', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await type(tester, 'A price you saw', r'$32.50');
      await tester.tap(addPrice());
      await tester.pump();
      await type(tester, 'A price you saw', '28');
      await tester.tap(addPrice());
      await tester.pump();

      expect(find.widgetWithText(InputChip, r'$32.50'), findsOneWidget);
      expect(find.widgetWithText(InputChip, r'$28.00'), findsOneWidget);
      // The box is ready for the next.
      expect(
        tester.widget<TextField>(field('A price you saw')).controller!.text,
        isEmpty,
      );
      await saved(tester);
      expect((await app.stored('draft-1'))!.typedComparableCents, [3250, 2800]);
    });

    testWidgets('are not added when they are not a price', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await type(tester, 'A price you saw', '0');
      await tester.tap(addPrice());
      await tester.pump();

      expect(find.text('Use an amount like 32 or 32.50.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TypedPrices),
          matching: find.byType(InputChip),
        ),
        findsNothing,
      );
      await type(tester, 'A price you saw', '5');
      expect(find.text('Use an amount like 32 or 32.50.'), findsNothing);
      await saved(tester);
      expect((await app.stored('draft-1'))!.typedComparableCents, isEmpty);
    });

    testWidgets('are removed by their chip', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(typedComparableCents: const [3250, 2800]),
        size: tallScreen,
      );

      await tester.tap(find.byTooltip(r'Remove $32.50'));
      await saved(tester);

      expect(find.widgetWithText(InputChip, r'$32.50'), findsNothing);
      expect((await app.stored('draft-1'))!.typedComparableCents, [2800]);
    });

    testWidgets('are said to have sold or not by one switch for all', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(typedComparableCents: const [3250, 2800]),
        size: tallScreen,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'These sold'),
            )
            .value,
        isFalse,
      );

      await tester.tap(find.text('These sold'));
      await saved(tester);

      expect((await app.stored('draft-1'))!.typedComparablesSold, isTrue);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'These sold'),
            )
            .value,
        isTrue,
      );
    });
  });

  group('the suggestion', () {
    testWidgets('says there is nothing to go on, and offers no price', (
      tester,
    ) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      expect(find.text('Suggested price'), findsOneWidget);
      expect(
        find.text('No prices found yet — check the links to Depop and eBay.'),
        findsOneWidget,
      );
      expect(find.textContaining('Use \$'), findsNothing);
    });

    testWidgets('is large, with its range and every reason', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(priceSearch: sampleSearch()),
        size: tallScreen,
      );
      final suggestion = suggestionFor(
        sampleListing(priceSearch: sampleSearch()),
      );
      expect(suggestion.listPriceCents, 3000);

      // The figure, in the biggest type on the screen.
      final figure = find.text(r'$30.00').last;
      expect(figure, findsOneWidget);
      expect(
        tester.widget<Text>(figure).style!.fontSize,
        greaterThan(
          Theme.of(tester.element(figure)).textTheme.titleLarge!.fontSize!,
        ),
      );
      expect(
        find.text('Prices seen range from \$28.00 to \$32.00.'),
        findsOneWidget,
      );
      for (final reason in suggestion.reasons) {
        expect(find.text(reason), findsOneWidget, reason: reason);
      }
      expect(suggestion.reasons, isNotEmpty);
    });

    testWidgets('sets the price when it is used, and the payout follows', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(priceSearch: sampleSearch()),
        size: tallScreen,
      );
      expect(find.textContaining("You get"), findsNothing);

      await tester.tap(find.text(r'Use $30.00'));
      await tester.pump();

      expect(
        tester.widget<TextField>(field('Your price')).controller!.text,
        '30',
      );
      expect(
        find.text("You get \$28.56 after Depop's fees (3.3% + \$0.45)"),
        findsOneWidget,
      );
      await saved(tester);
      expect((await app.stored('draft-1'))!.priceCents, 3000);
    });

    testWidgets('can no longer be used once it is the price', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(priceSearch: sampleSearch(), priceCents: 3000),
        size: tallScreen,
      );

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, r'Use $30.00'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text("That's the price you have."), findsOneWidget);
    });

    testWidgets('changes when a sold price is added', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);
      expect(find.textContaining('Use \$'), findsNothing);

      // Two prices seen, asked: the middle of them, $30.
      await type(tester, 'A price you saw', '32');
      await tester.tap(addPrice());
      await tester.pump();
      await type(tester, 'A price you saw', '28');
      await tester.tap(addPrice());
      await tester.pump();
      expect(find.text(r'Use $30.00'), findsOneWidget);

      // Said to be what they sold for, the same two prices are worth more: the
      // middle of the sales, asked 12% above for offers.
      await tester.tap(find.text('These sold'));
      await tester.pump();

      expect(find.text(r'Use $30.00'), findsNothing);
      expect(find.text(r'Use $35.00'), findsOneWidget);
      expect(
        find.text('Asking 12% above that leaves room for offers.'),
        findsOneWidget,
      );
      await saved(tester);
    });

    testWidgets('uses what was found and what was typed together', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(
          priceSearch: sampleSearch(),
          typedComparableCents: const [2400],
          typedComparablesSold: true,
        ),
        size: tallScreen,
      );

      final suggestion = suggestionFor(
        sampleListing(
          priceSearch: sampleSearch(),
          typedComparableCents: const [2400],
          typedComparablesSold: true,
        ),
      );
      // Two of the three are sales, which is enough to price from sales alone.
      expect(suggestion.basis, PriceBasis.soldComparables);
      expect(suggestion.comparablesUsed, 2);
      for (final reason in suggestion.reasons) {
        expect(find.text(reason), findsOneWidget, reason: reason);
      }
    });

    testWidgets('ignores a search that did not answer', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(
          priceSearch: sampleSearch(status: PriceSearchStatus.unavailable),
        ),
        size: tallScreen,
      );

      expect(
        find.text('No prices found yet — check the links to Depop and eBay.'),
        findsOneWidget,
      );
    });

    testWidgets('says what the garment cost when it was bought in dollars', (
      tester,
    ) async {
      final garment = confidentItem(
        id: 'sweat',
        name: 'Grey crewneck',
        type: ItemType.sweatshirt,
        purchase: const PurchaseInfo(
          priceMinorUnits: 4000,
          currencyCode: 'USD',
        ),
      );
      await openEditor(
        tester,
        listing: sampleListing(itemId: garment.id, priceSearch: sampleSearch()),
        garments: [garment],
        size: tallScreen,
      );

      expect(find.text(r'You paid $40.00.'), findsOneWidget);
    });

    testWidgets('says nothing of what it cost in another currency', (
      tester,
    ) async {
      final garment = confidentItem(
        id: 'sweat',
        name: 'Grey crewneck',
        type: ItemType.sweatshirt,
        purchase: const PurchaseInfo(
          priceMinorUnits: 4000,
          currencyCode: 'EUR',
        ),
      );
      await openEditor(
        tester,
        listing: sampleListing(itemId: garment.id, priceSearch: sampleSearch()),
        garments: [garment],
        size: tallScreen,
      );

      expect(find.textContaining('You paid'), findsNothing);
    });

    testWidgets('does not look for a garment a listing is not made from', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(priceSearch: sampleSearch()),
        size: tallScreen,
      );

      expect(find.textContaining('You paid'), findsNothing);
    });
  });

  group('the paid price', () {
    test('is only counted in US dollars', () {
      WardrobeItem bought(String currency, int minor) => confidentItem(
        id: 'x',
        name: 'x',
        purchase: PurchaseInfo(priceMinorUnits: minor, currencyCode: currency),
      );

      expect(paidCentsOf(bought('USD', 4000)), 4000);
      expect(paidCentsOf(bought('usd', 4000)), 4000);
      expect(paidCentsOf(bought('EUR', 4000)), isNull);
      expect(paidCentsOf(bought('USD', 0)), isNull);
      expect(paidCentsOf(confidentItem(id: 'x', name: 'x')), isNull);
      expect(paidCentsOf(null), isNull);
    });
  });

  group('your price', () {
    testWidgets('shows what is left after Depop\'s fees, as it is typed', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );
      expect(find.textContaining("Type the price you'll ask"), findsOneWidget);

      await type(tester, 'Your price', '30');

      expect(
        find.text("You get \$28.56 after Depop's fees (3.3% + \$0.45)"),
        findsOneWidget,
      );
      await type(tester, 'Your price', '45.50');
      expect(
        find.text(
          "You get ${formatUsd(DepopFees.us.netCents(4550))} after Depop's "
          'fees (3.3% + \$0.45)',
        ),
        findsOneWidget,
      );
      await saved(tester);
      expect((await app.stored('draft-1'))!.priceCents, 4550);
    });

    testWidgets('says when the fees were last checked', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(priceCents: 3000),
        size: tallScreen,
      );

      expect(
        find.text("Fees as of Oct 17, 2026 — check Depop's fee page."),
        findsOneWidget,
      );
    });

    testWidgets('is taken back when the box is emptied', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(priceCents: 3000),
        size: tallScreen,
      );

      await type(tester, 'Your price', '');
      await saved(tester);

      expect(find.textContaining('You get'), findsNothing);
      expect((await app.stored('draft-1'))!.priceCents, isNull);
    });

    testWidgets('keeps the last price while a new one is on its way', (
      tester,
    ) async {
      // "0" is not a price, and "0.75" is.
      final app = await openEditor(
        tester,
        listing: sampleListing(priceCents: 3000),
        size: tallScreen,
      );

      await type(tester, 'Your price', '0');
      await type(tester, 'Your price', '0.7');
      await type(tester, 'Your price', '0.75');
      await saved(tester);

      expect((await app.stored('draft-1'))!.priceCents, 75);
    });

    testWidgets('warns when too little is left to be worth the postage', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(priceCents: 500),
        size: tallScreen,
      );

      final net = DepopFees.us.netCents(500);
      expect(net, lessThan(500));
      expect(
        find.textContaining(
          "You'd get only ${formatUsd(net)} after Depop's fees",
        ),
        findsOneWidget,
      );
    });

    testWidgets('does not warn about a price that leaves enough', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(priceCents: 3000),
        size: tallScreen,
      );

      expect(find.textContaining('worth the postage'), findsNothing);
      expect(find.textContaining('worth bundling'), findsNothing);
      expect(find.textContaining('may be worth it'), findsNothing);
    });

    testWidgets('warns about a suggestion that would leave too little', (
      tester,
    ) async {
      // A single comparable at $5 suggests $5, which leaves $4.38.
      await openEditor(
        tester,
        listing: sampleListing(
          typedComparableCents: const [500],
          typedComparablesSold: false,
        ),
        size: tallScreen,
      );

      final suggestion = suggestionFor(
        sampleListing(typedComparableCents: const [500]),
      );
      expect(suggestion.belowWorthwhileNet, isTrue);
      expect(
        find.textContaining(
          'The suggested price would leave only '
          '${formatUsd(suggestion.netCents!)}',
        ),
        findsOneWidget,
      );
    });
  });

  group('the sections around it', () {
    testWidgets('are not disturbed by typing in the boxes', (tester) async {
      // The boxes are the same boxes after a lookup: their text is not rebuilt
      // from the listing each time it is stored.
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );
      await type(tester, 'Your price', '42');
      final before = tester.widget<TextField>(field('Your price')).controller;

      await lookUp(tester);

      expect(
        tester.widget<TextField>(field('Your price')).controller,
        same(before),
      );
      expect(before!.text, '42');
      await saved(tester);
      expect((await app.stored('draft-1'))!.priceCents, 4200);
    });
  });
}
