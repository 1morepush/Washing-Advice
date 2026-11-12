/// The shipping discount: the part of the buyer's postage the seller pays.
///
/// Depop's sell form has a box for it, and it comes off what the seller is
/// left with. What these hold is that the box is where a seller would look,
/// that what is typed is stored and survives Back, and that the figure the
/// editor shows is the core's — the same one the Sell list's cards use — so
/// the screens cannot tell a seller two different things about one sale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/theme.dart';

import 'listing_editor_harness.dart';

void main() {
  Finder box() => find.widgetWithText(TextField, 'Shipping discount you cover');

  Future<void> saved(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  String fees(String net, {String? discount}) =>
      "You get $net after Depop's fees (3.3% + \$0.45)"
      '${discount == null ? '' : ' and $discount shipping discount'}';

  group('the box', () {
    testWidgets('is in the Shipping section, with a line on what it does', (
      tester,
    ) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('shipping')),
          matching: box(),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "Optional. Pay part or all of the buyer's postage; it comes off "
          'what you get.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(box()).controller!.text, '');
    });

    testWidgets('shows what the listing holds', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(shippingDiscountCents: 450),
        size: tallScreen,
      );

      expect(tester.widget<TextField>(box()).controller!.text, '4.50');
    });

    testWidgets('does not suggest an amount or name any of Depop\'s tiers', (
      tester,
    ) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      expect(find.textContaining('tier'), findsNothing);
      expect(find.textContaining('Suggested discount'), findsNothing);
    });
  });

  group('typing in it', () {
    testWidgets('is stored, and changes what you get', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(priceCents: 3000),
        size: tallScreen,
      );
      expect(find.text(fees(r'$28.56')), findsOneWidget);

      await tester.enterText(box(), '4');
      await tester.pump();

      // $28.56 less $4.00, in the sentence Depop's fees are already in.
      expect(find.text(fees(r'$24.56', discount: r'$4.00')), findsOneWidget);
      await saved(tester);
      expect((await app.stored('draft-1'))!.shippingDiscountCents, 400);
    });

    testWidgets('takes cents, a dollar sign and a decimal comma', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(priceCents: 3000),
        size: tallScreen,
      );

      await tester.enterText(box(), r'$3,50');
      await tester.pump();
      await saved(tester);

      expect((await app.stored('draft-1'))!.shippingDiscountCents, 350);
      expect(find.text(fees(r'$25.06', discount: r'$3.50')), findsOneWidget);
    });

    testWidgets('emptying it takes the discount back', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(priceCents: 3000, shippingDiscountCents: 400),
        size: tallScreen,
      );
      expect(find.text(fees(r'$24.56', discount: r'$4.00')), findsOneWidget);

      await tester.enterText(box(), '');
      await tester.pump();
      await saved(tester);

      expect(find.text(fees(r'$28.56')), findsOneWidget);
      expect((await app.stored('draft-1'))!.shippingDiscountCents, isNull);
    });

    testWidgets('something that is not an amount is not stored', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(priceCents: 3000, shippingDiscountCents: 400),
        size: tallScreen,
      );

      // Zero is no discount, and says how to have none.
      await tester.enterText(box(), '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await saved(tester);

      expect(
        (await app.stored('draft-1'))!.shippingDiscountCents,
        400,
        reason: 'the last good amount stands',
      );
    });

    testWidgets('is kept when Back is pressed at once', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(priceCents: 3000),
        size: tallScreen,
      );

      await tester.enterText(box(), '2.25');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect((await app.stored('draft-1'))!.shippingDiscountCents, 225);
    });

    testWidgets('leaves the rest of the listing as it was', (tester) async {
      final before = sampleListing(priceCents: 3000);
      final app = await openEditor(tester, listing: before, size: tallScreen);

      await tester.enterText(box(), '4');
      await tester.pump();
      await saved(tester);

      final after = (await app.stored('draft-1'))!;
      expect(
        after.copyWith(
          clearShippingDiscount: true,
          updatedAt: before.updatedAt,
        ),
        before,
      );
    });
  });

  group('the net', () {
    testWidgets('is the core\'s, to the cent', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(priceCents: 4700, shippingDiscountCents: 899),
        size: tallScreen,
      );

      final sale = DepopFees.us.saleNet(4700, shippingDiscountCents: 899);
      expect(
        find.text(fees(formatUsd(sale.netCents), discount: formatUsd(899))),
        findsOneWidget,
      );
    });

    testWidgets('floors at nothing, and warns, when the discount is more', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(priceCents: 1000, shippingDiscountCents: 1500),
        size: tallScreen,
      );

      expect(find.text(fees(r'$0.00', discount: r'$15.00')), findsOneWidget);
      // $10.00 less $0.78 in fees is $9.22, and $15.00 is $5.78 more.
      expect(
        find.text(
          "Your shipping discount and Depop's fees come to more than the "
          "price. You'd get nothing and be \$5.78 out of pocket.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('asks about bundling when it leaves too little', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(priceCents: 3000, shippingDiscountCents: 2500),
        size: tallScreen,
      );

      // $28.56 less $25.00.
      expect(
        find.textContaining("You'd get only \$3.56 after Depop's fees"),
        findsOneWidget,
      );
    });

    testWidgets('is the same before and after the box is touched', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(priceCents: 3000),
        size: tallScreen,
      );

      await tester.enterText(box(), '4');
      await tester.pump();
      await tester.enterText(box(), '');
      await tester.pump();
      await saved(tester);

      expect(find.text(fees(r'$28.56')), findsOneWidget);
    });
  });

  group('when it sells', () {
    testWidgets('the price dialog and the finished sale count it', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(
          status: ListingStatus.listed,
          listedAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
          priceCents: 3000,
          shippingDiscountCents: 400,
        ),
        size: tallScreen,
      );

      await tester.tap(find.text('It sold'));
      await tester.pumpAndSettle();
      expect(
        find.text(fees(r'$24.56', discount: r'$4.00')),
        findsNWidgets(2),
        reason: 'once under the asking price, once in the dialog',
      );

      await tester.tap(find.text('Mark as sold'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "You got \$24.56 after Depop's fees (3.3% + \$0.45) and "
          '\$4.00 shipping discount',
        ),
        findsOneWidget,
      );
      expect((await app.stored('draft-1'))!.shippingDiscountCents, 400);
    });
  });

  group('on a small phone with large text', () {
    setUpAll(loadAppFont);

    for (final appearance in Appearance.values) {
      testWidgets('the box and its warning fit in ${appearance.name}', (
        tester,
      ) async {
        await openEditor(
          tester,
          listing: sampleListing(
            priceCents: 1000,
            shippingDiscountCents: 1234567,
          ),
          size: const Size(320, 640),
          textScale: 1.6,
          appearance: appearance,
        );

        await tester.ensureVisible(box());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.textContaining('out of pocket'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(
          find.textContaining('shipping discount').first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
