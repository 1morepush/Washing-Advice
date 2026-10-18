/// The listing editor as a whole: finding the listing, the description that is
/// pasted into Depop, leaving, and deleting.
///
/// The editor has no Save button and no Post button, so what these hold is the
/// part nobody sees being done: that the text on screen is exactly the text
/// that is copied, that going Back does not lose a word, and that a listing
/// somebody deletes is gone.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/features/sell/editor/description_section.dart';
import 'package:washing_advice/features/sell/listing_editor_screen.dart';
import 'package:washing_advice/features/sell/sell_screen.dart';

import 'listing_editor_harness.dart';

void main() {
  group('a listing that is not there', () {
    testWidgets('says so plainly, with a way back to Sell', (tester) async {
      await openEditor(tester, location: '/listing/gone', size: tallScreen);

      expect(find.byType(ListingEditorScreen), findsOneWidget);
      expect(find.text('This listing no longer exists'), findsOneWidget);

      await tester.tap(find.text('Back to Sell'));
      await tester.pumpAndSettle();

      expect(find.byType(SellScreen), findsOneWidget);
    });

    testWidgets('has the arrow, too', (tester) async {
      await openEditor(tester, location: '/listing/gone', size: tallScreen);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(SellScreen), findsOneWidget);
    });
  });

  group('the description', () {
    testWidgets('is the one the core composes, exactly', (tester) async {
      final listing = sampleListing();
      await openEditor(tester, listing: listing, size: tallScreen);

      final preview = tester.widget<SelectableText>(
        find.descendant(
          of: find.byType(DescriptionSection),
          matching: find.byType(SelectableText),
        ),
      );

      expect(preview.data, composeDescription(listing));
      // And it is the whole of it: the title is the first line, and the details
      // follow.
      expect(preview.data, startsWith('Nike vintage crewneck sweatshirt grey'));
      expect(preview.data, contains('Brand: Nike'));
    });

    testWidgets('can be selected, and not typed in', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      final preview = find.descendant(
        of: find.byType(DescriptionSection),
        matching: find.byType(SelectableText),
      );

      expect(preview, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DescriptionSection),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );
    });

    testWidgets("shows Depop's two counters", (tester) async {
      final listing = sampleListing();
      await openEditor(tester, listing: listing, size: tallScreen);

      final text = composeDescription(listing);
      final check = checkDescription(text);

      expect(
        find.text('${check.length} / 1,000 characters'),
        findsOneWidget,
        reason: 'the length of the text being pasted',
      );
      expect(find.text('${check.hashtagCount} / 5 hashtags'), findsOneWidget);
    });

    testWidgets('stops at the limit, and writes it as Depop does', (
      tester,
    ) async {
      // The composer never goes past a thousand characters, even for a title
      // of two thousand: it cuts, and ends in an ellipsis. The counter reads
      // the limit with its comma, as Depop's own does.
      final listing = sampleListing(title: 'Nike ${'crewneck ' * 250}');
      await openEditor(tester, listing: listing, size: tallScreen);

      expect(composeDescription(listing), hasLength(depopDescriptionLimit));
      expect(find.text('1,000 / 1,000 characters'), findsOneWidget);
    });

    testWidgets('turns the counter to the error colour, and says by how much, '
        'when there are too many hashtags', (tester) async {
      // Hashtags typed into the notes are a person's own and count against
      // Depop's five, however many the composer leaves out.
      final listing = sampleListing().copyWith(
        notes: '#one #two #three #four #five #six #seven',
      );
      await openEditor(tester, listing: listing, size: tallScreen);

      final count = checkDescription(composeDescription(listing)).hashtagCount;
      expect(count, greaterThan(depopHashtagLimit));

      final counter = find.text(
        '$count / 5 hashtags — ${count - depopHashtagLimit} over',
      );
      expect(counter, findsOneWidget);
      expect(
        tester.widget<Text>(counter).style?.color,
        Theme.of(tester.element(counter)).colorScheme.error,
      );
    });

    testWidgets('puts exactly that text on the clipboard, and says so', (
      tester,
    ) async {
      final listing = sampleListing();
      final clipboard = ClipboardSpy(tester);
      await openEditor(tester, listing: listing, size: tallScreen);

      await tester.tap(find.text('Copy description'));
      await tester.pump();

      expect(clipboard.text, composeDescription(listing));
      expect(
        find.text("Copied — paste it into Depop's description"),
        findsOneWidget,
      );
      // Let the message go, so no timer is left pending.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('has nothing to copy while it has nothing in it', (
      tester,
    ) async {
      final blank = Listing(
        id: const ListingId('blank'),
        createdAt: DateTime.utc(2026, 10, 15),
        updatedAt: DateTime.utc(2026, 10, 15),
      );
      await openEditor(tester, listing: blank, size: tallScreen);

      expect(find.textContaining('Nothing to paste yet'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Copy description'),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('deleting', () {
    testWidgets('asks first, and Cancel keeps the listing', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await tester.tap(find.text('Delete listing'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this listing?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(ListingEditorScreen), findsOneWidget);
      expect(await app.stored('draft-1'), isNotNull);
    });

    testWidgets('removes the listing, and goes back to Sell', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await tester.tap(find.text('Delete listing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(await app.stored('draft-1'), isNull);
      expect(find.byType(SellScreen), findsOneWidget);
      expect(find.byType(ListingEditorScreen), findsNothing);
      // Not the screen that says it is gone: the person asked for this.
      expect(find.text('This listing no longer exists'), findsNothing);
    });

    testWidgets('is always available, even while prices are being looked up', (
      tester,
    ) async {
      final gateway = FakePriceGateway()..hold = Completer<void>();
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        gateway: gateway,
        size: tallScreen,
      );
      await tester.tap(find.text('Look up prices'));
      await tester.pump();
      expect(find.text('Looking up prices…'), findsOneWidget);

      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Delete listing'),
            )
            .onPressed,
        isNotNull,
      );
      // By hand: the spinner of the look-up never lets the screen settle.
      await tester.tap(find.text('Delete listing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byType(SellScreen), findsOneWidget);
      expect(await app.stored('draft-1'), isNull);

      // The server answers after the listing has gone. It stays gone.
      gateway.hold!.complete();
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(await app.stored('draft-1'), isNull);
    });

    testWidgets('says the garment stays, for a listing made from one', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(itemId: const ItemId('sweat')),
        size: tallScreen,
      );

      await tester.tap(find.text('Delete listing'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The garment and its own photos stay'),
        findsOneWidget,
      );
    });
  });
}
